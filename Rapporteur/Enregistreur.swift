import AVFoundation
import Foundation

/// La capture native — la seule vraie raison d'être de l'application.
///
/// WebKit coupe le micro d'une page dès que l'application quitte l'écran :
/// une réunion d'une heure, téléphone posé écran éteint, donnerait une page
/// blanche. L'application enregistre donc elle-même :
///
///  - AVAudioEngine lit le micro ; chaque tampon est écrit dans un fichier
///    AAC (.m4a, 32 kbit/s mono — la parole, pas la musique), et son niveau
///    est mesuré pour le vu-mètre et l'avertisseur de silence de la page ;
///  - un ANNEAU garde les trois dernières minutes en PCM 16 kHz : c'est
///    l'extrait que la sonde de parole envoie au serveur (« zéro mot reconnu »
///    = micro muet ou noyé), encodé à la demande ;
///  - le mode audio en arrière-plan (Info.plist) et une session « record »
///    active tiennent la capture écran éteint ;
///  - les interruptions (appel entrant, changement d'écouteurs) relancent le
///    moteur dès qu'elles cessent.
///
/// La page reste maîtresse de tout le reste : sondes, file d'attente, envoi.
final class Enregistreur {

    enum Erreur: Error { case microRefuse, dejaEnCours, rienAEnregistrer, moteur(String) }

    private let moteur = AVAudioEngine()
    private var fichier: AVAudioFile?
    private(set) var urlFichier: URL?
    private var convertisseur: AVAudioConverter?
    private let formatAnneau = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    private var anneau: AnneauPCM
    /// L'anneau est écrit par le fil audio et lu par `extrait()` : un verrou.
    private let verrou = NSLock()
    private var enPause = false
    private(set) var enCours = false
    private let file = DispatchQueue(label: "com.lerapporteur.mobile.capture")
    private var observateurs: [NSObjectProtocol] = []

    /// Le niveau courant, déjà à l'échelle du vu-mètre de la page :
    /// racine du carré moyen × 4,5, borné à 1 (même formule que `niveau()`).
    private(set) var niveau: Float = 0

    init() {
        anneau = AnneauPCM(capacite: 16_000 * 180) // trois minutes
    }

    // MARK: - Démarrage

    func demarrer(_ suite: @escaping (Result<Void, Error>) -> Void) {
        guard !enCours else { suite(.failure(Erreur.dejaEnCours)); return }
        demanderMicro { accorde in
            guard accorde else { suite(.failure(Erreur.microRefuse)); return }
            self.file.async {
                do {
                    try self.lancer()
                    suite(.success(()))
                } catch {
                    suite(.failure(error))
                }
            }
        }
    }

    private func demanderMicro(_ suite: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { accorde in suite(accorde) }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { accorde in suite(accorde) }
        }
    }

    private func lancer() throws {
        let session = AVAudioSession.sharedInstance()
        /* « playAndRecord » et non « record » : la page joue le klaxon de
           l'avertisseur de silence. Mode « default » — surtout pas
           « voiceChat », dont l'annulation d'écho effacerait précisément les
           voix qui sortent d'un haut-parleur voisin. `mixWithOthers` laisse
           tourner la lecture d'une réunion rejouée sur ce même téléphone. */
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers])
        try session.setActive(true, options: [])

        let entree = moteur.inputNode
        let format = entree.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw Erreur.moteur("format d'entrée indisponible")
        }

        let dossier = FileManager.default.temporaryDirectory
        let url = dossier.appendingPathComponent("reunion-\(Int(Date().timeIntervalSince1970)).m4a")
        let reglages: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        // Le fichier reçoit des tampons au format du micro : AVAudioFile encode
        // en AAC au vol. Mono : on ne garde que le premier canal.
        let formatMono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate,
                                       channels: 1, interleaved: false)!
        fichier = try AVAudioFile(forWriting: url, settings: reglages,
                                  commonFormat: .pcmFormatFloat32, interleaved: false)
        urlFichier = url
        convertisseur = AVAudioConverter(from: formatMono, to: formatAnneau)
        verrou.lock(); anneau.vider(); verrou.unlock()
        enPause = false
        niveau = 0

        entree.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] tampon, _ in
            self?.traiter(tampon, formatMono: formatMono)
        }
        observerLesInterruptions()
        moteur.prepare()
        try moteur.start()
        enCours = true
    }

    // MARK: - Chaque tampon

    private func traiter(_ tampon: AVAudioPCMBuffer, formatMono: AVAudioFormat) {
        guard !enPause, let fichier = fichier else { niveau = 0; return }
        guard let mono = versMono(tampon, format: formatMono) else { return }

        // Le niveau : racine du carré moyen, puis la compression de la page.
        if let donnees = mono.floatChannelData?[0] {
            let n = Int(mono.frameLength)
            var somme: Float = 0
            for i in 0..<n { somme += donnees[i] * donnees[i] }
            let rms = n > 0 ? (somme / Float(n)).squareRoot() : 0
            niveau = min(1, rms * 4.5)
        }

        do { try fichier.write(from: mono) } catch { /* un tampon perdu, pas la séance */ }

        // L'anneau des trois dernières minutes, à 16 kHz.
        if let convertisseur = convertisseur {
            let capacite = AVAudioFrameCount(Double(mono.frameLength) * formatAnneau.sampleRate / formatMono.sampleRate) + 16
            guard let sortie = AVAudioPCMBuffer(pcmFormat: formatAnneau, frameCapacity: capacite) else { return }
            var servi = false
            var erreur: NSError?
            convertisseur.convert(to: sortie, error: &erreur) { _, statut in
                if servi { statut.pointee = .noDataNow; return nil }
                servi = true
                statut.pointee = .haveData
                return mono
            }
            if erreur == nil, let int16 = sortie.int16ChannelData?[0] {
                verrou.lock()
                anneau.ajouter(int16, Int(sortie.frameLength))
                verrou.unlock()
            }
        }
    }

    private func versMono(_ tampon: AVAudioPCMBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if tampon.format.channelCount == 1 && tampon.format.commonFormat == .pcmFormatFloat32 { return tampon }
        guard let source = tampon.floatChannelData?[0],
              let mono = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: tampon.frameLength),
              let cible = mono.floatChannelData?[0] else { return nil }
        mono.frameLength = tampon.frameLength
        cible.update(from: source, count: Int(tampon.frameLength))
        return mono
    }

    // MARK: - Pause, reprise, arrêt

    func pause() { file.async { self.enPause = true; self.niveau = 0 } }
    func reprendre() { file.async { self.enPause = false } }

    /// Clôt le fichier et le rend. La session audio est relâchée : le
    /// téléphone retrouve son comportement normal.
    func arreter() -> URL? {
        var url: URL?
        file.sync {
            guard enCours else { return }
            moteur.inputNode.removeTap(onBus: 0)
            moteur.stop()
            fichier = nil          // ferme et finalise le conteneur
            url = urlFichier
            enCours = false
            niveau = 0
            observateurs.forEach { NotificationCenter.default.removeObserver($0) }
            observateurs.removeAll()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        return url
    }

    /// Les trois dernières minutes, encodées en AAC 16 kHz — moins d'un
    /// mégaoctet, sous le plafond du serveur.
    func extrait() -> Data? {
        var resultat: Data?
        file.sync {
            verrou.lock()
            let echantillons = anneau.contenu()
            verrou.unlock()
            guard echantillons.count > 16_000 else { return } // moins d'une seconde : rien à juger
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("extrait-\(UUID().uuidString).m4a")
            let reglages: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 24_000,
            ]
            do {
                let sortie = try AVAudioFile(forWriting: url, settings: reglages,
                                             commonFormat: .pcmFormatInt16, interleaved: true)
                let pas = 16_000
                var debut = 0
                while debut < echantillons.count {
                    let n = min(pas, echantillons.count - debut)
                    guard let tampon = AVAudioPCMBuffer(pcmFormat: formatAnneau, frameCapacity: AVAudioFrameCount(n)),
                          let canal = tampon.int16ChannelData?[0] else { break }
                    echantillons.withUnsafeBufferPointer { p in
                        canal.update(from: p.baseAddress! + debut, count: n)
                    }
                    tampon.frameLength = AVAudioFrameCount(n)
                    try sortie.write(from: tampon)
                    debut += n
                }
            } catch { return }
            // AVAudioFile n'a pas de close() : le fichier se finalise à sa libération.
            resultat = try? Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
        }
        return resultat
    }

    // MARK: - Interruptions

    private func observerLesInterruptions() {
        let centre = NotificationCenter.default
        observateurs.append(centre.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: nil, queue: nil) { [weak self] avis in
            guard let self = self, self.enCours,
                  let brut = avis.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: brut) else { return }
            if type == .ended {
                // Un appel a pris le micro ; il le rend : on repart, sans geste.
                self.file.async { self.relancer() }
            }
        })
        observateurs.append(centre.addObserver(forName: .AVAudioEngineConfigurationChange,
                                               object: moteur, queue: nil) { [weak self] _ in
            guard let self = self, self.enCours else { return }
            self.file.async { self.relancer() }
        })
    }

    private func relancer() {
        guard enCours, !moteur.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        try? moteur.start()
    }
}

/// Un anneau d'échantillons Int16 : les N derniers, dans l'ordre.
struct AnneauPCM {
    private var tampon: [Int16]
    private var position = 0
    private var plein = false

    init(capacite: Int) { tampon = [Int16](repeating: 0, count: capacite) }

    mutating func vider() { position = 0; plein = false }

    mutating func ajouter(_ source: UnsafePointer<Int16>, _ n: Int) {
        for i in 0..<n {
            tampon[position] = source[i]
            position += 1
            if position == tampon.count { position = 0; plein = true }
        }
    }

    func contenu() -> [Int16] {
        if !plein { return Array(tampon[0..<position]) }
        return Array(tampon[position...]) + Array(tampon[..<position])
    }
}

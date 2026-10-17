import AVFoundation
import Foundation

/// Le micro de l'iPhone pour l'interprète vocal, quand des écouteurs ou des AirPods sont
/// branchés — demande de Felly (17/10/2026) : « avec ou sans écouteurs, Bluetooth ou
/// AirPods, que ce soit flexible et dynamique ».
///
/// Dès qu'une page ouvre un micro, WebKit règle la session audio avec `.allowBluetooth`
/// (mains libres) : iOS prend alors le micro des AirPods, qui entend mal la pièce. Avec des
/// écouteurs, la page n'ouvre donc aucun micro : l'application écoute ELLE-MÊME par le micro
/// de l'iPhone — `.allowBluetoothA2DP` sans `.allowBluetooth`, entrée intégrée préférée — et
/// remet le son à la page par morceaux de 16 bits à 48 kHz, une dizaine par seconde, comme
/// la prise de la réunion du panneau. La voix de l'interprète, que joue la page, va aux
/// écouteurs en haute qualité (A2DP). Rien n'est gardé : les morceaux passent, c'est tout.
final class MicroInterprete {

    /// Un morceau (base64, taux), sur le fil principal.
    var surMorceau: ((String, Int) -> Void)?
    /// La capture s'est arrêtée d'elle-même (appel, Siri, services audio relancés) :
    /// la page repasse à son micro, et redemande celui-ci au tour suivant.
    var surArret: (() -> Void)?

    private(set) var enCours = false

    private let moteur = AVAudioEngine()
    private let formatSortie = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000,
                                             channels: 1, interleaved: true)!
    private var convertisseur: AVAudioConverter?
    private var formatTap: AVAudioFormat?
    /// Un dixième de seconde à 48 kHz, en 16 bits.
    private let tailleMorceau = 9_600
    private var tampon = Data()
    private let verrou = NSLock()
    private var observateurs: [NSObjectProtocol] = []

    func demarrer() throws {
        if enCours { return }
        let session = AVAudioSession.sharedInstance()
        /* Mode « default », comme l'enregistreur : « voiceChat » repasserait aux
           mains libres. `mixWithOthers` : la voix de l'interprète, que joue la page,
           ne doit être ni coupée ni baissée par cette session. */
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers])
        try session.setActive(true, options: [])
        if let integre = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? session.setPreferredInput(integre)
        }
        try poserLeTap()
        observer()
        moteur.prepare()
        try moteur.start()
        enCours = true
    }

    func arreter() {
        guard enCours else { return }
        enCours = false
        observateurs.forEach { NotificationCenter.default.removeObserver($0) }
        observateurs = []
        moteur.inputNode.removeTap(onBus: 0)
        moteur.stop()
        formatTap = nil
        verrou.lock(); tampon.removeAll(); verrou.unlock()
    }

    /// Le tap au format COURANT du micro (il change avec la route : un appel, d'autres écouteurs).
    private func poserLeTap() throws {
        let entree = moteur.inputNode
        let format = entree.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate,
                                       channels: 1, interleaved: false) else {
            throw NSError(domain: "MicroInterprete", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "format d'entrée indisponible"])
        }
        if formatTap != nil { entree.removeTap(onBus: 0) }
        formatTap = format
        convertisseur = AVAudioConverter(from: mono, to: formatSortie)
        entree.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] tampon, _ in
            self?.traiter(tampon, mono: mono)
        }
    }

    private func traiter(_ source: AVAudioPCMBuffer, mono: AVAudioFormat) {
        guard enCours, let canal = source.floatChannelData?[0], let convertisseur = convertisseur,
              let entree = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: source.frameLength),
              let cible = entree.floatChannelData?[0] else { return }
        // Le premier canal seul : l'interprète écoute en mono.
        entree.frameLength = source.frameLength
        memcpy(cible, canal, Int(source.frameLength) * MemoryLayout<Float>.size)
        let capacite = AVAudioFrameCount(Double(source.frameLength) * formatSortie.sampleRate / mono.sampleRate) + 32
        guard let sortie = AVAudioPCMBuffer(pcmFormat: formatSortie, frameCapacity: capacite) else { return }
        var servi = false
        var erreur: NSError?
        convertisseur.convert(to: sortie, error: &erreur) { _, statut in
            if servi { statut.pointee = .noDataNow; return nil }
            servi = true
            statut.pointee = .haveData
            return entree
        }
        guard erreur == nil, sortie.frameLength > 0, let echantillons = sortie.int16ChannelData?[0] else { return }

        var prets: [Data] = []
        verrou.lock()
        tampon.append(Data(bytes: echantillons, count: Int(sortie.frameLength) * 2))
        while tampon.count >= tailleMorceau {
            prets.append(Data(tampon.prefix(tailleMorceau)))
            tampon.removeFirst(tailleMorceau)
        }
        verrou.unlock()
        guard !prets.isEmpty else { return }
        let taux = Int(formatSortie.sampleRate)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.enCours else { return }
            prets.forEach { self.surMorceau?($0.base64EncodedString(), taux) }
        }
    }

    private func observer() {
        let centre = NotificationCenter.default
        // Un appel, Siri : le moteur s'arrête ; la page reprend la main.
        observateurs.append(centre.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: nil, queue: .main) { [weak self] note in
            guard let brut = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: brut) == .began else { return }
            self?.lacher()
        })
        // La route a changé (écouteurs, appel) : le moteur se reconfigure, on le relance.
        observateurs.append(centre.addObserver(forName: .AVAudioEngineConfigurationChange,
                                               object: moteur, queue: .main) { [weak self] _ in
            guard let self = self, self.enCours else { return }
            do {
                try self.poserLeTap()
                self.moteur.prepare()
                try self.moteur.start()
            } catch {
                self.lacher()
            }
        })
        observateurs.append(centre.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.lacher()
        })
    }

    private func lacher() {
        guard enCours else { return }
        arreter()
        surArret?()
    }
}

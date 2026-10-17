import AVFoundation
import Foundation
import WebKit

/// Le seul pont entre la page et l'application — l'équivalent du preload
/// Electron et du `PontRapporteur` Android.
///
/// Côté page, `pont.js` (injecté au chargement) pose `window.rapporteurIOS`,
/// et `window.rapporteurAndroid` en alias : le site reconnaît ainsi une
/// « application mobile » sans rien changer à ses branches Android, et lit
/// `rapporteurIOS` là où l'iPhone diffère (capture native, textes).
///
/// Les appels sont asynchrones : la page poste `{id, action, params}`, et
/// l'application répond par `rapporteurIOS._repondre(id, réponse)` — les
/// données binaires (fichier, extrait) passent avant, par morceaux base64
/// (`_morceau`). Rien d'autre ne traverse : pas d'accès au système depuis la page.
final class Pont: NSObject, WKScriptMessageHandler {

    static let nom = "rapporteur"

    private weak var vue: WKWebView?
    private let enregistreur = Enregistreur()
    /// Le micro de l'iPhone pour l'interprète, avec des écouteurs ou des AirPods (1.1.13).
    private let microInterprete = MicroInterprete()
    /// Le temps que l'enregistreur démarre : une demande de l'interprète y attend sa copie (1.1.14).
    private var enregistrementEnDemarrage = false
    private var observateurRoute: NSObjectProtocol?
    private var minuterieNiveau: Timer?
    /// Les gros transferts (le fichier de la séance) passent un par un.
    private let fileEnvois = DispatchQueue(label: "com.lerapporteur.mobile.pont")

    var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    func attacher(a vue: WKWebView) {
        self.vue = vue
        vue.configuration.userContentController.add(self, name: Pont.nom)
        if let chemin = Bundle.main.url(forResource: "pont", withExtension: "js"),
           let source = try? String(contentsOf: chemin, encoding: .utf8) {
            let script = WKUserScript(source: source.replacingOccurrences(of: "__VERSION__", with: version),
                                      injectionTime: .atDocumentStart, forMainFrameOnly: true)
            vue.configuration.userContentController.addUserScript(script)
        }
        microInterprete.surMorceau = { [weak self] morceau, taux in
            self?.direMicroInterprete("recevoir", "'\(morceau)',\(taux)")
        }
        microInterprete.surArret = { [weak self] in self?.direMicroInterprete("arrete") }
        // Écouteurs branchés ou retirés : la page le sait aussitôt.
        observateurRoute = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in
            self?.pousserEcouteurs()
        }
    }

    func detacher() {
        vue?.configuration.userContentController.removeScriptMessageHandler(forName: Pont.nom)
        minuterieNiveau?.invalidate()
        enregistreur.surCopie = nil
        microInterprete.arreter()
        if let observateur = observateurRoute { NotificationCenter.default.removeObserver(observateur) }
    }

    var captureEnCours: Bool { enregistreur.enCours }

    /// La réunion tenue sur ce téléphone s'ouvre DANS l'application : le
    /// contrôleur pose le panneau du haut, ou le replie.
    var surOuvrirReunion: ((URL) -> Void)?
    var surFermerReunion: (() -> Void)?
    /// L'interprète et la réunion du panneau (1.1.13) : la salle demande le son des
    /// correspondants, la parole dans la réunion, et envoie la voix de l'interprète.
    var surSonReunion: ((Bool, Double) -> Void)?
    var surParoleReunion: ((Bool, Double) -> Void)?
    var surVoixReunion: ((String, Int) -> Void)?

    // MARK: - Réception

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        // Seule notre page parle au pont : une caisse de paiement embarquée
        // n'obtient rien.
        let hote = message.frameInfo.securityOrigin.host.lowercased()
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "https",
              [0, 443].contains(message.frameInfo.securityOrigin.port) else { return }
        guard hote == "lerapporteur.com" || hote == "www.lerapporteur.com" else { return }
        guard let corps = message.body as? [String: Any],
              let id = corps["id"] as? Int,
              let action = corps["action"] as? String else { return }
        let params = corps["params"] as? [String: Any] ?? [:]

        switch action {
        case "demarrer":
            /* Un seul micro pendant l'enregistrement (1.1.14) : l'interprète qui écoutait par
               celui de l'iPhone (écouteurs) passe sur la copie de celui du compte rendu, sans
               que la page ait à le redemander. */
            enregistrementEnDemarrage = true
            if microInterprete.enCours && !microInterprete.parCopie { brancherCopie() }
            enregistreur.demarrer { resultat in
                DispatchQueue.main.async {
                    self.enregistrementEnDemarrage = false
                    switch resultat {
                    case .success:
                        self.lancerLeNiveau()
                        self.repondre(id, ["ok": true])
                    case .failure(let erreur):
                        self.lacherLaCopie()
                        self.repondre(id, ["erreur": self.decrire(erreur)])
                    }
                }
            }
        case "pause":
            enregistreur.pause(); repondre(id, ["ok": true])
        case "reprendre":
            enregistreur.reprendre(); repondre(id, ["ok": true])
        case "extrait":
            fileEnvois.async {
                let donnees = self.enregistreur.extrait()
                DispatchQueue.main.async {
                    if let donnees = donnees {
                        self.envoyerParMorceaux(id, donnees) { self.repondre(id, ["ok": true]) }
                    } else {
                        self.repondre(id, ["ok": true]) // rien à juger : la page n'enverra pas de sonde
                    }
                }
            }
        case "arreter":
            minuterieNiveau?.invalidate()
            // L'interprète écoutait la copie : la session reste ouverte, sa voix ne se coupe pas.
            let garder = microInterprete.parCopie
            fileEnvois.async {
                let url = self.enregistreur.arreter(garderSession: garder)
                // Il repasse à son micro (écouteurs) ou à celui de la page : elle le redemande.
                DispatchQueue.main.async { self.lacherLaCopie() }
                let donnees = url.flatMap { try? Data(contentsOf: $0) }
                DispatchQueue.main.async {
                    guard let donnees = donnees, !donnees.isEmpty else {
                        self.repondre(id, ["erreur": "fichier introuvable"]); return
                    }
                    self.envoyerParMorceaux(id, donnees) {
                        self.repondre(id, ["ok": true, "octetsTotal": donnees.count])
                        // La page tient désormais le fichier (file d'attente) :
                        // l'exemplaire temporaire n'a plus de raison d'être.
                        if let url = url { try? FileManager.default.removeItem(at: url) }
                    }
                }
            }
        case "notifier":
            Notifications.partagees.poser(titre: params["titre"] as? String ?? "Rapporteur",
                                          texte: params["texte"] as? String ?? "")
            repondre(id, ["ok": true])
        case "ouvrirReunion":
            // Un lien https, rien d'autre : la réunion s'ouvre en version web,
            // dans le panneau du haut, sans aucun pont.
            let brut = (params["lien"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let lien = URL(string: brut), lien.scheme?.lowercased() == "https",
                  !(lien.host ?? "").isEmpty else {
                repondre(id, ["erreur": "lien invalide"]); return
            }
            surOuvrirReunion?(lien)
            repondre(id, ["ok": true])
        case "fermerReunion":
            surFermerReunion?()
            repondre(id, ["ok": true])
        case "sonReunion":
            // Règle 6 : l'interprète écoute la réunion du panneau à la source.
            surSonReunion?(params["capter"] as? Bool ?? false, (params["niveau"] as? NSNumber)?.doubleValue ?? 1)
            repondre(id, ["ok": true])
        case "paroleReunion":
            // Règle 7 : les correspondants entendent l'interprète, le client en fond.
            surParoleReunion?(params["parler"] as? Bool ?? false, (params["niveau"] as? NSNumber)?.doubleValue ?? 1)
            repondre(id, ["ok": true])
        case "voixReunion":
            // Un morceau de la voix de l'interprète, une dizaine par seconde : sans réponse.
            if let morceau = params["morceau"] as? String, let taux = (params["taux"] as? NSNumber)?.intValue {
                surVoixReunion?(morceau, taux)
            }
        case "microInterprete":
            // Écouteurs ou AirPods : l'application écoute par le micro de l'iPhone pour
            // l'interprète (la page n'ouvre aucun micro).
            guard params["capter"] as? Bool ?? false else {
                if microInterprete.parCopie { enregistreur.surCopie = nil }
                microInterprete.arreter()
                repondre(id, ["ok": true]); return
            }
            /* Pendant l'enregistrement — ou le temps qu'il démarre — (1.1.14) : la copie du micro
               du compte rendu, jamais un second micro. */
            if enregistreur.enCours || enregistrementEnDemarrage {
                brancherCopie()
                repondre(id, ["ok": true, "copie": true]); return
            }
            demanderMicro { [weak self] accorde in
                guard let self = self else { return }
                guard accorde else { self.repondre(id, ["erreur": "micro refusé"]); return }
                do {
                    try self.microInterprete.demarrer()
                    self.repondre(id, ["ok": true])
                } catch {
                    self.microInterprete.arreter()
                    self.repondre(id, ["erreur": self.decrire(error)])
                }
            }
        case "autresSons":
            // L'interprète vocal parle à l'oreille : les autres applications
            // (YouTube, Teams…) baissent leur son le temps qu'il parle.
            repondre(id, autresSons(baisser: params["baisser"] as? Bool ?? false))
        case "enregistrementDemarre", "enregistrementTermine":
            // Le pendant du service Android : ici, c'est la session audio
            // active qui tient l'application éveillée — rien à faire de plus.
            repondre(id, ["ok": true])
        default:
            repondre(id, ["erreur": "action inconnue"])
        }
    }

    // MARK: - Les autres sons pendant l'interprète vocal

    /// Demande de Felly (15/10/2026) : la voix de l'interprète devant celle
    /// d'origine. Une page ne peut pas toucher au son d'une autre application ;
    /// la session audio de l'application, si : `.duckOthers` fait baisser les
    /// autres applications par le système tant qu'elle est active, et
    /// `.defaultToSpeaker` envoie l'interprète au haut-parleur (pas à l'écouteur
    /// d'appel, où l'enverrait le micro ouvert). À l'arrêt, la session se retire
    /// en le disant aux autres (`.notifyOthersOnDeactivation`) : leur son revient.
    /// Pendant un enregistrement natif, rien : la séance garde ses réglages (l'interprète,
    /// 1.1.14, y écoute une copie de son micro et ne parle que dans des écouteurs).
    private func autresSons(baisser: Bool) -> [String: Any] {
        if enregistreur.enCours { return ["ok": false] }
        // Le micro de l'iPhone pris pour l'interprète (écouteurs) : sa session reste telle quelle.
        if microInterprete.enCours { return ["ok": true] }
        let session = AVAudioSession.sharedInstance()
        do {
            if baisser {
                try session.setCategory(.playAndRecord, mode: .default,
                                        options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
                try session.setActive(true)
            } else {
                do {
                    try session.setActive(false, options: .notifyOthersOnDeactivation)
                } catch {
                    // Session encore occupée (WebKit) : on retire au moins l'atténuation.
                    try session.setCategory(.playAndRecord, mode: .default,
                                            options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
                }
            }
            return ["ok": true]
        } catch {
            return ["erreur": error.localizedDescription]
        }
    }

    // MARK: - Réponses

    private var pageDeConfiance: Bool {
        guard let url = vue?.url, url.scheme == "https",
              url.port == nil || url.port == 443 else { return false }
        return ["lerapporteur.com", "www.lerapporteur.com"].contains(url.host?.lowercased() ?? "")
    }

    /// L'état de la réunion du panneau, poussé dans la page : elle le lit sans
    /// attendre (sonReunionPossible, paroleReunionPossible).
    func etatReunion(possible: Bool) {
        guard pageDeConfiance else { return }
        vue?.evaluateJavaScript("window.rapporteurIOS && window.rapporteurIOS._etatReunion({possible: \(possible)});")
    }

    /// Des écouteurs (filaires, USB, Bluetooth, AirPods) sur la sortie ? Poussé dans la page
    /// au chargement et à chaque changement : l'interprète s'y adapte sans s'arrêter.
    func pousserEcouteurs() {
        guard pageDeConfiance else { return }
        let types: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio]
        let branches = AVAudioSession.sharedInstance().currentRoute.outputs.contains { types.contains($0.portType) }
        vue?.evaluateJavaScript("window.rapporteurIOS && window.rapporteurIOS._ecouteurs && window.rapporteurIOS._ecouteurs({branches: \(branches)});")
    }

    /// L'interprète sur la copie du micro de l'enregistrement (1.1.14).
    private func brancherCopie() {
        microInterprete.passerEnCopie()
        enregistreur.surCopie = { [weak self] tampon in self?.microInterprete.recevoirCopie(tampon) }
    }

    /// La copie lâchée (fin ou échec de l'enregistrement) : la page redemande sa source.
    private func lacherLaCopie() {
        guard microInterprete.parCopie else { return }
        enregistreur.surCopie = nil
        microInterprete.arreter()
        direMicroInterprete("arrete")
    }

    /// Le micro de l'iPhone remis à l'interprète : `recevoir(morceau, taux)` ou `arrete()`.
    private func direMicroInterprete(_ fonction: String, _ argument: String = "") {
        guard pageDeConfiance, ["recevoir", "arrete"].contains(fonction) else { return }
        vue?.evaluateJavaScript("window.rapporteurMicroInterprete && window.rapporteurMicroInterprete.\(fonction)(\(argument));")
    }

    private func demanderMicro(_ suite: @escaping (Bool) -> Void) {
        let fin: (Bool) -> Void = { accorde in DispatchQueue.main.async { suite(accorde) } }
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: fin(true)
            case .denied: fin(false)
            default: AVAudioApplication.requestRecordPermission { fin($0) }
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: fin(true)
            case .denied: fin(false)
            default: AVAudioSession.sharedInstance().requestRecordPermission { fin($0) }
            }
        }
    }

    /// Le son des correspondants (rapporteurSonReunion) ou le micro du client
    /// (rapporteurMicroReunion), remis à la salle : `recevoir(morceau, taux)` ou `arrete()`.
    func direReunion(_ objet: String, _ fonction: String, _ argument: String = "") {
        guard pageDeConfiance, ["rapporteurSonReunion", "rapporteurMicroReunion"].contains(objet),
              ["recevoir", "arrete"].contains(fonction) else { return }
        vue?.evaluateJavaScript("window.\(objet) && window.\(objet).\(fonction)(\(argument));")
    }

    private func repondre(_ id: Int, _ reponse: [String: Any]) {
        guard pageDeConfiance else { return }
        guard let json = try? JSONSerialization.data(withJSONObject: reponse),
              let texte = String(data: json, encoding: .utf8) else { return }
        vue?.evaluateJavaScript("window.rapporteurIOS && window.rapporteurIOS._repondre(\(id), \(texte));")
    }

    /// Le binaire passe en base64, par tranches d'un mégaoctet, l'une après
    /// l'autre : une seule chaîne de 60 Mo étranglerait la vue web.
    private func envoyerParMorceaux(_ id: Int, _ donnees: Data, _ fini: @escaping () -> Void) {
        let pas = 1_048_576
        var debut = 0
        func suivant() {
            // La navigation peut avoir changé pendant le transfert asynchrone.
            // Ne jamais livrer l'audio à une nouvelle page non autorisée.
            guard self.pageDeConfiance else { return }
            guard debut < donnees.count else { fini(); return }
            let fin = min(debut + pas, donnees.count)
            let b64 = donnees.subdata(in: debut..<fin).base64EncodedString()
            debut = fin
            vue?.evaluateJavaScript("window.rapporteurIOS && window.rapporteurIOS._morceau(\(id), \"\(b64)\");") { _, _ in
                suivant()
            }
        }
        suivant()
    }

    /// Le vu-mètre : dix relevés par seconde, poussés dans la page — avec, à
    /// côté, depuis combien de secondes le système nous a retiré le micro
    /// (0 = la capture tourne). Toutes les deux secondes, le chien de garde de
    /// l'enregistreur vérifie que le moteur tourne encore et le relance sinon.
    private func lancerLeNiveau() {
        minuterieNiveau?.invalidate()
        var tics = 0
        minuterieNiveau = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.enregistreur.enCours else { return }
            tics += 1
            if tics % 20 == 0 { self.enregistreur.surveiller() }
            let n = self.enregistreur.niveau
            let i = self.enregistreur.interrompuSec
            self.vue?.evaluateJavaScript(
                "window.rapporteurIOS && (window.rapporteurIOS.capture.niveau = \(n), " +
                "window.rapporteurIOS.capture.interrompueSec = \(i));")
        }
    }

    private func decrire(_ erreur: Error) -> String {
        if let e = erreur as? Enregistreur.Erreur {
            switch e {
            case .microRefuse: return "micro refusé"
            case .dejaEnCours: return "déjà en cours"
            case .rienAEnregistrer: return "rien à enregistrer"
            case .moteur(let detail): return "moteur : \(detail)"
            }
        }
        return erreur.localizedDescription
    }
}

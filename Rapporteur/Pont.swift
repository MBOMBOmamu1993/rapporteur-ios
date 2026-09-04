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
    }

    func detacher() {
        vue?.configuration.userContentController.removeScriptMessageHandler(forName: Pont.nom)
        minuterieNiveau?.invalidate()
    }

    var captureEnCours: Bool { enregistreur.enCours }

    // MARK: - Réception

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        // Seule notre page parle au pont : une caisse de paiement embarquée
        // n'obtient rien.
        let hote = message.frameInfo.securityOrigin.host.lowercased()
        guard hote == "lerapporteur.com" || hote == "www.lerapporteur.com" else { return }
        guard let corps = message.body as? [String: Any],
              let id = corps["id"] as? Int,
              let action = corps["action"] as? String else { return }
        let params = corps["params"] as? [String: Any] ?? [:]

        switch action {
        case "demarrer":
            enregistreur.demarrer { resultat in
                DispatchQueue.main.async {
                    switch resultat {
                    case .success:
                        self.lancerLeNiveau()
                        self.repondre(id, ["ok": true])
                    case .failure(let erreur):
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
            fileEnvois.async {
                let url = self.enregistreur.arreter()
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
        case "enregistrementDemarre", "enregistrementTermine":
            // Le pendant du service Android : ici, c'est la session audio
            // active qui tient l'application éveillée — rien à faire de plus.
            repondre(id, ["ok": true])
        default:
            repondre(id, ["erreur": "action inconnue"])
        }
    }

    // MARK: - Réponses

    private func repondre(_ id: Int, _ reponse: [String: Any]) {
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

    /// Le vu-mètre : dix relevés par seconde, poussés dans la page.
    private func lancerLeNiveau() {
        minuterieNiveau?.invalidate()
        minuterieNiveau = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.enregistreur.enCours else { return }
            let n = self.enregistreur.niveau
            self.vue?.evaluateJavaScript("window.rapporteurIOS && (window.rapporteurIOS.capture.niveau = \(n));")
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

import Foundation

/// Les liens que le panneau de réunion ouvre — essai de Felly (20/10/2026) : « sur iPhone, le
/// lien Zoom ne s'ouvre pas, ça m'envoie sur l'App Store ». La page de lancement de Zoom
/// (« /j/<numéro> ») reconnaît un téléphone et pousse son application, puis l'App Store, qui
/// emporteraient la réunion hors de Rapporteur.
enum LiensReunion {

    /// Un lien Zoom « /j/<numéro> » devient celui de la réunion dans le navigateur,
    /// « /wc/join/<numéro> » — l'adresse même du bouton « Participer depuis le navigateur » de
    /// Zoom —, mot de passe et autres paramètres gardés. Tout autre lien reste tel quel.
    static func pourLeNavigateur(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "https", let hote = url.host?.lowercased(),
              hote == "zoom.us" || hote.hasSuffix(".zoom.us") else { return url }
        let morceaux = url.path.split(separator: "/")
        guard morceaux.count == 2, morceaux[0] == "j", !morceaux[1].isEmpty,
              morceaux[1].allSatisfy({ $0.isASCII && $0.isNumber }),
              var composants = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        composants.path = "/wc/join/\(morceaux[1])"
        return composants.url ?? url
    }

    /// Une boutique d'applications : jamais dans le panneau.
    static func versUneBoutique(_ url: URL) -> Bool {
        let schema = url.scheme?.lowercased() ?? ""
        if ["itms-apps", "itms-appss", "itms", "itmss", "market"].contains(schema) { return true }
        let hote = url.host?.lowercased() ?? ""
        return ["apps.apple.com", "itunes.apple.com", "appsto.re", "play.google.com"].contains(hote)
    }
}

import Foundation

/// Les cadres techniques ne doivent jamais déclencher une application externe.
enum PolitiqueNavigation {
    enum Destination: Equatable {
        case permettre, refuser, externe, charger, accueil(Bool), connexion(Bool), retourConnexion
    }

    static let hotes: Set<String> = ["lerapporteur.com", "www.lerapporteur.com"]

    static func destination(_ url: URL, cadrePrincipal: Bool?, sourcePrincipale: Bool,
                            clic: Bool) -> Destination {
        let schema = url.scheme?.lowercased() ?? ""
        let hote = url.host?.lowercased() ?? ""
        let https = schema == "https" && (url.port == nil || url.port == 443)
        let interne = https && hotes.contains(hote)

        if cadrePrincipal == false {
            if schema == "about" && ["blank", "srcdoc"].contains(url.path) { return .permettre }
            return interne || (https && hote == "challenges.cloudflare.com") ? .permettre : .refuser
        }
        // Un sous-cadre ne peut ouvrir ni une fenêtre ni une application.
        guard sourcePrincipale else { return .refuser }
        if schema == "rapporteur" { return .retourConnexion }
        if interne {
            let chemin = url.path
            let anglais = chemin.hasPrefix("/en/") || chemin == "/en"
            if chemin.isEmpty || ["/", "/en", "/en/"].contains(chemin) { return .accueil(anglais) }
            // L'app utilise exclusivement la connexion courriel de Rapporteur (4.8).
            if chemin == "/api/connexion" || chemin == "/api/connexion/" {
                let retour = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "retour" })?.value ?? ""
                return .connexion(retour.hasPrefix("/en/"))
            }
            if ["/tarifs", "/paiement", "/en/tarifs", "/en/paiement"].contains(where: chemin.hasPrefix) {
                return .accueil(anglais)
            }
            return cadrePrincipal == nil ? .charger : .permettre
        }
        if schema == "about" || schema == "file" { return .permettre }
        if hote == "challenges.cloudflare.com" || hote == "accounts.google.com"
            || hote == "stripe.com" || hote.hasSuffix(".stripe.com")
            || hote == "cinetpay.com" || hote.hasSuffix(".cinetpay.com") { return .refuser }
        return clic && ["https", "mailto", "tel"].contains(schema) ? .externe : .refuser
    }
}

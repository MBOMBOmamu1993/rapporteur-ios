import Foundation

typealias D = PolitiqueNavigation.Destination
var nombre = 0
func verifier(_ adresse: String, cadre: Bool? = true, source: Bool = true,
              clic: Bool = false, attendu: D) {
    let obtenu = PolitiqueNavigation.destination(URL(string: adresse)!,
        cadrePrincipal: cadre, sourcePrincipale: source, clic: clic)
    precondition(obtenu == attendu, "Navigation inattendue : \(adresse), \(obtenu), attendu \(attendu)")
    nombre += 1
}
verifier("https://challenges.cloudflare.com/cdn-cgi/challenge-platform/widget", cadre: false, attendu: .permettre)
verifier("https://challenges.cloudflare.com/cdn-cgi/challenge-platform/widget", cadre: false, source: false, attendu: .permettre)
verifier("about:blank", cadre: false, source: false, attendu: .permettre)
verifier("about:srcdoc", cadre: false, source: false, attendu: .permettre)
verifier("https://challenges.cloudflare.com/", clic: true, attendu: .refuser)
verifier("https://challenges.cloudflare.com/", cadre: nil, source: false, attendu: .refuser)
verifier("https://challenges.cloudflare.com.evil.example/", cadre: false, attendu: .refuser)
verifier("http://challenges.cloudflare.com/", cadre: false, attendu: .refuser)
verifier("https://challenges.cloudflare.com:8443/", cadre: false, attendu: .refuser)
verifier("https://example.com/", cadre: false, clic: true, attendu: .refuser)
verifier("mailto:info@lerapporteur.com", cadre: false, clic: true, attendu: .refuser)
verifier("https://example.com/", cadre: nil, source: false, clic: true, attendu: .refuser)
verifier("https://example.com/", attendu: .refuser)
verifier("https://example.com/", clic: true, attendu: .externe)
verifier("mailto:info@lerapporteur.com", clic: true, attendu: .externe)
verifier("https://lerapporteur.com/en/connexion", attendu: .permettre)
verifier("https://lerapporteur.com/api/connexion", clic: true, attendu: .connexion(false))
verifier("https://lerapporteur.com/api/connexion?retour=%2Fen%2Fenregistrer", attendu: .connexion(true))
verifier("https://accounts.google.com/o/oauth2/v2/auth", clic: true, attendu: .refuser)
verifier("https://lerapporteur.com/en/paiement", attendu: .accueil(true))
verifier("https://checkout.stripe.com/pay/test", clic: true, attendu: .refuser)
verifier("https://lerapporteur.com/", attendu: .accueil(false))
verifier("https://lerapporteur.com/en", attendu: .accueil(true))
verifier("https://lerapporteur.com/compte", cadre: nil, clic: true, attendu: .charger)
verifier("rapporteur://connexion?billet=obsolete", attendu: .retourConnexion)
verifier("rapporteur://connexion?billet=obsolete", cadre: false, attendu: .refuser)
print("\(nombre) scénarios de navigation validés")

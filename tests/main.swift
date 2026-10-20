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
// Le panneau de réunion : Zoom dans le navigateur, jamais de boutique d'applications (20/10/2026).
func lien(_ avant: String, _ attendu: String) {
    let obtenu = LiensReunion.pourLeNavigateur(URL(string: avant)!).absoluteString
    precondition(obtenu == attendu, "Lien de réunion inattendu : \(avant) → \(obtenu), attendu \(attendu)")
    nombre += 1
}
lien("https://us05web.zoom.us/j/81234567890?pwd=AbC123.1", "https://us05web.zoom.us/wc/join/81234567890?pwd=AbC123.1")
lien("https://zoom.us/j/81234567890", "https://zoom.us/wc/join/81234567890")
lien("https://zoom.us/j/81234567890/", "https://zoom.us/wc/join/81234567890")
lien("https://zoom.us/wc/join/81234567890?pwd=x", "https://zoom.us/wc/join/81234567890?pwd=x")
lien("https://zoom.us/my/salle", "https://zoom.us/my/salle")
lien("https://zoom.us/j/abc", "https://zoom.us/j/abc")
lien("https://evilzoom.us/j/81234567890", "https://evilzoom.us/j/81234567890")
lien("http://zoom.us/j/81234567890", "http://zoom.us/j/81234567890")
lien("https://teams.microsoft.com/l/meetup-join/19", "https://teams.microsoft.com/l/meetup-join/19")
for boutique in ["https://apps.apple.com/us/app/id546505307", "itms-apps://itunes.apple.com/us/app/id546505307",
                 "https://play.google.com/store/apps/details?id=us.zoom.videomeetings", "market://details?id=x"] {
    precondition(LiensReunion.versUneBoutique(URL(string: boutique)!), "Boutique non reconnue : \(boutique)")
    nombre += 1
}
for page in ["https://app.zoom.us/wc/81234567890/join", "https://teams.live.com/meet/1", "https://meet.google.com/abc-defg-hij"] {
    precondition(!LiensReunion.versUneBoutique(URL(string: page)!), "Page de réunion prise pour une boutique : \(page)")
    nombre += 1
}
print("\(nombre) scénarios de navigation validés")

// Les réunions gardées (1.1.16) : rangées, notées, listées, redonnées, oubliées, ménage.
var gardeesValides = 0
func exiger(_ condition: Bool, _ message: String) {
    precondition(condition, "Réunions gardées : \(message)")
    gardeesValides += 1
}
let bancGardees = FileManager.default.temporaryDirectory.appendingPathComponent("gardees-\(UUID().uuidString)")
func fichierDeSeance(_ octets: Int) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("reunion-\(UUID().uuidString).m4a")
    FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 7, count: octets))
    return url
}
let maintenant = Date()
let gardees = ReunionsGardees(dossier: bancGardees, plafond: 25)
let source = fichierDeSeance(12)
let premiere = try! gardees.garder(fichier: source, debut: maintenant.addingTimeInterval(-3600), dureeSec: 3600,
                                  proprietaire: "4a1a51e612220936a948c330")
exiger(!FileManager.default.fileExists(atPath: source.path), "le fichier temporaire doit être déplacé")
exiger(ReunionsGardees.valide(premiere), "identifiant invalide : \(premiere)")
exiger(gardees.donnees(id: premiere)?.count == 12, "le fichier gardé doit se relire entier")
try! gardees.noter(id: premiere, page: ["debut": "2026-10-20T13:33:52+01:00", "courriel": "a@exemple.cd", "langues_compte_rendu": ["fr"]])
var liste = gardees.liste()
exiger(liste.count == 1 && liste[0]["id"] as? String == premiere && (liste[0]["octets"] as? Int64) == 12, "liste : \(liste)")
let infos = liste[0]["infos"] as? [String: Any]
exiger((infos?["page"] as? [String: Any])?["courriel"] as? String == "a@exemple.cd", "ce que la page a noté doit revenir")
exiger((infos?["natif"] as? [String: Any])?["proprietaire"] as? String == "4a1a51e612220936a948c330", "le compte doit être noté")
exiger(((infos?["natif"] as? [String: Any])?["duree_sec"] as? Int) == 3600, "la durée doit être notée")
exiger(((infos?["natif"] as? [String: Any])?["garde_ms"] as? NSNumber).map { abs($0.doubleValue / 1000 - Date().timeIntervalSince1970) < 60 } == true,
       "l'heure du rangement doit être notée")
for hostile in ["../secret", "a/b", "", String(repeating: "a", count: 65), "r 1", "é"] {
    exiger(!ReunionsGardees.valide(hostile) && gardees.donnees(id: hostile) == nil, "identifiant accepté : \(hostile)")
}
exiger((try? gardees.noter(id: "r-inconnue", page: [:])) == nil, "noter une réunion absente doit échouer")
exiger((try? gardees.noter(id: premiere, page: ["gros": String(repeating: "x", count: 70_000)])) == nil, "une note démesurée doit être refusée")
// Plus de dix jours : partie ; la récente reste.
_ = try! gardees.garder(fichier: fichierDeSeance(3), debut: maintenant.addingTimeInterval(-11 * 86_400), dureeSec: 3, proprietaire: nil)
gardees.menage(maintenant: maintenant)
liste = gardees.liste()
exiger(liste.count == 1 && liste[0]["id"] as? String == premiere, "ménage des dix jours : \(liste)")
// Au-delà du plafond (25 octets ici) : les plus anciennes partent, jamais la dernière.
let deuxieme = try! gardees.garder(fichier: fichierDeSeance(10), debut: maintenant.addingTimeInterval(-1800), dureeSec: 10, proprietaire: nil)
let troisieme = try! gardees.garder(fichier: fichierDeSeance(10), debut: maintenant.addingTimeInterval(-60), dureeSec: 10, proprietaire: nil)
gardees.menage(maintenant: maintenant)
exiger(gardees.liste().compactMap { $0["id"] as? String } == [deuxieme, troisieme], "ménage du plafond : \(gardees.liste())")
let seule = ReunionsGardees(dossier: bancGardees.appendingPathComponent("seule"), plafond: 1)
let derniere = try! seule.garder(fichier: fichierDeSeance(50), debut: maintenant, dureeSec: 50, proprietaire: nil)
seule.menage(maintenant: maintenant)
exiger(seule.liste().compactMap { $0["id"] as? String } == [derniere], "la dernière réunion ne part jamais au ménage")
// Reçue par le serveur : oubliée, fichier et fiche.
gardees.oublier(id: deuxieme)
gardees.oublier(id: troisieme)
exiger(gardees.liste().isEmpty, "oublier doit tout retirer")
let restes = (try? FileManager.default.contentsOfDirectory(atPath: bancGardees.path)) ?? []
exiger(!restes.contains { $0.hasSuffix(".json") || $0.hasSuffix(".m4a") }, "des fichiers restent : \(restes)")
try? FileManager.default.removeItem(at: bancGardees)
print("\(gardeesValides) contrôles des réunions gardées validés")

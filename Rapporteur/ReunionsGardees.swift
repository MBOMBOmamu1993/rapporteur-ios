import Foundation

/// Les réunions gardées par l'application tant que le serveur ne les a pas reçues (1.1.16).
///
/// Jusqu'à la 1.1.15, le fichier de la séance était effacé dès que la page l'avait reçu : la copie
/// de la page (sa base IndexedDB) était la seule. Le 20/10/2026, la réunion d'une cliente est restée
/// illisible pour la page (défaut de WebKit, corrigé côté site) ; une autre panne du stockage de la
/// page — téléphone plein, données du site vidées — l'aurait perdue pour de bon. Ici, le fichier est
/// rangé à l'abri (Application Support, hors des sauvegardes iCloud) jusqu'à ce que la page dise que
/// le serveur l'a reçu, ou que le client la supprime ; il peut lui être redonné à tout moment.
///
/// Le ménage retire ce qui a plus de dix jours, puis l'excédent au-delà de 2 Go, du plus ancien au
/// plus récent — jamais la dernière réunion. Rien ici ne dépend de WebKit ni d'AVFoundation : le
/// banc `tests/main.swift` l'essaie tel quel.
final class ReunionsGardees {

    static let joursMax: Double = 10
    static let octetsMax: Int64 = 2 * 1024 * 1024 * 1024
    /// Ce que la page peut noter à côté d'une réunion : de quoi la renvoyer, pas un document.
    static let infosMax = 64 * 1024

    let dossier: URL
    /// Le plafond du ménage (2 Go ; réglable pour le banc).
    let plafond: Int64
    private let fm = FileManager.default
    private let verrou = NSLock()

    init(dossier: URL? = nil, plafond: Int64 = ReunionsGardees.octetsMax) {
        self.plafond = plafond
        if let dossier = dossier {
            self.dossier = dossier
        } else {
            let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            self.dossier = support.appendingPathComponent("ReunionsGardees", isDirectory: true)
        }
    }

    /// Un identifiant venu de la page : lettres, chiffres et tirets — jamais un chemin.
    static func valide(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90) ||
            ($0.value >= 97 && $0.value <= 122) || $0 == "-"
        }
    }

    static func nouvelIdentifiant(_ debut: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyyMMdd-HHmmss"
        let alea = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        return "r\(format.string(from: debut))-\(alea)"
    }

    private func audio(_ id: String) -> URL { dossier.appendingPathComponent("\(id).m4a") }
    private func fiche(_ id: String) -> URL { dossier.appendingPathComponent("\(id).json") }

    private func preparer() throws {
        guard !fm.fileExists(atPath: dossier.path) else { return }
        try fm.createDirectory(at: dossier, withIntermediateDirectories: true)
        // Des réunions confidentielles, gardées quelques jours : rien dans les sauvegardes iCloud.
        var url = dossier
        var valeurs = URLResourceValues()
        valeurs.isExcludedFromBackup = true
        try? url.setResourceValues(valeurs)
    }

    private func lireFiche(_ id: String) -> [String: Any] {
        guard let donnees = try? Data(contentsOf: fiche(id)),
              let objet = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any] else { return [:] }
        return objet
    }

    private func ecrireFiche(_ id: String, _ contenu: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(contenu) else { throw CocoaError(.coderInvalidValue) }
        let donnees = try JSONSerialization.data(withJSONObject: contenu)
        try donnees.write(to: fiche(id), options: .atomic)
    }

    /// Range le fichier de la séance — déplacé, pas copié : même volume, aucune attente — avec ce
    /// que l'application en sait (début, durée, compte). Rend son identifiant.
    @discardableResult
    func garder(fichier: URL, debut: Date, dureeSec: Int, proprietaire: String?) throws -> String {
        verrou.lock(); defer { verrou.unlock() }
        try preparer()
        let id = ReunionsGardees.nouvelIdentifiant(debut)
        try fm.moveItem(at: fichier, to: audio(id))
        // garde_ms : l'heure du rangement — la page ne reprend un original qu'au-delà de dix
        // minutes, jamais une séance que la salle est en train de déposer.
        var natif: [String: Any] = ["debut_ms": Int64(debut.timeIntervalSince1970 * 1000), "duree_sec": max(0, dureeSec),
                                    "garde_ms": Int64(Date().timeIntervalSince1970 * 1000)]
        if let proprietaire = proprietaire, ReunionsGardees.valide(proprietaire) { natif["proprietaire"] = proprietaire }
        try? ecrireFiche(id, ["natif": natif])
        return id
    }

    /// Ce que la page sait de la réunion (début, langues, adresse du compte rendu…), posé à côté :
    /// si sa propre copie disparaissait, elle pourrait la renvoyer telle qu'elle était.
    func noter(id: String, page: [String: Any]) throws {
        verrou.lock(); defer { verrou.unlock() }
        guard ReunionsGardees.valide(id), fm.fileExists(atPath: audio(id).path) else { throw CocoaError(.fileNoSuchFile) }
        guard JSONSerialization.isValidJSONObject(page),
              let brut = try? JSONSerialization.data(withJSONObject: page), brut.count <= ReunionsGardees.infosMax else {
            throw CocoaError(.coderInvalidValue)
        }
        var contenu = lireFiche(id)
        contenu["page"] = page
        try ecrireFiche(id, contenu)
    }

    /// Les réunions gardées, de la plus ancienne à la plus récente : identifiant, poids, date
    /// (millisecondes) et ce qui a été noté.
    func liste() -> [[String: Any]] {
        verrou.lock(); defer { verrou.unlock() }
        return reunions().map { r in
            ["id": r.id, "octets": r.octets, "cree": Int64(r.date.timeIntervalSince1970 * 1000), "infos": lireFiche(r.id)]
        }
    }

    /// Le fichier d'une réunion gardée, pour la page.
    func donnees(id: String) -> Data? {
        verrou.lock(); defer { verrou.unlock() }
        guard ReunionsGardees.valide(id) else { return nil }
        return try? Data(contentsOf: audio(id), options: .mappedIfSafe)
    }

    /// Le serveur l'a reçue, ou le client l'a supprimée : elle n'a plus rien à faire ici.
    func oublier(id: String) {
        verrou.lock(); defer { verrou.unlock() }
        guard ReunionsGardees.valide(id) else { return }
        try? fm.removeItem(at: audio(id))
        try? fm.removeItem(at: fiche(id))
    }

    /// Plus de dix jours : retirée. Au-delà de 2 Go : les plus anciennes d'abord, jamais la dernière.
    /// Une fiche sans son fichier part aussi.
    func menage(maintenant: Date = Date()) {
        verrou.lock(); defer { verrou.unlock() }
        let limite = maintenant.addingTimeInterval(-ReunionsGardees.joursMax * 86_400)
        var restantes = reunions()
        for r in restantes where r.date < limite {
            try? fm.removeItem(at: audio(r.id))
            try? fm.removeItem(at: fiche(r.id))
        }
        restantes.removeAll { $0.date < limite }
        var total = restantes.reduce(Int64(0)) { $0 + $1.octets }
        while total > plafond, restantes.count > 1 {
            let plusAncienne = restantes.removeFirst()
            try? fm.removeItem(at: audio(plusAncienne.id))
            try? fm.removeItem(at: fiche(plusAncienne.id))
            total -= plusAncienne.octets
        }
        let fichiers = (try? fm.contentsOfDirectory(at: dossier, includingPropertiesForKeys: nil)) ?? []
        for url in fichiers where url.pathExtension == "json" {
            let id = url.deletingPathExtension().lastPathComponent
            if !fm.fileExists(atPath: audio(id).path) { try? fm.removeItem(at: url) }
        }
    }

    private struct Reunion { let id: String; let octets: Int64; let date: Date }

    /// Date d'une réunion : son début noté par l'application, sinon la date du fichier.
    private func reunions() -> [Reunion] {
        let cles: [URLResourceKey] = [.fileSizeKey, .creationDateKey, .contentModificationDateKey]
        let fichiers = (try? fm.contentsOfDirectory(at: dossier, includingPropertiesForKeys: cles)) ?? []
        return fichiers.compactMap { url -> Reunion? in
            guard url.pathExtension == "m4a" else { return nil }
            let id = url.deletingPathExtension().lastPathComponent
            guard ReunionsGardees.valide(id) else { return nil }
            let valeurs = try? url.resourceValues(forKeys: Set(cles))
            var date = valeurs?.creationDate ?? valeurs?.contentModificationDate ?? Date.distantPast
            if let natif = lireFiche(id)["natif"] as? [String: Any], let ms = (natif["debut_ms"] as? NSNumber)?.doubleValue {
                date = Date(timeIntervalSince1970: ms / 1000)
            }
            return Reunion(id: id, octets: Int64(valeurs?.fileSize ?? 0), date: date)
        }.sorted { $0.date < $1.date }
    }
}

import UIKit
import WebKit

/// La réunion en ligne tenue sur CE téléphone, ouverte DANS l'application —
/// le pendant du panneau « reunion » d'Android.
///
/// Tenue dans l'application Teams, Zoom ou WhatsApp, une réunion prend le
/// micro pour elle (iOS le donne à l'appel) et Rapporteur n'entend plus rien.
/// Ouverte ici, en version web, elle reste dans NOTRE application : la
/// réunion capte le client pour ses correspondants, et l'enregistreur natif
/// capte le client ET le haut-parleur.
///
/// La page de réunion n'a qu'un pont, `rapporteurReunion` (1.1.13), par lequel la
/// prise (`prise-reunion.js`) DONNE le son des correspondants, ou le micro du client
/// pendant que l'interprète parle dans la réunion — seulement quand la salle l'a
/// demandé, et vérifié ici. Elle n'obtient que micro et caméra, et seulement
/// auprès des services de réunion connus.
final class PanneauReunion: UIView, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

    /// Les services de réunion auxquels le panneau accorde micro et caméra —
    /// la liste d'Android. Tout autre site s'affiche mais n'obtient rien.
    static func hoteDeReunion(_ hote: String) -> Bool {
        let h = hote.lowercased()
        func domaine(_ d: String) -> Bool { h == d || h.hasSuffix("." + d) }
        return h == "meet.google.com"
            || domaine("teams.microsoft.com") || domaine("teams.live.com")
            || domaine("zoom.us") || h.hasSuffix(".webex.com")
            || h == "meet.jit.si" || domaine("whereby.com")
    }

    /// Signature d'ORDINATEUR (Safari sur Mac), comme « Site pour ordinateur »
    /// dans Safari : à un téléphone, Teams et Zoom ne servent que
    /// « Télécharger l'application », dont les boutons sortiraient la réunion
    /// de Rapporteur ; à un ordinateur, ils proposent « Continuer sur ce
    /// navigateur », et la réunion se tient ici.
    static var agentOrdinateur: String {
        let v = UIDevice.current.systemVersion.split(separator: ".").map(String.init)
        let version = (v.first ?? "17") + "." + (v.count > 1 ? v[1] : "0")
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/\(version) Safari/605.1.15"
    }

    /// « Fermer » : le contrôleur replie le panneau.
    var surFermer: (() -> Void)?

    private let barre = UIView()
    private let titre = UILabel()
    private let fermer = UIButton(type: .system)
    private let reunion: WKWebView

    override init(frame: CGRect) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()          // les connexions Google/Microsoft restent
        configuration.allowsInlineMediaPlayback = true        // la vidéo reste dans le panneau
        configuration.mediaTypesRequiringUserActionForPlayback = [] // les voix des correspondants sans clic
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        reunion = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frame)

        backgroundColor = UIColor(red: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255, alpha: 1)
        titre.textColor = UIColor(red: 0xF0 / 255, green: 0xEE / 255, blue: 0xE6 / 255, alpha: 1)
        titre.font = .systemFont(ofSize: 15, weight: .medium)
        titre.adjustsFontSizeToFitWidth = true
        titre.minimumScaleFactor = 0.75
        fermer.setTitleColor(UIColor(red: 0xE0 / 255, green: 0x8D / 255, blue: 0x6D / 255, alpha: 1), for: .normal)
        fermer.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        fermer.setContentHuggingPriority(.required, for: .horizontal)
        fermer.setContentCompressionResistancePriority(.required, for: .horizontal)
        fermer.addTarget(self, action: #selector(toucherFermer), for: .touchUpInside)

        reunion.navigationDelegate = self
        reunion.uiDelegate = self
        reunion.customUserAgent = Self.agentOrdinateur
        reunion.allowsBackForwardNavigationGestures = true

        for vue in [barre, titre, fermer, reunion] as [UIView] {
            vue.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(barre)
        barre.addSubview(titre)
        barre.addSubview(fermer)
        addSubview(reunion)
        NSLayoutConstraint.activate([
            barre.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            barre.leadingAnchor.constraint(equalTo: leadingAnchor),
            barre.trailingAnchor.constraint(equalTo: trailingAnchor),
            barre.heightAnchor.constraint(equalToConstant: 42),
            titre.leadingAnchor.constraint(equalTo: barre.leadingAnchor, constant: 16),
            titre.centerYAnchor.constraint(equalTo: barre.centerYAnchor),
            fermer.leadingAnchor.constraint(greaterThanOrEqualTo: titre.trailingAnchor, constant: 12),
            fermer.trailingAnchor.constraint(equalTo: barre.trailingAnchor, constant: -16),
            fermer.centerYAnchor.constraint(equalTo: barre.centerYAnchor),
            reunion.topAnchor.constraint(equalTo: barre.bottomAnchor),
            reunion.leadingAnchor.constraint(equalTo: leadingAnchor),
            reunion.trailingAnchor.constraint(equalTo: trailingAnchor),
            reunion.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // La prise, posée au tout début de chaque page de réunion (avant ses scripts),
        // et son pont vers l'application — par un relais faible : WebKit retient ses
        // récepteurs, le panneau ne doit pas se retenir lui-même.
        let controleur = reunion.configuration.userContentController
        controleur.add(RelaisFaible(self), name: Self.pontPrise)
        // D'abord « ordinateur.js » : sans lui, Teams voit un iPhone (plateforme et
        // écran tactile) et ne sert que l'App Store ; puis la prise du son.
        for nom in ["ordinateur", "prise-reunion"] {
            if let chemin = Bundle.main.url(forResource: nom, withExtension: "js"),
               let source = try? String(contentsOf: chemin, encoding: .utf8) {
                controleur.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

    /// Ouvre la réunion ; la barre parle la langue de la salle (fr, en, pt, es).
    func ouvrir(_ lien: URL, langue: String) {
        let mots: [String: (String, String)] = [
            "fr": ("Réunion — dans Rapporteur", "✕ Fermer"),
            "en": ("Meeting — inside Rapporteur", "✕ Close"),
            "pt": ("Reunião — no Rapporteur", "✕ Fechar"),
            "es": ("Reunión — en Rapporteur", "✕ Cerrar"),
        ]
        let (texte, bouton) = mots[langue] ?? mots["fr"]!
        titre.text = texte
        fermer.setTitle(bouton, for: .normal)
        reunion.load(URLRequest(url: lien))
    }

    /// Fermer, c'est quitter la réunion : la page vide coupe micro et caméra.
    func vider() {
        priseReunion = false
        paroleReunion = false
        reunion.stopLoading()
        reunion.load(URLRequest(url: URL(string: "about:blank")!))
    }

    // MARK: - Le son de la réunion, pour l'interprète (iPhone 1.1.13)

    /*
     * Demandes de Felly (16-17/10/2026), comme sur Android 1.1.11 et 1.1.12 :
     * l'interprète écoute la réunion ouverte ici à la source — le son des
     * correspondants, jamais le micro (règle 6) — et, dans l'autre sens, les
     * correspondants l'entendent parler à la place du client, sa voix devant
     * (règle 7). La salle demande ; la prise exécute ; ce qu'elle envoie est
     * vérifié avant d'entrer dans la salle : du base 64, de taille bornée, d'un
     * service de réunion connu, en HTTPS, et seulement quand la salle l'a demandé.
     */
    static let pontPrise = "rapporteurReunion"
    private static let base64 = try! NSRegularExpression(pattern: "^[A-Za-z0-9+/]+={0,2}$")

    /// Un morceau du son des correspondants (règle 6), pour la salle.
    var surSon: ((String, Int) -> Void)?
    /// Un morceau du micro du client tel que la réunion le prend (règle 7), pour la salle.
    var surMicro: ((String, Int) -> Void)?
    /// La page du panneau a changé : le contrôleur redit à la salle si l'interprète peut s'y brancher.
    var surEtat: (() -> Void)?

    private(set) var priseReunion = false
    private(set) var paroleReunion = false
    private var niveauReunion = 1.0
    private var niveauClient = 0.15

    /// Une page de réunion à qui l'on prend le son : un service connu, en HTTPS.
    var possible: Bool {
        guard let url = reunion.url, url.scheme?.lowercased() == "https",
              url.port == nil || url.port == 443, let hote = url.host else { return false }
        return Self.hoteDeReunion(hote)
    }

    /// La salle demande (ou lâche) le son des correspondants ; niveau = celui de la
    /// réunion dans le panneau pendant ce temps (1 à l'arrêt).
    func capter(_ oui: Bool, niveau: Double) {
        priseReunion = oui && possible
        niveauReunion = max(0, min(1, niveau))
        commander()
    }

    /// La salle fait parler l'interprète dans la réunion (ou l'arrête) ; niveau = la
    /// voix du client derrière lui, pour les correspondants.
    func parler(_ oui: Bool, niveau: Double) {
        paroleReunion = oui && possible
        niveauClient = max(0, min(1, niveau))
        commander()
    }

    /// Un morceau de la voix de l'interprète, de la salle vers la réunion.
    func voix(_ morceau: String, taux: Int) {
        guard paroleReunion, possible, Self.morceauValide(morceau, taux) else { return }
        reunion.evaluateJavaScript("window.__rapporteurPrise && window.__rapporteurPrise.voix('\(morceau)', \(taux));")
    }

    private func commander() {
        reunion.evaluateJavaScript("window.__rapporteurPrise && (window.__rapporteurPrise.capter(\(priseReunion), "
            + "\(priseReunion ? niveauReunion : 1)), window.__rapporteurPrise.parler(\(paroleReunion), \(niveauClient)));")
    }

    private static func morceauValide(_ morceau: String, _ taux: Int) -> Bool {
        let longueur = morceau.utf8.count
        guard longueur > 0, longueur <= 65_536, (8_000...96_000).contains(taux) else { return false }
        return base64.firstMatch(in: morceau, range: NSRange(location: 0, length: (morceau as NSString).length)) != nil
    }

    /// Le seul pont de la page de réunion : elle ne peut que DONNER le son de ses
    /// correspondants, ou le micro du client pendant que l'interprète y parle.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let origine = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, origine.protocol == "https", [0, 443].contains(origine.port),
              Self.hoteDeReunion(origine.host), possible,
              let corps = message.body as? [String: Any],
              let type = corps["type"] as? String,
              let morceau = corps["b64"] as? String,
              let taux = (corps["taux"] as? NSNumber)?.intValue,
              Self.morceauValide(morceau, taux) else { return }
        switch type {
        case "son" where priseReunion: surSon?(morceau, taux)
        case "micro" where paroleReunion: surMicro?(morceau, taux)
        default: break
        }
    }

    @objc private func toucherFermer() { surFermer?() }

    // MARK: - La réunion reste en version web, dans le panneau

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.preferredContentMode = .desktop
        // Les liens « ouvrez l'application » (msteams:, zoomus:, itms-apps:…)
        // emporteraient la réunion HORS de Rapporteur — donc hors du micro
        // partagé. On reste sur la version web, comme sur Android.
        let schema = action.request.url?.scheme?.lowercased() ?? ""
        let web = ["https", "http", "about", "blob", "data"].contains(schema)
        decisionHandler(web ? .allow : .cancel, preferences)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Une seule fenêtre, comme le WebView Android : ce que la réunion
        // ouvrirait à côté s'ouvre ici.
        if let url = action.request.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            webView.load(action.request)
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Le moteur de la réunion est mort (mémoire) : on la recharge.
        webView.reload()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        surEtat?()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Chaque page reçoit une prise neuve (script du début du document) : on lui
        // redit ce que la salle a demandé.
        if priseReunion || paroleReunion { commander() }
        surEtat?()
    }

    // MARK: - Micro et caméra : aux services de réunion seulement

    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let confiance = origin.protocol == "https" && [0, 443].contains(origin.port)
            && Self.hoteDeReunion(origin.host)
        decisionHandler(confiance ? .grant : .deny)
    }

    // MARK: - Les boîtes de dialogue de la réunion

    /// Le contrôleur le plus haut : une alerte présentée ailleurs ne
    /// s'afficherait pas, et WebKit attendrait sa réponse pour toujours.
    private var presentateur: UIViewController? {
        var haut = window?.rootViewController
        while let suivant = haut?.presentedViewController { haut = suivant }
        return haut
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let hote = presentateur else { completionHandler(); return }
        let alerte = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alerte.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        hote.present(alerte, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let hote = presentateur else { completionHandler(false); return }
        let alerte = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alerte.addAction(UIAlertAction(title: NSLocalizedString("Annuler", comment: ""), style: .cancel) { _ in completionHandler(false) })
        alerte.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        hote.present(alerte, animated: true)
    }
}

/// WebKit retient ses récepteurs de messages : un relais faible évite que le
/// panneau se retienne lui-même (et ne soit jamais libéré).
private final class RelaisFaible: NSObject, WKScriptMessageHandler {
    weak var cible: WKScriptMessageHandler?
    init(_ cible: WKScriptMessageHandler) { self.cible = cible }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        cible?.userContentController(controller, didReceive: message)
    }
}

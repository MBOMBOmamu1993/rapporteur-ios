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
/// La page de réunion n'a aucun pont : elle n'obtient que micro et caméra,
/// et seulement auprès des services de réunion connus.
final class PanneauReunion: UIView, WKNavigationDelegate, WKUIDelegate {

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
        reunion.stopLoading()
        reunion.load(URLRequest(url: URL(string: "about:blank")!))
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

import AuthenticationServices
import UIKit
import WebKit

/// Un WKWebView plein écran qui charge lerapporteur.com/mobile — l'accueil de
/// l'application, le même que sur Android : un bouton micro au centre.
///
/// Ce que la vue web ne fait PAS elle-même, et que ce contrôleur décide :
///  - la connexion Google se joue hors de la vue web (ASWebAuthenticationSession,
///    qui partage la session Safari du téléphone : Google y est déjà connecté) et
///    revient par rapporteur://connexion?billet=…, échangé contre la session
///    DANS la vue web, avec le défi que seule l'application connaît ;
///  - version App Store : tarifs et caisses ne se chargent jamais (règle 3.1.1),
///    le site les masque déjà — ceci est la ceinture et les bretelles ;
///  - les autres sites s'ouvrent dans Safari ; hors connexion, un écran local.
final class ControleurPrincipal: UIViewController, WKNavigationDelegate, WKUIDelegate,
                                 ASWebAuthenticationPresentationContextProviding {

    static let site = URL(string: "https://lerapporteur.com")!
    private static let hotes: Set<String> = ["lerapporteur.com", "www.lerapporteur.com"]

    private var toile: WKWebView!
    private let pont = Pont()
    /// Le défi de la connexion en cours, exigé par le serveur à l'échange du
    /// billet : une application tierce qui écouterait rapporteur:// aurait le
    /// billet, jamais le défi.
    private var defi: String?
    private var sessionConnexion: ASWebAuthenticationSession?

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()          // la session persiste
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = [] // le klaxon du silence sonne sans clic
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        toile = WKWebView(frame: .zero, configuration: configuration)
        toile.navigationDelegate = self
        toile.uiDelegate = self
        toile.allowsBackForwardNavigationGestures = true
        toile.scrollView.contentInsetAdjustmentBehavior = .never
        toile.backgroundColor = UIColor(named: "Fond")
        toile.isOpaque = false
        // L'agent utilisateur du WKWebView : celui de Safari mobile, signé du nom
        // de l'application. Le site y lit « iPhone » — son mode téléphone.
        toile.customUserAgent = nil
        toile.evaluateJavaScript("navigator.userAgent") { [weak self] resultat, _ in
            if let ua = resultat as? String, let self = self {
                self.toile.customUserAgent = ua + " Rapporteur/\(self.pont.version)"
            }
        }
        pont.attacher(a: toile)
        view = toile
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        chargerAccueil()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    private func chargerAccueil(anglais: Bool = false) {
        toile.load(URLRequest(url: Self.site.appendingPathComponent(anglais ? "en/mobile" : "mobile")))
    }

    // MARK: - Le retour de la connexion (rapporteur://connexion?billet=…)

    func traiterLien(_ lien: URL) {
        guard lien.scheme == "rapporteur", lien.host == "connexion",
              let billet = URLComponents(url: lien, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "billet" })?.value, !billet.isEmpty else { return }
        var composants = URLComponents(url: Self.site.appendingPathComponent("api/connexion/mobile"),
                                       resolvingAgainstBaseURL: false)!
        composants.queryItems = [URLQueryItem(name: "billet", value: billet),
                                 URLQueryItem(name: "defi", value: defi ?? "")]
        defi = nil
        toile.load(URLRequest(url: composants.url!))
    }

    /// La page demande la connexion : on l'ouvre dans la fenêtre système
    /// d'authentification, armée du défi, et l'on attend rapporteur://.
    private func ouvrirLaConnexion(_ depart: URL) {
        defi = Self.fabriquerDefi()
        var composants = URLComponents(url: depart, resolvingAgainstBaseURL: false)!
        var items = composants.queryItems ?? []
        items.append(URLQueryItem(name: "application", value: "ios"))
        items.append(URLQueryItem(name: "defi", value: defi))
        composants.queryItems = items
        guard let url = composants.url else { return }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "rapporteur") { [weak self] retour, _ in
            self?.sessionConnexion = nil
            guard let retour = retour else { return } // annulé : on reste sur la page de connexion
            self?.traiterLien(retour)
        }
        session.presentationContextProvider = self
        // Partager les cookies de Safari : le client y est déjà connecté à
        // Google, ses vérifications (« c'est bien vous ? ») y aboutissent.
        session.prefersEphemeralWebBrowserSession = false
        sessionConnexion = session
        session.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }

    private static func fabriquerDefi() -> String {
        var graine = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, graine.count, &graine)
        return Data(graine).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Où la vue web a le droit d'aller

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let schema = url.scheme?.lowercased() ?? ""

        // Écrire à l'assistance depuis /aide, appeler : le téléphone prend le relais.
        if schema == "mailto" || schema == "tel" {
            UIApplication.shared.open(url); decisionHandler(.cancel); return
        }
        if schema == "rapporteur" { traiterLien(url); decisionHandler(.cancel); return }
        if schema != "https" && schema != "http" && schema != "file" && schema != "about" {
            UIApplication.shared.open(url); decisionHandler(.cancel); return
        }

        let hote = url.host?.lowercased() ?? ""
        if Self.hotes.contains(hote) {
            let chemin = url.path
            // Le clic sur la marque ramène à l'accueil de l'application, pas
            // à la page commerciale.
            if chemin.isEmpty || chemin == "/" { chargerAccueil(); decisionHandler(.cancel); return }
            if chemin == "/en" || chemin == "/en/" { chargerAccueil(anglais: true); decisionHandler(.cancel); return }
            if chemin == "/api/connexion" && action.targetFrame?.isMainFrame ?? true {
                ouvrirLaConnexion(url); decisionHandler(.cancel); return
            }
            // Version App Store : aucun achat dans l'application.
            if chemin.hasPrefix("/tarifs") || chemin.hasPrefix("/paiement")
                || chemin.hasPrefix("/en/tarifs") || chemin.hasPrefix("/en/paiement") {
                chargerAccueil(anglais: chemin.hasPrefix("/en/")); decisionHandler(.cancel); return
            }
            // Un lien « nouvelle fenêtre » vers notre site : dans la même vue.
            if action.targetFrame == nil { webView.load(URLRequest(url: url)); decisionHandler(.cancel); return }
            decisionHandler(.allow); return
        }

        if schema == "file" || schema == "about" { decisionHandler(.allow); return }

        // Caisses de paiement : lettre morte dans la version App Store.
        if hote.hasSuffix(".stripe.com") || hote.hasSuffix(".cinetpay.com") { decisionHandler(.cancel); return }

        // Tout autre site s'ouvre dans Safari : l'application ne montre que le nôtre.
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }

    // MARK: - Hors connexion

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        montrerHorsLigneSiBesoin(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        montrerHorsLigneSiBesoin(error)
    }

    private func montrerHorsLigneSiBesoin(_ error: Error) {
        let e = error as NSError
        // -999 : navigation annulée (une autre a pris sa place) — pas une panne.
        guard e.domain == NSURLErrorDomain, e.code != NSURLErrorCancelled else { return }
        // Une séance en cours ne doit pas être remplacée par l'écran hors ligne.
        guard !pont.captureEnCours else { return }
        if let page = Bundle.main.url(forResource: "hors-ligne", withExtension: "html") {
            toile.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Le moteur est mort (mémoire, mise à jour) : plutôt qu'un écran
        // blanc « qui ne s'ouvre plus », on recharge.
        if pont.captureEnCours { webView.reload() } else { chargerAccueil() }
    }

    // MARK: - Ce que la page demande à l'utilisateur

    /// Le micro d'une page : notre site seulement. La capture est native, la
    /// page ne devrait plus le demander — si elle le fait, elle l'obtient.
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let notre = Self.hotes.contains(origin.host.lowercased())
        decisionHandler(notre && type == .microphone ? .grant : .deny)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alerte = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alerte.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alerte, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alerte = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alerte.addAction(UIAlertAction(title: NSLocalizedString("Annuler", comment: ""), style: .cancel) { _ in completionHandler(false) })
        alerte.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alerte, animated: true)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // window.open : décidé par decidePolicyFor (targetFrame nil) ; jamais
        // de seconde vue.
        if let url = navigationAction.request.url {
            if Self.hotes.contains(url.host?.lowercased() ?? "") { webView.load(URLRequest(url: url)) }
            else { UIApplication.shared.open(url) }
        }
        return nil
    }
}

import UIKit
import WebKit

/// Un WKWebView plein écran qui charge lerapporteur.com/mobile — l'accueil de
/// l'application, le même que sur Android : un bouton micro au centre.
///
/// Ce que la vue web ne fait PAS elle-même, et que ce contrôleur décide :
///  - la connexion utilise exclusivement le code courriel de Rapporteur ;
///  - Turnstile reste dans son cadre web, sans ouvrir Safari ;
///  - version App Store : tarifs et caisses ne se chargent jamais (règle 3.1.1),
///    le site les masque déjà — ceci est la ceinture et les bretelles ;
///  - les autres sites s'ouvrent dans Safari ; hors connexion, un écran local.
final class ControleurPrincipal: UIViewController, WKNavigationDelegate, WKUIDelegate {

    static let site = URL(string: "https://lerapporteur.com")!
    private static let hotes: Set<String> = ["lerapporteur.com", "www.lerapporteur.com"]

    private var toile: WKWebView!
    private let pont = Pont()

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()          // la session persiste
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = [] // le klaxon du silence sonne sans clic
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        // Fixé avant toute navigation : Turnstile exige un agent stable.
        configuration.applicationNameForUserAgent = "Rapporteur/\(pont.version)"
        toile = WKWebView(frame: .zero, configuration: configuration)
        toile.navigationDelegate = self
        toile.uiDelegate = self
        toile.allowsBackForwardNavigationGestures = true
        toile.scrollView.contentInsetAdjustmentBehavior = .never
        toile.backgroundColor = UIColor(named: "Fond")
        toile.isOpaque = false
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

    // MARK: - Compatibilité avec les anciens liens de connexion

    func traiterLien(_ lien: URL) {
        guard lien.scheme == "rapporteur", lien.host == "connexion" else { return }
        toile.load(URLRequest(url: Self.site.appendingPathComponent("connexion")))
    }

    // MARK: - Où la vue web a le droit d'aller

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let destination = PolitiqueNavigation.destination(url,
            cadrePrincipal: action.targetFrame?.isMainFrame,
            sourcePrincipale: action.sourceFrame.isMainFrame,
            clic: action.navigationType == .linkActivated)
        switch destination {
        case .permettre: decisionHandler(.allow); return
        case .refuser: break
        case .externe: UIApplication.shared.open(url)
        case .charger: webView.load(action.request)
        case .accueil(let anglais): chargerAccueil(anglais: anglais)
        case .connexion(let anglais):
            var composants = URLComponents(url: Self.site.appendingPathComponent(anglais ? "en/connexion" : "connexion"),
                                           resolvingAgainstBaseURL: false)!
            composants.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.filter { $0.name == "retour" }
            if let connexion = composants.url { webView.load(URLRequest(url: connexion)) }
        case .retourConnexion: traiterLien(url)
        }
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
        let notre = origin.protocol == "https" && [0, 443].contains(origin.port)
            && frame.isMainFrame && Self.hotes.contains(origin.host.lowercased())
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
        // Toute navigation, y compris target=_blank, est traitée par la même
        // politique. Aucun second chemin ne peut ouvrir Safari depuis un cadre.
        return nil
    }
}

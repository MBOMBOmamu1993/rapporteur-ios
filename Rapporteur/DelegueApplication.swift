import UIKit
import UserNotifications

/// Rapporteur pour iPhone — la coquille.
///
/// Même philosophie que les applications Windows et Android : AUCUNE logique
/// du service ici. L'application charge lerapporteur.com/mobile et n'ajoute
/// que ce qu'une page web ne sait pas faire sur un iPhone :
///
///  - enregistrer par le micro ÉCRAN ÉTEINT (WebKit suspend la capture d'une
///    page dès que l'application passe en arrière-plan ; l'application capte
///    donc elle-même, avec AVAudioEngine et le mode audio en arrière-plan, et
///    rend le fichier à la page — voir `Enregistreur`) ;
///  - conclure la connexion Google hors de la vue web (Google refuse ses pages
///    aux vues web), par ASWebAuthenticationSession et le lien rapporteur:// ;
///  - poser une notification locale quand la salle alerte d'un silence.
///
/// Les clés, les prompts et la rédaction restent sur le serveur : il n'y a
/// rien à voler dans cette application. La session est le cookie du site.
@main
final class DelegueApplication: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = Notifications.partagees
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Principale", sessionRole: session.role)
    }
}

/// La scène unique : une fenêtre, un contrôleur, la vue web plein écran.
final class DelegueScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private weak var principal: ControleurPrincipal?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let controleur = ControleurPrincipal()
        principal = controleur
        let fenetre = UIWindow(windowScene: scene)
        fenetre.rootViewController = controleur
        fenetre.makeKeyAndVisible()
        window = fenetre
        // Lancée par un lien rapporteur:// (retour de connexion tapé dans Safari).
        options.urlContexts.forEach { controleur.traiterLien($0.url) }
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        contexts.forEach { principal?.traiterLien($0.url) }
    }
}

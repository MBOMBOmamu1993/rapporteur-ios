import UserNotifications
import UIKit

/// Les notifications locales : l'avertisseur de silence de la salle en pose
/// une quand plus rien n'est capté — écran éteint, c'est le seul moyen de
/// prévenir. Demandée au premier besoin, jamais au lancement.
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    static let partagees = Notifications()

    func poser(titre: String, texte: String) {
        let centre = UNUserNotificationCenter.current()
        centre.getNotificationSettings { reglages in
            switch reglages.authorizationStatus {
            case .notDetermined:
                centre.requestAuthorization(options: [.alert, .sound]) { accorde, _ in
                    if accorde { self.envoyer(titre: titre, texte: texte) }
                }
            case .authorized, .provisional, .ephemeral:
                self.envoyer(titre: titre, texte: texte)
            default:
                break
            }
        }
    }

    private func envoyer(titre: String, texte: String) {
        let contenu = UNMutableNotificationContent()
        contenu.title = titre
        contenu.body = texte
        contenu.sound = .default
        // Un seul identifiant : l'alerte suivante remplace la précédente,
        // comme le `tag` de la notification web.
        let demande = UNNotificationRequest(identifier: "rapporteur-silence", content: contenu, trigger: nil)
        UNUserNotificationCenter.current().add(demande)
    }

    /// Au premier plan aussi : la salle elle-même affiche déjà son encadré,
    /// mais l'écran peut être sur une autre application.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}

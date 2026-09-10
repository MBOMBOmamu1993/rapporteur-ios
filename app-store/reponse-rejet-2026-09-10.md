Hello App Review Team,

Thank you for the specific reproduction details. We identified and corrected the iOS navigation defect behind the Cloudflare/Safari behavior and the blocked email-code request. Please review the replacement build 1.1.5 (5).

GUIDELINE 2.1 — EMAIL CODE AND SAFARI
Cloudflare Turnstile verifies that a code request comes from a human, to prevent automated email abuse. The previous iOS navigation delegate incorrectly treated the embedded Cloudflare challenge frame as an external website, cancelled it, and opened Safari. The verification could not complete inside the app, so the email-code step could not proceed. This was an app defect, not an action we expect the reviewer to work around.

The replacement build keeps HTTPS challenges.cloudflare.com frames and the required about:blank/about:srcdoc frames inside WKWebView. Frames cannot launch Safari or other apps. External navigation now requires a user-initiated link from the main page. The user agent is stable before the first navigation. The web form waits for verification and continues automatically; it reports loading/network failures, allows retries, and resets the widget by its identifier. Server-side validation and rate limits remain active.

GUIDELINE 4.8 — LOGIN SERVICES
The iOS app now exclusively uses Rapporteur's own passwordless account creation and email-code sign-in. Google Sign-In is no longer offered or opened by the iOS app. This follows the guideline 4.8 exception for apps that exclusively use the company's own account setup and sign-in systems. Existing customers can use their existing email address to access the same account.

REVIEW ACCESS
Open Sign in, enter demo@lerapporteur.com, then tap “I already have a code” / “J’ai déjà un code”. Enter the six-digit code from the Password field in App Review Information. This uses the normal server-side code verification endpoint. For an ordinary account, tap “Email me a sign-in code” / “Recevoir un code de connexion”, complete the human verification if requested, and enter the emailed code.

PHYSICAL IPHONE VIDEO
Please see rapporteur-test-iphone-reel-2026-09-09.mp4, already attached under App Review Information > Attachment for version 1.1.5. Please open that attachment when reviewing this response. It was recorded on a physical iPhone on September 9 and added to the version notes after our initial reply. Please disregard the now-outdated statement in our September 9 message that no physical-device recording was available. This existing recording demonstrates the earlier build's meeting recording, account interface/deletion controls and receipt of the report by email. Its Google login footage predates the email-only change in the replacement build; it is not presented as a recording of build 5.

Thank you for reviewing the corrected build and the physical-device video.

/*
 * Le panneau de réunion se présente comme un ORDINATEUR (Safari sur Mac) : à un
 * téléphone, Teams ne sert que sa page « Rejoindre la réunion », qui mène à l'App
 * Store et sortirait la réunion de Rapporteur ; à un ordinateur, il propose
 * « Continuer sur ce navigateur », et la réunion se tient ici.
 *
 * L'agent de Mac ne suffit pas sur un vrai iPhone (essai de Felly, 17/10/2026,
 * iPhone 17 Pro Max : page téléphone de Teams, puis l'App Store) : la page lit
 * aussi la plateforme (« iPhone ») et l'écran tactile, et les deux réunis la font
 * basculer — plateforme Mac seule, Teams y voit un iPad. Mesuré sur le moteur de
 * Safari : plateforme Mac ET tactile tu → « Continuer sur ce navigateur ».
 *
 * Posé au tout début du document, avant les scripts de la page, dans les pages des
 * services de réunion connus seulement. Les touchers restent des clics pour la page.
 */
(function () {
  "use strict";
  var hote = String(location.hostname || "").toLowerCase();
  function domaine(d) { return hote === d || hote.slice(-(d.length + 1)) === "." + d; }
  var connu = hote === "meet.google.com" || domaine("teams.microsoft.com") || domaine("teams.live.com") ||
    domaine("zoom.us") || hote.slice(-10) === ".webex.com" || hote === "meet.jit.si" || domaine("whereby.com");
  if (!connu) { return; }
  function poser(nom, valeur) {
    try { Object.defineProperty(Navigator.prototype, nom, { configurable: true, get: function () { return valeur; } }); } catch (e) { /* tant pis */ }
  }
  poser("platform", "MacIntel");
  poser("maxTouchPoints", 0);
})();

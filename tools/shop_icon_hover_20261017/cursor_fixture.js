// Test-only input inside the Panorama VM. This file is never loaded by the game.
(function () {
    "use strict";
    var cfg = GameUI.CustomUIConfig();
    GameUI.GetCursorPosition = function () { return cfg.__shopIconHoverTestPointer || null; };
})();

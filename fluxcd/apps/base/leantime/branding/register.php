<?php

// Instance branding, loaded as a system plugin (LEAN_PLUGINS), so it applies under every theme.

use Leantime\Core\Events\EventDispatcher;

// Monofur as its own entry in Theme -> Font; the stylesheet reads the entry's name as the font family.
EventDispatcher::addFilterListener('leantime.core.ui.theme.*.fonts', function ($fonts) {
    return $fonts + ['monofur' => 'Monofur'];
});

EventDispatcher::add_event_listener('leantime.*.afterLinkTags', function () {
    echo '<style id="optcpBranding">
@font-face {
  font-family: "Monofur";
  src: url("'.BASE_URL.'/dist/fonts/monofur.woff2") format("woff2");
  font-display: swap;
}
/* Leantime marketing quotes on the sign-in / sign-out panel */
.row .regLeft .socialProofContent { display: none; }
/* The en-US.ini label override never loads on an en-US install (duplicate key in Language::readIni) */
a.btn[href$="/oidc/login"] { font-size: 0; }
a.btn[href$="/oidc/login"]::after { content: "PrPlanIT SSO"; font-size: var(--base-font-size, 14px); }
</style>';
});

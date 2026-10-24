const supported = iina.appearance && typeof iina.appearance.getTheme === 'function';
if (supported) {
  iina.console.log('PLAYER_APPEARANCE ' + JSON.stringify(iina.appearance.getTheme()));
  iina.appearance.onChange(theme => {
    iina.console.log('PLAYER_APPEARANCE_CHANGED ' + JSON.stringify(theme));
  });
}
function menu(title, action) {
  iina.menu.addItem(iina.menu.item(title, action));
}
function sidebar() {
  iina.sidebar.loadFile('panel.html');
  iina.sidebar.show();
}
iina.event.on('iina.window-loaded', sidebar);
menu('Accent API — Show Sidebar', sidebar);
menu('Accent API — Open Standalone', () => {
  iina.standaloneWindow.loadFile('panel.html');
  iina.standaloneWindow.setProperty({ title: 'Accent API Fixture' });
  iina.standaloneWindow.open();
});
menu('Accent API — Open Simple Mode', () => {
  iina.standaloneWindow.simpleMode();
  iina.standaloneWindow.setStyle(`
    :root { color-scheme: light dark; }
    body { padding: 24px; color: #222; color: CanvasText; }
    @media (prefers-color-scheme: dark) { body { color: #eee; } }
    h2 { font-size: 20px; color: inherit; }
    button { background: var(--iina-accent-color, #007AFF); color: var(--iina-accent-text-color, #fff);
      border: 0; border-radius: 7px; padding: 10px 16px; font: inherit; }
    code { font-family: ui-monospace, monospace; }
  `);
  iina.standaloneWindow.setContent('<h2>Simple Mode</h2><p>This native simpleMode template receives the same CSS tokens and browser API.</p><button>Token button</button><p>Inspect <code>iina.appearance.getTheme()</code> in the Web Inspector.</p>');
  iina.standaloneWindow.open();
});
let overlayRequested = false;
iina.event.on('iina.plugin-overlay-loaded', () => {
  if (overlayRequested) iina.overlay.show();
});
menu('Accent API — Show Overlay', () => {
  overlayRequested = true;
  iina.overlay.loadFile('overlay.html');
  iina.overlay.setClickable(true);
});
menu('Accent API — Hide Overlay', () => {
  overlayRequested = false;
  iina.overlay.hide();
});

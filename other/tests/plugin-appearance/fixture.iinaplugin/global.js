// This entry intentionally creates no player/window. It verifies global export.
if (iina.appearance && typeof iina.appearance.getTheme === 'function') {
  iina.console.log('GLOBAL_APPEARANCE ' + JSON.stringify(iina.appearance.getTheme()));
  iina.appearance.onChange(theme => {
    iina.console.log('GLOBAL_APPEARANCE_CHANGED ' + JSON.stringify(theme));
  });
} else {
  iina.console.log('GLOBAL_APPEARANCE unsupported (stock IINA fallback)');
}

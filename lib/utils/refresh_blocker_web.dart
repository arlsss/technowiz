// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

html.EventListener? _beforeUnloadListener;
html.EventListener? _keyDownListener;

void enableRefreshBlocker() {
  disableRefreshBlocker();

  // Intercept browser refresh/reload attempts (like reload button)
  _beforeUnloadListener = (html.Event event) {
    event.preventDefault();
    if (event is html.BeforeUnloadEvent) {
      event.returnValue = '';
    }
  };
  html.window.addEventListener('beforeunload', _beforeUnloadListener);

  // Intercept keyboard reload shortcuts: F5, Ctrl+R, Command+R
  _keyDownListener = (html.Event event) {
    if (event is html.KeyboardEvent) {
      final isF5 = event.keyCode == 116 || event.key == 'F5';
      final isCtrlOrCmd = event.ctrlKey || event.metaKey;
      final isR = event.keyCode == 82 || event.key == 'r' || event.key == 'R';

      if (isF5 || (isCtrlOrCmd && isR)) {
        event.preventDefault();
        event.stopPropagation();
      }
    }
  };
  html.window.addEventListener('keydown', _keyDownListener, true);
}

void disableRefreshBlocker() {
  if (_beforeUnloadListener != null) {
    html.window.removeEventListener('beforeunload', _beforeUnloadListener);
    _beforeUnloadListener = null;
  }
  if (_keyDownListener != null) {
    html.window.removeEventListener('keydown', _keyDownListener, true);
    _keyDownListener = null;
  }
}


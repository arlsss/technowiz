import 'package:flutter/foundation.dart';
import 'refresh_blocker_stub.dart'
    if (dart.library.html) 'refresh_blocker_web.dart';

class RefreshBlocker {
  static void block() {
    if (kIsWeb) {
      enableRefreshBlocker();
    }
  }

  static void unblock() {
    if (kIsWeb) {
      disableRefreshBlocker();
    }
  }
}


import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Centralized service to manage online/offline presence for all users across TechNoWiz.
class UserPresenceService with WidgetsBindingObserver {
  UserPresenceService._internal();
  static final UserPresenceService instance = UserPresenceService._internal();

  Timer? _heartbeatTimer;
  bool _isObserverRegistered = false;
  String? _currentTrackingUid;

  /// Call once at app startup or when a user logs in.
  void init() {
    if (!_isObserverRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _isObserverRegistered = true;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setOnline(user.uid);
    }
  }

  /// Mark the user as online in Firestore and keep their presence fresh with a heartbeat.
  Future<void> setOnline([String? uid]) async {
    final targetUid = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (targetUid == null || targetUid.isEmpty) return;

    _currentTrackingUid = targetUid;

    try {
      await FirebaseFirestore.instance.collection('users').doc(targetUid).update({
        'isOnline': true,
        'status': 'Online',
        'lastSeen': FieldValue.serverTimestamp(),
        'lastActive': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠️ UserPresence setOnline error: $e');
    }

    _startHeartbeat(targetUid);
  }

  /// Mark the user as offline in Firestore and stop the heartbeat.
  Future<void> setOffline([String? uid]) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final targetUid =
        uid ?? _currentTrackingUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (targetUid == null || targetUid.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(targetUid).update({
        'isOnline': false,
        'status': 'Offline',
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠️ UserPresence setOffline error: $e');
    }
  }

  void _startHeartbeat(String uid) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null || currentUser.uid != uid) {
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
        return;
      }
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'isOnline': true,
          'status': 'Online',
          'lastSeen': FieldValue.serverTimestamp(),
          'lastActive': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('⚠️ UserPresence heartbeat error: $e');
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = _currentTrackingUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (state == AppLifecycleState.resumed) {
      setOnline(uid);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      setOffline(uid);
    }
  }

  /// Evaluates whether a user's Firestore record represents an active/online session.
  /// 
  /// A user is considered Active if:
  /// 1. They are the user currently running the app, OR
  /// 2. `isOnline == true` AND their last activity (`lastSeen`, `lastActive`, or `lastLogin`)
  ///    was within the last 3 minutes.
  /// Otherwise, they are treated as Offline.
  static bool isUserActive(Map<String, dynamic> data, {String? docUid}) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null &&
        (docUid == currentUid || data['uid'] == currentUid)) {
      return true;
    }

    final bool isOnlineFlag = data['isOnline'] == true ||
        (data['status'] ?? '').toString().trim().toLowerCase() == 'online';
    if (!isOnlineFlag) return false;

    final dynamic lastSeenRaw =
        data['lastSeen'] ?? data['lastActive'] ?? data['lastLogin'];
    if (lastSeenRaw is Timestamp) {
      final lastSeen = lastSeenRaw.toDate();
      final diff = DateTime.now().difference(lastSeen);
      return diff.inMinutes < 3;
    }

    return false;
  }
}

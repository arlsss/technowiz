import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('======================================');
  debugPrint('TECHNOWIZ MAIN STARTING');
  debugPrint('======================================');

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('FIREBASE INITIALIZED');

  // Configure web persistence before creating the app's auth listener.
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    debugPrint('WEB AUTH PERSISTENCE SET TO LOCAL');
  } else {
    debugPrint('MOBILE AUTH PERSISTENCE HANDLED BY FIREBASE');
  }

  // Do not wait here for authStateChanges().first. Waiting before runApp()
  // leaves the browser showing a blank page during auth restoration.
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TechNoWiz',
      home: SplashScreen(),
    );
  }
}

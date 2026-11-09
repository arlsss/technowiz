import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth auth = FirebaseAuth.instance;

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future registerUser(
    String name,
    String email,
    String password,
    String role,
  ) async {
    UserCredential result = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    User? user = result.user;

    await firestore.collection("users").doc(user!.uid).set({
      "uid": user.uid,
      "name": name,
      "email": email,
      "role": role,
    });
  }

  Future loginUser(String email, String password) async {
    UserCredential result = await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    return result.user;
  }
}

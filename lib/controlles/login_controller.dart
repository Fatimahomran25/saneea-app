import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/login_model.dart';
import 'dart:async';
import 'messaging_controller.dart';

class LoginController {
  final LoginModel model = LoginModel();

  final nationalIdCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();

  bool submitted = false;
  bool isLoading = false;
  bool obscurePassword = true;

  String? serverError;

  void togglePasswordVisibility() {
    obscurePassword = !obscurePassword;
  }

  void submit() {
    submitted = true;
  }

  void dispose() {
    nationalIdCtrl.dispose();
    passwordCtrl.dispose();
  }

  // ==========================
  // Validation
  // ==========================

  bool get isNationalIdValid {
    final v = nationalIdCtrl.text.trim();
    return v.length == 10;
  }

  bool get allRequiredValid =>
      isNationalIdValid && passwordCtrl.text.trim().isNotEmpty;

  // ==========================
  // Field Errors
  // ==========================

  String? get nationalIdFieldError {
    final v = nationalIdCtrl.text.trim();
    if (!submitted) return null;
    if (v.isEmpty) return 'National ID / Iqama is required.';
    if (v.length != 10) return 'National ID / Iqama must be 10 digits.';
    return null;
  }

  String? get passwordFieldError {
    final v = passwordCtrl.text;
    if (!submitted) return null;
    if (v.trim().isEmpty) return 'Password is required.';
    return null;
  }

  // ==========================
  // Firebase Helpers
  // ==========================

  Future<String?> _emailByNationalId(String nid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('nationalId', isEqualTo: nid)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 12));

      if (snap.docs.isEmpty) return null;

      final data = snap.docs.first.data();
      final email = (data['email'] ?? '').toString().trim();
      return email.isEmpty ? null : email;
    } on TimeoutException {
      throw FirebaseAuthException(code: 'network-request-failed');
    } on FirebaseException catch (e) {
      throw FirebaseAuthException(code: e.code, message: e.message);
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'National ID / Password is incorrect.';
      case 'network-request-failed':
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Check your internet connection.';
      case 'permission-denied':
        return 'Login lookup is blocked by database rules.';
      case 'operation-not-allowed':
        return 'Login service is currently unavailable.';
      default:
        return 'Login failed. Please try again. (${e.code})';
    }
  }

  Future<bool> login() async {
    serverError = null;
    submitted = true;

    if (!allRequiredValid) return false;

    final nid = nationalIdCtrl.text.trim();
    final pass = passwordCtrl.text;
    isLoading = true;

    try {
      final email = await _emailByNationalId(nid);
      if (email == null) {
        serverError = 'National ID / Password is incorrect.';
        return false;
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: pass,
      );

      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Login failed: ${e.code} ${e.message ?? ''}');
      serverError = _mapAuthError(e);
      return false;
    } catch (_) {
      serverError = 'Something went wrong. Try again.';
      return false;
    } finally {
      isLoading = false;
    }
  }

  Future<void> logout() async {
    // خطوة تنظيف ثانوية (إشعارات)؛ فشلها ما يفترض يمنع تسجيل الخروج.
    try {
      final messagingController = MessagingController();
      await messagingController.clearToken();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }
}

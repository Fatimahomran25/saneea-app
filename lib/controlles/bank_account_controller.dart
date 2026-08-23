import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/bank_account_model.dart';

// يحوّل أخطاء Firebase التقنية الخام إلى رسالة مفهومة للمستخدم، بدل
// عرض النص التقني الخام.
String _friendlyError(Object e) {
  if (e is FirebaseException) {
    switch (e.code) {
      case 'quota-exceeded':
        return "We're experiencing high demand right now. Please try again later.";
      case 'unauthorized':
      case 'permission-denied':
        return "You don't have permission to do this.";
      case 'unauthenticated':
        return "Please log in again and try.";
      case 'network-request-failed':
      case 'unavailable':
        return "Network error. Please check your connection and try again.";
      case 'canceled':
        return "Upload was canceled.";
      default:
        return "Something went wrong. Please try again.";
    }
  }
  return "Something went wrong. Please try again.";
}

class BankAccountController extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  bool isLoading = true;
  bool isSaving = false;
  String? error;

  // ✅ saved from DB
  BankAccountModel? bank;

  // form controllers
  final ibanCtrl = TextEditingController();
  final cardCtrl = TextEditingController();   // NOT stored fully
  final expiryCtrl = TextEditingController(); // stored (MM/YY)
  final cvcCtrl = TextEditingController();    // NEVER stored

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  String _cleanIban(String s) => s.replaceAll(' ', '').toUpperCase();
  String _digitsOnly(String s) => s.replaceAll(' ', '').trim();

  bool get hasSavedCard => (bank?.cardLast4 ?? '').isNotEmpty;
  bool get hasSavedIban => (bank?.iban ?? '').isNotEmpty;
  bool get hasSavedExpiry => (bank?.cardExpiry ?? '').isNotEmpty;

  String? get savedIban => bank?.iban;
  String? get savedCardLast4 => bank?.cardLast4;
  String? get savedExpiry => bank?.cardExpiry;

  // -------------------- INIT --------------------
  Future<void> init() async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) throw 'Not logged in';

      final doc = await _userDoc(user.uid).get();
      final data = doc.data();

      bank = BankAccountModel.fromUserDoc(data);

      // ✅ نعبّي IBAN من الداتا (مو من الفورم السابق)
      ibanCtrl.text = bank?.iban ?? '';

      // ❌ لا نعبّي البطاقة/CVC لأنها حساسة
      cardCtrl.clear();
      expiryCtrl.clear();
      cvcCtrl.clear();

      isLoading = false;
      notifyListeners();
    } catch (e) {
      error = _friendlyError(e);
      isLoading = false;
      notifyListeners();
    }
  }

  // -------------------- VALIDATORS --------------------
  String? validateIban(String? v) {
    final s = _cleanIban((v ?? '').trim());
    if (s.isEmpty) return 'IBAN is required';
    if (!RegExp(r'^SA\d{22}$').hasMatch(s)) {
      return 'IBAN must be SA + 22 digits (24 chars)';
    }
    return null;
  }

  // ✅ إذا عندي بطاقة محفوظة: لو تركه فاضي ما نطلبه
  String? validateCard(String? v) {
    final s = _digitsOnly(v ?? '');
    if (hasSavedCard && s.isEmpty) return null;

    if (s.isEmpty) return 'Card number is required';
    if (!RegExp(r'^\d{16}$').hasMatch(s)) return 'Card number must be 16 digits';
    return null;
  }

  String? validateExpiry(String? v) {
    final s = (v ?? '').trim();
    if (hasSavedCard && s.isEmpty) return null;

    if (s.isEmpty) return 'Expiry is required';
    if (!RegExp(r'^(0[1-9]|1[0-2])\/\d{2}$').hasMatch(s)) return 'Use MM/YY';
    return null;
  }

  String? validateCvc(String? v) {
    final s = (v ?? '').trim();
    if (hasSavedCard && s.isEmpty) return null;

    if (s.isEmpty) return 'CVC is required';
    if (!RegExp(r'^\d{3}$').hasMatch(s)) return 'CVC must be 3 digits';
    return null;
  }

  // -------------------- SAVE --------------------
  Future<bool> saveBankInfo() async {
    final user = _auth.currentUser;
    if (user == null) {
      error = 'Not logged in';
      notifyListeners();
      return false;
    }

    isSaving = true;
    error = null;
    notifyListeners();

    try {
      final iban = _cleanIban(ibanCtrl.text);

      final cardDigits = _digitsOnly(cardCtrl.text);
      final expiry = expiryCtrl.text.trim();
      final cvc = cvcCtrl.text.trim();

      // ✅ last4/expiry لو المستخدم دخل بطاقة جديدة
      String last4 = bank?.cardLast4 ?? '';
      String expiryToSave = bank?.cardExpiry ?? '';

      if (cardDigits.isNotEmpty) {
        last4 = cardDigits.substring(cardDigits.length - 4);
        expiryToSave = expiry;
        // ❌ cvc never stored (for validation only)
        debugPrint("CVC received (not stored): $cvc");
      }

      await _userDoc(user.uid).set({
        'iban': iban,
        'cardLast4': last4,
        'cardExpiry': expiryToSave,
        'bankUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ✅ update local model
      bank = BankAccountModel(
        iban: iban,
        cardLast4: last4.isEmpty ? null : last4,
        cardExpiry: expiryToSave.isEmpty ? null : expiryToSave,
        updatedAt: DateTime.now(),
      );

      // ✅ clear sensitive fields
      cardCtrl.clear();
      expiryCtrl.clear();
      cvcCtrl.clear();

      isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = _friendlyError(e);
      debugPrint("SAVE ERROR: $e");
      isSaving = false;
      notifyListeners();
      return false;
    }
  }

  // -------------------- DELETE --------------------
  Future<bool> deleteBankInfo() async {
    final user = _auth.currentUser;
    if (user == null) {
      error = 'Not logged in';
      notifyListeners();
      return false;
    }

    isSaving = true;
    error = null;
    notifyListeners();

    try {
      await _userDoc(user.uid).update({
        'iban': FieldValue.delete(),
        'cardLast4': FieldValue.delete(),
        'cardExpiry': FieldValue.delete(),
        'bankUpdatedAt': FieldValue.delete(),
      });

      bank = const BankAccountModel(
        iban: null,
        cardLast4: null,
        cardExpiry: null,
        updatedAt: null,
      );

      ibanCtrl.clear();
      cardCtrl.clear();
      expiryCtrl.clear();
      cvcCtrl.clear();

      isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = _friendlyError(e);
      debugPrint("DELETE ERROR: $e");
      isSaving = false;
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    ibanCtrl.dispose();
    cardCtrl.dispose();
    expiryCtrl.dispose();
    cvcCtrl.dispose();
    super.dispose();
  }
}
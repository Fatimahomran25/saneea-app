import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/client_profile_model.dart';
import 'account_access_service.dart';
import 'messaging_controller.dart';

// يحوّل أخطاء Firebase التقنية الخام إلى رسالة مفهومة للمستخدم، بدل
// عرض النص التقني الخام (اسم bucket، روابط، أكواد داخلية...).
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

class ClientProfileController extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final AccountAccessService _accountAccessService = AccountAccessService();

  bool isLoading = true;
  bool isSaving = false;
  bool isEditing = false;
  String? error;

  ClientProfileModel? profile;
  List<ClientReviewModel> reviews = [];

  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final bioCtrl = TextEditingController();

  Uint8List? pickedImageFile;
  String? viewedUserId;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  static const int bioMax = 150;
  final RegExp gmailReg = RegExp(r'^[a-zA-Z0-9._%+-]+@gmail\.com$');

  int get bioLen => bioCtrl.text.length;

  bool get isOwnProfile {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null || profile == null) return true;
    return profile!.uid == currentUid;
  }

  Future<void> init({String? userId}) async {
    isLoading = true;
    error = null;
    viewedUserId = userId;
    notifyListeners();

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        error = "Not logged in";
        isLoading = false;
        notifyListeners();
        return;
      }

      final targetUid = userId ?? currentUser.uid;

      await _profileSub?.cancel();

      _profileSub = _db.collection('users').doc(targetUid).snapshots().listen((
        doc,
      ) async {
        try {
          final data = doc.data() ?? {};

          final fetchedReviews = await _fetchReviews(targetUid);
          final rating = _avgRating(fetchedReviews);

          profile = ClientProfileModel.fromFirestore(
            uid: targetUid,
            data: data,
            rating: rating,
          );

          reviews = fetchedReviews;

          if (!isEditing && profile != null) {
            nameCtrl.text = profile!.name;
            emailCtrl.text = profile!.email;
            bioCtrl.text = profile!.bio;
          }

          error = null;
          isLoading = false;
          notifyListeners();
        } catch (e) {
          error = _friendlyError(e);
          isLoading = false;
          notifyListeners();
        }
      });
    } catch (e) {
      error = _friendlyError(e);
      isLoading = false;
      notifyListeners();
    }
  }

  Future<List<ClientReviewModel>> _fetchReviews(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    final enrichedReviews = await _withResolvedReviewerProfileUrls(snap.docs);

    return enrichedReviews
        .map((data) => ClientReviewModel.fromFirestore(data))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _withResolvedReviewerProfileUrls(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final missingReviewerIds = <String>{};

    for (final doc in docs) {
      final data = doc.data();
      final reviewerProfileUrl = ((data['reviewerProfileUrl'] ??
                  data['senderProfileUrl'] ??
                  data['senderProfileImage']) ??
              '')
          .toString()
          .trim();
      final reviewerId = (data['reviewerId'] ?? '').toString().trim();

      if (reviewerProfileUrl.isEmpty && reviewerId.isNotEmpty) {
        missingReviewerIds.add(reviewerId);
      }
    }

    final resolvedUrls = <String, String>{};
    if (missingReviewerIds.isNotEmpty) {
      final userDocs = await Future.wait(
        missingReviewerIds.map((reviewerId) {
          return _db.collection('users').doc(reviewerId).get();
        }),
      );

      for (final userDoc in userDocs) {
        final userData = userDoc.data();
        if (userData == null) continue;
        final reviewerId = userDoc.id;
        final profileUrl = ((userData['photoUrl'] ?? userData['profile']) ?? '')
            .toString()
            .trim();
        if (profileUrl.isNotEmpty) {
          resolvedUrls[reviewerId] = profileUrl;
        }
      }
    }

    return docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      final reviewerProfileUrl = ((data['reviewerProfileUrl'] ??
                  data['senderProfileUrl'] ??
                  data['senderProfileImage']) ??
              '')
          .toString()
          .trim();
      final reviewerId = (data['reviewerId'] ?? '').toString().trim();

      if (reviewerProfileUrl.isEmpty &&
          reviewerId.isNotEmpty &&
          resolvedUrls.containsKey(reviewerId)) {
        data['reviewerProfileUrl'] = resolvedUrls[reviewerId];
      }

      return data;
    }).toList();
  }

  double _avgRating(List<ClientReviewModel> list) {
    if (list.isEmpty) return 0;
    final sum = list.fold<int>(0, (prev, review) => prev + review.rating);
    return double.parse((sum / list.length).toStringAsFixed(1));
  }

  Future<void> deleteProfileImage() async {
    if (!isOwnProfile) return;

    final user = _auth.currentUser;
    if (user == null) return;
    error = null;

    if (await _accountAccessService.isCurrentUserBlocked()) {
      error = AccountAccessService.blockedActionMessage;
      notifyListeners();
      return;
    }

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};

      final photoUrl = (data['photoUrl'] ?? data['profile'] ?? '').toString();

      if (photoUrl.isNotEmpty) {
        final ref = _storage.refFromURL(photoUrl);
        await ref.delete();
      }

      await _db.collection('users').doc(user.uid).update({
        'photoUrl': FieldValue.delete(),
        'profile': FieldValue.delete(),
      });

      profile = profile?.copyWith(clearPhotoUrl: true);
      pickedImageFile = null;
      notifyListeners();
    } catch (e) {
      debugPrint("DELETE IMAGE ERROR: $e");
    }
  }

  void startEdit() {
    if (profile == null || !isOwnProfile) return;
    isEditing = true;
    notifyListeners();
  }

  void cancelEdit() {
    if (profile == null) return;

    isEditing = false;
    pickedImageFile = null;

    nameCtrl.text = profile!.name;
    emailCtrl.text = profile!.email;
    bioCtrl.text = profile!.bio;

    notifyListeners();
  }

  String? validateName(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return "Name is required";
    if (text.length < 2) return "Name is too short";
    return null;
  }

  String? validateGmail(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return "Email is required";
    if (!gmailReg.hasMatch(text)) {
      return "Enter a valid gmail (name@gmail.com)";
    }
    return null;
  }

  String? validateBio(String? value) {
    final text = value ?? '';
    if (text.length > bioMax) {
      return "Bio must be $bioMax characters or less";
    }
    return null;
  }

  void setPickedImage(Uint8List bytes) {
    if (!isEditing || !isOwnProfile) return;
    pickedImageFile = bytes;
    notifyListeners();
  }

  Future<String?> _uploadProfileImage(String uid) async {
    if (pickedImageFile == null) return profile?.photoUrl;

    final ref = _storage.ref().child('profile_images').child('$uid.jpg');
    await ref.putData(
      pickedImageFile!,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return await ref.getDownloadURL();
  }

  Future<bool> save() async {
    if (profile == null || !isOwnProfile) return false;

    isSaving = true;
    error = null;
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) throw "Not logged in";
      await _accountAccessService.ensureCurrentUserNotBlocked();

      final newName = nameCtrl.text.trim();
      final parts = newName
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList();

      final firstName = parts.isNotEmpty ? parts.first : '';
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      final newEmail = emailCtrl.text.trim();
      final safeBio = bioCtrl.text.length > bioMax
          ? bioCtrl.text.substring(0, bioMax)
          : bioCtrl.text;

      final photoUrl = await _uploadProfileImage(user.uid);

      await _db.collection('users').doc(user.uid).set({
        'accountType': 'client',
        'name': newName,
        'firstName': firstName,
        'lastName': lastName,
        'email': newEmail,
        'bio': safeBio,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (photoUrl != null) 'profile': photoUrl,
      }, SetOptions(merge: true));

      final fetchedReviews = await _fetchReviews(user.uid);
      final rating = _avgRating(fetchedReviews);

      reviews = fetchedReviews;
      profile = profile!.copyWith(
        name: newName,
        email: newEmail,
        bio: safeBio,
        photoUrl: photoUrl,
        rating: rating,
      );

      isSaving = false;
      isEditing = false;
      pickedImageFile = null;
      notifyListeners();
      return true;
    } catch (e) {
      error = _friendlyError(e);
      isSaving = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout(BuildContext context) async {
    // خطوة تنظيف ثانوية (إشعارات)؛ فشلها ما يفترض يمنع تسجيل الخروج.
    try {
      final messagingController = MessagingController();
      await messagingController.clearToken();
    } catch (_) {}
    await _auth.signOut();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  Future<void> deleteAccount(BuildContext context) async {
    if (!isOwnProfile) return;

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final requestsSnapshot = await _db
          .collection('requests')
          .where('clientId', isEqualTo: user.uid)
          .get();

      for (final doc in requestsSnapshot.docs) {
        final data = doc.data();
        if (data['status'] == 'pending') {
          await doc.reference.update({
            'status': 'cancelled_by_client',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await _db.collection('users').doc(user.uid).delete();
      await user.delete();

      if (!context.mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/signup', (_) => false);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    nameCtrl.dispose();
    emailCtrl.dispose();
    bioCtrl.dispose();
    super.dispose();
  }
}

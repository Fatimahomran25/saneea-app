import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/freelancer_profile_model.dart';
import 'account_access_service.dart';
import 'messaging_controller.dart';

class FreelancerProfileController extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final AccountAccessService _accountAccessService = AccountAccessService();

  bool isLoading = true;
  bool isSaving = false;
  bool isEditing = false;

  String? error;
  FreelancerProfileModel? profile;
  List<FreelancerReviewModel> reviews = [];
  // ✅ name as 2 fields
  final firstNameCtrl = TextEditingController();
  final lastNameCtrl = TextEditingController();

  final emailCtrl = TextEditingController();
  final bioCtrl = TextEditingController();

  // IBAN
  final ibanCtrl = TextEditingController();

  // نستخدم bytes بدل dart:io File عشان يشتغل على كل المنصات (الويب
  // مو مدعوم فيه Image.file / putFile إطلاقاً).
  Uint8List? pickedImageFile;
  final List<Uint8List> pickedPortfolioFiles = [];

  static const int bioMax = 150;
  final RegExp gmailReg = RegExp(r'^[a-zA-Z0-9._%+-]+@gmail\.com$');

  static const List<String> serviceTypeOptions = [
    "one-time",
    "long-term",
    "both",
  ];
  static const List<String> workingModeOptions = [
    "online",
    "in-person",
    "both",
  ];
  static const List<String> serviceFieldOptions = [
    'Graphic Designers',
    'Software Developers',
    'Marketing',
    'Accounting',
    'Tutoring',
  ];

  int get bioLen => bioCtrl.text.length;
  String normalizeServiceField(String value) {
    switch (value.trim()) {
      case 'Graphic Designer':
        return 'Graphic Designers';
      case 'Software Developer':
        return 'Software Developers';
      case 'Marketer':
      case 'Marketering':
        return 'Marketing';
      case 'Accountant':
        return 'Accounting';
      case 'Tutor':
        return 'Tutoring';
      default:
        return value;
    }
  }

  Future<void> init({String? userId}) async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final uid = userId ?? _auth.currentUser?.uid;

      if (uid == null) {
        error = "User not found";
        isLoading = false;
        notifyListeners();
        return;
      }

      final doc = await _db.collection('users').doc(uid).get();
      final data = doc.data();

      if (data == null) {
        error = "User data not found";
        isLoading = false;
        notifyListeners();
        return;
      }

      reviews = await _fetchReviews(uid);
      final rating = _avgRating(reviews);

      profile = FreelancerProfileModel.fromFirestore(
        uid: uid,
        data: data,
        rating: rating,
      );

      profile = profile!.copyWith(
        serviceField: normalizeServiceField(profile!.serviceField ?? ''),
      );

      // تعبئة البيانات
      firstNameCtrl.text = capitalizeWords(profile!.firstName);
      lastNameCtrl.text = capitalizeWords(profile!.lastName);
      emailCtrl.text = profile!.email;
      bioCtrl.text = profile!.bio;
      ibanCtrl.text = profile!.iban ?? "";

      bioCtrl.removeListener(_bioListener);
      bioCtrl.addListener(_bioListener);

      isLoading = false;
      notifyListeners();
    } catch (e) {
      error = friendlyError(e);
      isLoading = false;
      notifyListeners();
    }
  }

  void _bioListener() => notifyListeners();

  void startEdit() {
    if (profile == null) return;
    isEditing = true;
    notifyListeners();
  }

  void cancelEdit() {
    if (profile == null) return;

    isEditing = false;
    pickedImageFile = null;
    pickedPortfolioFiles.clear();

    firstNameCtrl.text = capitalizeWords(profile!.firstName);
    lastNameCtrl.text = capitalizeWords(profile!.lastName);

    emailCtrl.text = profile!.email;
    bioCtrl.text = profile!.bio;
    ibanCtrl.text = profile!.iban ?? "";

    notifyListeners();
  }

  // يحوّل أخطاء Firebase التقنية الخام (زي "quota-exceeded" أو
  // "permission-denied") إلى رسالة مفهومة للمستخدم، بدل ما نعرض
  // النص التقني الخام (اسم الـ bucket، روابط، أكواد داخلية...).
  static String friendlyError(Object e) {
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

  // يكبّر أول حرف من كل كلمة (زي "fatimah" -> "Fatimah")، نفس شكل
  // خيارات Job Title ("Software Developers").
  static String capitalizeWords(String value) {
    return value
        .split(' ')
        .map(
          (w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1),
        )
        .join(' ');
  }

  // ===== validators =====
  // أرقام إنجليزية/عربية/فارسية ممتدة، يستخدمها فحص الاسم أدناه.
  static final RegExp _digitsRegex = RegExp(r'[0-9٠-٩۰-۹]');

  String? validateFirstName(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "First name is required";
    if (_digitsRegex.hasMatch(value)) return "Letters only";
    if (value.length > 20) return "Max 20 characters";
    return null;
  }

  String? validateLastName(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Last name is required";
    if (_digitsRegex.hasMatch(value)) return "Letters only";
    if (value.length > 20) return "Max 20 characters";
    return null;
  }

  String? validateBio(String? v) {
    final value = (v ?? '');
    if (value.length > bioMax) return "Bio must be $bioMax characters or less";
    return null;
  }

  String? validateGmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Email is required";
    if (!gmailReg.hasMatch(value))
      return "Enter a valid email (name@gmail.com)";
    return null;
  }

  String? validateIban(String? v) {
    if (!isEditing) return null;
    final s = (v ?? '').trim().replaceAll(' ', '');
    if (s.isEmpty) return null;
    if (!s.toUpperCase().startsWith('SA')) return "IBAN must start with SA";
    if (s.length < 15) return "IBAN is too short";
    return null;
  }

  // ===== image/portfolio =====
  void setPickedImage(Uint8List bytes) {
    if (!isEditing) return;
    pickedImageFile = bytes;
    notifyListeners();
  }

  void addPortfolioFiles(List<Uint8List> files) {
    if (!isEditing) return;
    pickedPortfolioFiles.addAll(files);
    notifyListeners();
  }

  void removePortfolioAt(int i) {
    if (!isEditing) return;
    if (i < 0 || i >= pickedPortfolioFiles.length) return;
    pickedPortfolioFiles.removeAt(i);
    notifyListeners();
  }

  Future<void> deletePortfolioImage(String imageUrl) async {
    if (!isEditing || profile == null) return;
    error = null;

    if (await _accountAccessService.isCurrentUserBlocked()) {
      error = AccountAccessService.blockedActionMessage;
      notifyListeners();
      return;
    }

    try {
      final updatedUrls = List<String>.from(profile!.portfolioUrls)
        ..remove(imageUrl);

      await _storage.refFromURL(imageUrl).delete();

      await _db.collection('users').doc(profile!.uid).set({
        'portfolioUrls': updatedUrls,
      }, SetOptions(merge: true));

      profile = profile!.copyWith(portfolioUrls: updatedUrls);
      notifyListeners();
    } catch (e) {
      error = "Failed to delete portfolio image";
      notifyListeners();
    }
  }

  Future<void> deleteProfileImage() async {
    if (profile == null) return;
    error = null;

    if (await _accountAccessService.isCurrentUserBlocked()) {
      error = AccountAccessService.blockedActionMessage;
      notifyListeners();
      return;
    }

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final oldUrl = profile!.photoUrl;

      // حذف من Storage
      if (oldUrl != null && oldUrl.isNotEmpty) {
        await _storage.refFromURL(oldUrl).delete();
      }

      // حذف من Firestore
      await _db.collection('users').doc(user.uid).update({
        'profile': FieldValue.delete(),
      });

      // تحديث الحالة
      profile = profile!.copyWith(clearPhotoUrl: true);
      pickedImageFile = null;

      notifyListeners();
    } catch (e) {
      error = "Failed to delete profile image";
      notifyListeners();
    }
  }

  Future<void> setServiceFieldAndPersist(String v) async {
    if (!isEditing || profile == null) return;
    error = null;

    if (await _accountAccessService.isCurrentUserBlocked()) {
      error = AccountAccessService.blockedActionMessage;
      notifyListeners();
      return;
    }

    final old = profile!.serviceField;
    profile = profile!.copyWith(serviceField: v);
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) return;
      await _db.collection('users').doc(user.uid).update({'serviceField': v});
    } catch (_) {
      profile = profile!.copyWith(serviceField: old);
      error = "Failed to save service field";
      notifyListeners();
    }
  }

  Future<List<FreelancerReviewModel>> _fetchReviews(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('reviews')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    final enrichedReviews = await _withResolvedReviewerProfileUrls(snap.docs);

    return enrichedReviews
        .map((data) => FreelancerReviewModel.fromFirestore(data))
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

  double _avgRating(List<FreelancerReviewModel> list) {
    if (list.isEmpty) return 0;
    final sum = list.fold<int>(0, (p, r) => p + r.rating);
    return double.parse((sum / list.length).toStringAsFixed(1));
  }

  Future<void> setServiceTypeAndPersist(String v) async {
    if (!isEditing || profile == null) return;
    error = null;

    if (await _accountAccessService.isCurrentUserBlocked()) {
      error = AccountAccessService.blockedActionMessage;
      notifyListeners();
      return;
    }

    final old = profile!.serviceType;
    profile = profile!.copyWith(serviceType: v);
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) return;
      await _db.collection('users').doc(user.uid).update({'serviceType': v});
    } catch (_) {
      profile = profile!.copyWith(serviceType: old);
      error = "Failed to save service type";
      notifyListeners();
    }
  }

  Future<void> setWorkingModeAndPersist(String v) async {
    if (!isEditing || profile == null) return;
    error = null;

    if (await _accountAccessService.isCurrentUserBlocked()) {
      error = AccountAccessService.blockedActionMessage;
      notifyListeners();
      return;
    }

    final old = profile!.workingMode;
    profile = profile!.copyWith(workingMode: v);
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) return;
      await _db.collection('users').doc(user.uid).update({'workingMode': v});
    } catch (_) {
      profile = profile!.copyWith(workingMode: old);
      error = "Failed to save working mode";
      notifyListeners();
    }
  }

  // ✅ experiences (update same users doc)
  Future<void> addExperience(ExperienceModel exp) async {
    if (!isEditing || profile == null) return;
    error = null;

    if (await _accountAccessService.isCurrentUserBlocked()) {
      error = AccountAccessService.blockedActionMessage;
      notifyListeners();
      return;
    }

    final list = [...profile!.experiences, exp];
    profile = profile!.copyWith(experiences: list);
    notifyListeners();

    try {
      await _db.collection('users').doc(profile!.uid).set({
        'experiences': list.map((e) => e.toMap()).toList(),
      }, SetOptions(merge: true));
    } catch (e) {
      error = "Failed to save experience";
      notifyListeners();
    }
  }

  Future<void> editExperience(int index, ExperienceModel exp) async {
    if (!isEditing || profile == null) return;
    final list = [...profile!.experiences];
    if (index < 0 || index >= list.length) return;
    error = null;

    if (await _accountAccessService.isCurrentUserBlocked()) {
      error = AccountAccessService.blockedActionMessage;
      notifyListeners();
      return;
    }

    list[index] = exp;
    profile = profile!.copyWith(experiences: list);
    notifyListeners();

    try {
      await _db.collection('users').doc(profile!.uid).set({
        'experiences': list.map((e) => e.toMap()).toList(),
      }, SetOptions(merge: true));
    } catch (e) {
      error = "Failed to update experience";
      notifyListeners();
    }
  }

  Future<void> deleteExperience(int index) async {
    if (!isEditing || profile == null) return;
    final list = [...profile!.experiences];
    if (index < 0 || index >= list.length) return;
    error = null;

    if (await _accountAccessService.isCurrentUserBlocked()) {
      error = AccountAccessService.blockedActionMessage;
      notifyListeners();
      return;
    }

    list.removeAt(index);
    profile = profile!.copyWith(experiences: list);
    notifyListeners();

    try {
      await _db.collection('users').doc(profile!.uid).set({
        'experiences': list.map((e) => e.toMap()).toList(),
      }, SetOptions(merge: true));
    } catch (e) {
      error = "Failed to delete experience";
      notifyListeners();
    }
  }

  // ===== save =====
  Future<bool> save() async {
    if (profile == null) return false;

    isSaving = true;
    error = null;
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) throw "Not logged in";
      await _accountAccessService.ensureCurrentUserNotBlocked();
      final uid = user.uid;

      String? profileUrl = profile!.photoUrl;

      if (pickedImageFile != null) {
        final ref = _storage.ref().child('users/$uid/profile.jpg');
        // putData (بدل putFile) يشتغل على كل المنصات لأنه يرفع bytes
        // مباشرة بدون الاعتماد على نظام ملفات حقيقي (غير متوفر بالويب).
        await ref.putData(
          pickedImageFile!,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        profileUrl = await ref.getDownloadURL();
      }

      // upload portfolio
      final List<String> uploadedPortfolioUrls = [];
      for (final bytes in pickedPortfolioFiles) {
        final id = DateTime.now().microsecondsSinceEpoch.toString();
        final ref = _storage.ref().child('users/$uid/portfolio/$id.jpg');
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        uploadedPortfolioUrls.add(await ref.getDownloadURL());
      }

      final mergedPortfolioUrls = [
        ...profile!.portfolioUrls,
        ...uploadedPortfolioUrls,
      ];

      // ✅ name from 2 fields (Capital أول حرف من كل كلمة قبل الحفظ)
      final newFirst = capitalizeWords(firstNameCtrl.text.trim());
      final newLast = capitalizeWords(lastNameCtrl.text.trim());

      final newEmail = emailCtrl.text.trim();
      final newBioRaw = bioCtrl.text;
      final safeBio = newBioRaw.length > bioMax
          ? newBioRaw.substring(0, bioMax)
          : newBioRaw;

      final newIban = ibanCtrl.text.trim().replaceAll(' ', '');
      final ibanToSave = newIban.isEmpty ? "" : newIban;

      await _db.collection('users').doc(uid).set({
        'email': newEmail,
        'firstName': newFirst,
        'lastName': newLast,
        'nationalId': profile!.nationalId,
        'bio': safeBio,

        'portfolioUrls': mergedPortfolioUrls,
        if (profileUrl != null) 'profile': profileUrl,

        'rating': profile!.rating,

        'serviceField': profile!.serviceField,
        'serviceType': profile!.serviceType,
        'workingMode': profile!.workingMode,

        'iban': ibanToSave,
        'experiences': profile!.experiences.map((e) => e.toMap()).toList(),
      }, SetOptions(merge: true));

      if (newEmail != user.email) {
        try {
          await user.updateEmail(newEmail);
        } catch (_) {}
      }

      profile = profile!.copyWith(
        firstName: newFirst,
        lastName: newLast,
        email: newEmail,
        bio: safeBio,
        photoUrl: profileUrl,
        iban: ibanToSave.isEmpty ? null : ibanToSave,
        portfolioUrls: mergedPortfolioUrls,
      );

      isEditing = false;
      pickedImageFile = null;
      pickedPortfolioFiles.clear();

      isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = friendlyError(e);
      isSaving = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout(BuildContext context) async {
    // نلف clearToken بمحاولة منفصلة: هذي خطوة تنظيف ثانوية (إشعارات)،
    // ما نبيها توقف تسجيل الخروج الفعلي لو فشلت (زي لما يكون إذن
    // الإشعارات ممنوع بالمتصفح ويرمي خطأ).
    try {
      final messagingController = MessagingController();
      await messagingController.clearToken();
    } catch (_) {
      // تجاهل: فشل تنظيف الإشعارات مو سبب كافي نمنع المستخدم من
      // تسجيل الخروج.
    }
    await _auth.signOut();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  void goResetPassword(BuildContext context) {
    Navigator.pushNamed(context, '/forgotPassword');
  }

  Future<void> deleteAccount(BuildContext context) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _db.collection('users').doc(user.uid).delete();
      await user.delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted successfully')),
      );

      await Future.delayed(const Duration(seconds: 1));
      if (!context.mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/signup', (r) => false);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  bool get hasRequiredProfileData {
    final p = profile;
    if (p == null) return false;

    return (p.serviceField?.trim().isNotEmpty ?? false) &&
        (p.serviceType?.trim().isNotEmpty ?? false) &&
        (p.workingMode?.trim().isNotEmpty ?? false) &&
        p.portfolioUrls.isNotEmpty;
  }

  List<String> get missingRequiredFields {
    final p = profile;
    if (p == null) {
      return const [
        'Service Field',
        'Service Type',
        'Working Mode',
        'Portfolio',
      ];
    }

    final missing = <String>[];

    if (!(p.serviceField?.trim().isNotEmpty ?? false)) {
      missing.add('Service Field');
    }
    if (!(p.serviceType?.trim().isNotEmpty ?? false)) {
      missing.add('Service Type');
    }
    if (!(p.workingMode?.trim().isNotEmpty ?? false)) {
      missing.add('Working Mode');
    }
    if (p.portfolioUrls.isEmpty) {
      missing.add('Portfolio');
    }

    return missing;
  }

  @override
  void dispose() {
    bioCtrl.removeListener(_bioListener);

    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    emailCtrl.dispose();
    bioCtrl.dispose();
    ibanCtrl.dispose();

    super.dispose();
  }
}

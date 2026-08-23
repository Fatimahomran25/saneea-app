import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:saneea_app/views/client_home_screen.dart';
import '../controlles/account_access_service.dart';
import '../controlles/freelancer_profile_controller.dart';
import '../models/freelancer_profile_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'request_action_button.dart';
import 'favorite_heart_button.dart';
import 'report_flag_button.dart';
//تمت

class FreelancerProfileView extends StatefulWidget {
  final String? userId;
  final bool fromCategory;
  final bool fromChat;
  final bool readOnlyMode;
  const FreelancerProfileView({
    super.key,
    this.userId,
    this.fromCategory = false,
    this.fromChat = false, // 👈 الحل هنا
    this.readOnlyMode = false,
  });
  @override
  State<FreelancerProfileView> createState() => _FreelancerProfileViewState();
}

class _FreelancerProfileViewState extends State<FreelancerProfileView> {
  final c = FreelancerProfileController();
  final _formKey = GlobalKey<FormState>();

  static const Color kPurple = Color.fromRGBO(79, 55, 139, 1);
  static const Color kHeaderBg = Color(0xFFF2EAFB);
  static const Color kCardBg = Color(0xFFF4F1FA);
  static const Color kSoftBorder = Color(0x66B8A9D9);

  bool get _isOwnProfile => widget.userId == null;

  // The header stars and the "Top rated" lists both read users/{uid}.rating
  // directly, but the profile controller's `profile.rating` is a separate
  // average computed from the reviews subcollection — they can disagree
  // (e.g. a rating set without matching review docs). Favoriting used to
  // snapshot the controller's value, so the favorites list could show a
  // stale/different rating than what the profile itself just displayed.
  // Fetching the same stored field once here keeps both in sync.
  double? _viewedUserStoredRating;

  Future<void> _loadViewedUserStoredRating() async {
    final userId = widget.userId;
    if (userId == null || userId.trim().isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final data = doc.data();
      final rawRating = data?['rating'];
      final rating = rawRating is num
          ? rawRating.toDouble()
          : double.tryParse(rawRating?.toString() ?? '') ?? 0.0;

      if (!mounted) return;
      setState(() {
        _viewedUserStoredRating = rating;
      });
    } catch (_) {
      // Keep whatever the header stars already fall back to; favoriting
      // still works, just without the freshest rating snapshot.
    }
  }

  String _maskIban(String? iban) {
    final s = (iban ?? '').replaceAll(' ', '').toUpperCase();
    if (s.isEmpty) return "No bank account added";
    final head = s.length >= 4 ? s.substring(0, 4) : s;
    return '$head •••• •••• •••• •••• ••••';
  }

  String get _displayBio {
    final bio = c.isEditing
        ? c.bioCtrl.text.trim()
        : (c.profile?.bio.trim() ?? '');
    return bio.isEmpty ? 'No bio added yet.' : bio;
  }

  String get _displayEmail {
    final email = c.isEditing
        ? c.emailCtrl.text.trim()
        : (c.profile?.email.trim() ?? '');
    return email.isEmpty ? '-' : email;
  }

  String get _displayServiceField {
    final field = c.profile?.serviceField?.trim() ?? '';
    return field.isEmpty ? 'Freelancer' : field;
  }

  void _showBlockedActionSnackBarIfNeeded() {
    if (!mounted) return;
    if (c.error != AccountAccessService.blockedActionMessage) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(AccountAccessService.blockedActionMessage),
        ),
      );
  }

  @override
  void initState() {
    super.initState();
    c.init(userId: widget.userId);
    _loadViewedUserStoredRating();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    if (!c.isEditing || !_isOwnProfile) return;

    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (x == null) return;
      // نقرأ bytes مباشرة بدل تكوين dart:io File (غير مدعوم بالويب).
      final bytes = await x.readAsBytes();
      c.setPickedImage(bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Pick failed: $e')));
    }
  }

  Future<void> _pickPortfolioImages() async {
    if (!c.isEditing || !_isOwnProfile) return;
    final xs = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (xs.isEmpty) return;
    // bytes بدل File عشان تشتغل بكل المنصات (بما فيها الويب).
    final bytesList = await Future.wait(xs.map((e) => e.readAsBytes()));
    c.addPortfolioFiles(bytesList);
  }

  Future<ExperienceModel?> _experienceDialog({ExperienceModel? initial}) async {
    final fieldCtrl = TextEditingController(text: initial?.field ?? '');
    final orgCtrl = TextEditingController(text: initial?.org ?? '');
    final periodCtrl = TextEditingController(text: initial?.period ?? '');
    final formKey = GlobalKey<FormState>();

    final res = await showDialog<ExperienceModel>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(initial == null ? "Add Experience" : "Edit Experience"),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: fieldCtrl,
                  maxLength: 35,
                  maxLines: 1,
                  autovalidateMode:
                      AutovalidateMode.onUserInteraction, // 🔥 هذا المهم
                  decoration: const InputDecoration(
                    labelText: "Field",
                    hintText: "e.g. Graphic Design",
                    border: OutlineInputBorder(),
                    counterText: "",
                  ),
                  validator: (v) {
                    final value = v?.trim() ?? '';

                    if (value.isEmpty) return 'Field is required';

                    if (value.contains('http') || value.contains('www')) {
                      return 'Links are not allowed';
                    }

                    if (!RegExp(r'[a-zA-Z\u0600-\u06FF]').hasMatch(value)) {
                      return 'Please enter a valid field name';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: orgCtrl,
                  maxLength: 40,
                  maxLines: 1,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(
                    labelText: "Organization",
                    hintText: "e.g. King Saud University",
                    border: OutlineInputBorder(),
                    counterText: "",
                  ),
                  validator: (v) {
                    final value = v?.trim() ?? '';

                    if (value.isEmpty) return 'Organization is required';

                    if (value.contains('http') || value.contains('www')) {
                      return 'Links are not allowed';
                    }

                    if (!RegExp(r'[a-zA-Z\u0600-\u06FF]').hasMatch(value)) {
                      return 'Please enter a valid organization';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: periodCtrl,
                  maxLines: 1,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(
                    labelText: "Period",
                    hintText: "e.g. Sep 2021 - Jun 2023",
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final value = v?.trim() ?? '';

                    if (value.isEmpty) return 'Period is required';

                    if (value.contains('http') || value.contains('www')) {
                      return 'Links are not allowed';
                    }

                    if (!RegExp(r'[a-zA-Z0-9]').hasMatch(value)) {
                      return 'Please enter a valid period';
                    }

                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                ctx,
                ExperienceModel(
                  field: fieldCtrl.text.trim(),
                  org: orgCtrl.text.trim(),
                  period: periodCtrl.text.trim(),
                ),
              );
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );

    return res;
  }

  Widget _buildOwnProfile() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 10),

          _HeaderLikeAdmin_NoJobTitle(
            purple: kPurple,
            headerBg: kHeaderBg,
            isEditing: _isOwnProfile ? c.isEditing : false,
            profile: c.profile!,
            userId: widget.userId,
            pickedImageFile: _isOwnProfile ? c.pickedImageFile : null,
            onPickImage: _pickProfileImage,
            onDeleteImage: () async {
              if (!_isOwnProfile) return;

              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Delete image?'),
                  content: const Text(
                    'Are you sure you want to delete your profile image?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await c.deleteProfileImage();

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      c.error == null
                          ? 'Profile image deleted successfully'
                          : c.error!,
                    ),
                  ),
                );
              }
            },
            firstNameCtrl: c.firstNameCtrl,
            lastNameCtrl: c.lastNameCtrl,
            onEditTap: (_isOwnProfile && !c.isEditing) ? c.startEdit : null,
            firstNameValidator: c.validateFirstName,
            lastNameValidator: c.validateLastName,
            serviceFieldOptions:
                FreelancerProfileController.serviceFieldOptions,
            onServiceFieldChanged: (value) async {
              if (_isOwnProfile) {
                await c.setServiceFieldAndPersist(value);
                _showBlockedActionSnackBarIfNeeded();
              }
            },
          ),

          const SizedBox(height: 14),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
              decoration: BoxDecoration(
                color: kCardBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: kSoftBorder, width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!c.hasRequiredProfileData)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kSoftBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Complete the required fields to make your profile visible:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.red.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),

                          ...c.missingRequiredFields.map(
                            (e) => Text(
                              '• $e',
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 18),
                  _EditableField(
                    label: "Bio",
                    enabled: c.isEditing,
                    controller: c.bioCtrl,
                    maxLength: FreelancerProfileController.bioMax,
                    maxLines: 4,
                    validator: c.validateBio,
                    counterText:
                        "${c.bioLen.clamp(0, FreelancerProfileController.bioMax)}/${FreelancerProfileController.bioMax}",
                    hintText: "Write your bio...",
                    purple: kPurple,
                  ),
                  const SizedBox(height: 18),

                  _ReadOnlyBlock(
                    title: "National ID / Iqama",
                    value: c.profile!.nationalId,
                    purple: kPurple,
                  ),
                  const SizedBox(height: 18),

                  _EditableField(
                    label: "Email Address",
                    enabled: c.isEditing,
                    controller: c.emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    validator: c.validateGmail,
                    hintText: "name@gmail.com",
                    purple: kPurple,
                  ),
                  const SizedBox(height: 14),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "IBAN",
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: kPurple.withOpacity(0.25),
                                  width: 1.2,
                                ),
                              ),
                              child: Text(
                                c.isEditing
                                    ? c.ibanCtrl.text.isEmpty
                                          ? "No bank account added"
                                          : c.ibanCtrl.text
                                    : _maskIban(c.profile!.iban),
                                style: TextStyle(
                                  color: Colors.grey.shade800,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: "Bank account",
                        onPressed: () async {
                          final changed = await Navigator.pushNamed(
                            context,
                            '/bankAccount',
                          );
                          if (changed == true) {
                            await c.init(userId: widget.userId);
                          }
                        },
                        icon: Icon(Icons.account_balance, color: kPurple),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (c.profile!.serviceType ?? '').trim().isEmpty
                            ? "Service Type *"
                            : "Service Type",
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _SegmentBar(
                        options: FreelancerProfileController.serviceTypeOptions,
                        value: c.profile!.serviceType,
                        enabled: c.isEditing,
                        onChanged: (v) async {
                          await c.setServiceTypeAndPersist(v);
                          _showBlockedActionSnackBarIfNeeded();
                        },
                        purple: kPurple,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (c.profile!.workingMode ?? '').trim().isEmpty
                            ? "Working Mode *"
                            : "Working Mode",
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _SegmentBar(
                        options: FreelancerProfileController.workingModeOptions,
                        value: c.profile!.workingMode,
                        enabled: c.isEditing,
                        onChanged: (v) async {
                          await c.setWorkingModeAndPersist(v);
                          _showBlockedActionSnackBarIfNeeded();
                        },
                        purple: kPurple,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // نقلنا Portfolio لهنا (جنب Service Type/Working Mode)
                  // لأنه من الحقول المطلوبة لتفعيل ظهور البروفايل للعملاء،
                  // فيكون ترتيب الحقول منطقي: كل المطلوب إكماله يجي أول.
                  _InnerBox(
                    borderColor: kSoftBorder,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              c.profile!.portfolioUrls.isEmpty
                                  ? "Portfolio *"
                                  : "Portfolio",
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (_isOwnProfile && c.isEditing)
                              TextButton.icon(
                                onPressed: _pickPortfolioImages,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text("Add"),
                                style: TextButton.styleFrom(
                                  foregroundColor: kPurple,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Builder(
                          builder: (context) {
                            final net = c.profile!.portfolioUrls;
                            final local = c.pickedPortfolioFiles;
                            final total = net.length + local.length;

                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: total == 0 ? 4 : total,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                  ),
                              itemBuilder: (ctx, i) {
                                if (total == 0) {
                                  return _PlaceholderTile(purple: kPurple);
                                }
                                if (i < net.length) {
                                  final url = net[i];
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: Image.network(
                                            url,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        if (_isOwnProfile && c.isEditing)
                                          Positioned(
                                            top: 6,
                                            right: 6,
                                            child: GestureDetector(
                                              onTap: () async {
                                                await c.deletePortfolioImage(
                                                  url,
                                                );
                                                _showBlockedActionSnackBarIfNeeded();
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.withOpacity(
                                                    0.9,
                                                  ),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.close,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }

                                final localIndex = i - net.length;
                                final f = local[localIndex];

                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      // Image.memory بدل Image.file: يشتغل
                                      // على كل المنصات (Image.file غير
                                      // مدعوم إطلاقاً بفلاتر ويب).
                                      child: Image.memory(f, fit: BoxFit.cover),
                                    ),
                                    if (_isOwnProfile && c.isEditing)
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: GestureDetector(
                                          onTap: () =>
                                              c.removePortfolioAt(localIndex),
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withOpacity(
                                                0.9,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Text(
                        "Experience",
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (_isOwnProfile && c.isEditing)
                        TextButton.icon(
                          onPressed: () async {
                            final res = await _experienceDialog();
                            if (res == null) return;
                            await c.addExperience(res);
                            _showBlockedActionSnackBarIfNeeded();
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text("Add"),
                          style: TextButton.styleFrom(foregroundColor: kPurple),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  ...List.generate(c.profile!.experiences.length, (i) {
                    final e = c.profile!.experiences[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ExperienceCard(
                        purple: kPurple,
                        experience: e,
                        editable: _isOwnProfile ? c.isEditing : false,
                        onEdit: () async {
                          final res = await _experienceDialog(initial: e);
                          if (res == null) return;
                          await c.editExperience(i, res);
                          _showBlockedActionSnackBarIfNeeded();
                        },
                        onDelete: () async {
                          await c.deleteExperience(i);
                          _showBlockedActionSnackBarIfNeeded();
                        },
                      ),
                    );
                  }),

                  const SizedBox(height: 14),

                  // نفس نمط Reviews/Experience: التسمية فوق الصندوق
                  // برّا، مو بالداخل.
                  Text(
                    "Rating",
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _InnerBox(
                    borderColor: kSoftBorder,
                    // Wrap يخلي الصندوق بحجم محتواه بالضبط (مو ممدود
                    // لعرض الشاشة كامل)، ولو ضاقت الشاشة يلف النص
                    // تحت النجوم تلقائياً بدل ما يفيض (overflow).
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      children: [
                        _StarsReadOnly(value: c.profile!.rating, size: 22),
                        Text(
                          c.profile!.rating.toStringAsFixed(1),
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  Text(
                    "Reviews",
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),

                  _InnerBox(
                    borderColor: kSoftBorder,
                    child: c.reviews.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: Text(
                                "No reviews yet.",
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                        : Column(
                            children: c.reviews.map((r) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _ReviewFigmaTile(
                                  name: r.reviewerName,
                                  reviewerProfileUrl: r.reviewerProfileUrl,
                                  rating: r.rating,
                                  text: r.text,
                                ),
                              );
                            }).toList(),
                          ),
                  ),

                  const SizedBox(height: 18),

                  if (_isOwnProfile && c.isEditing) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _AdminOutlinedBtn(
                            text: "Cancel",
                            textColor: kPurple,
                            borderColor: kPurple.withOpacity(0.25),
                            onPressed: c.isSaving ? null : c.cancelEdit,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: kPurple,
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: c.isSaving
                                ? null
                                : () async {
                                    FocusScope.of(context).unfocus();

                                    final saved = await c.save();
                                    if (!mounted) return;

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          saved
                                              ? "Saved successfully ✅"
                                              : c.error ==
                                                    AccountAccessService
                                                        .blockedActionMessage
                                              ? c.error!
                                              : "Save failed: ${c.error ?? ''}",
                                        ),
                                      ),
                                    );
                                  },
                            child: c.isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text("Done"),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_isOwnProfile) ...[
                    _AdminOutlinedBtn(
                      text: "Reset password",
                      textColor: const Color(0xFF2F7BFF),
                      borderColor: kPurple.withOpacity(0.25),
                      onPressed: () => c.goResetPassword(context),
                    ),
                    const SizedBox(height: 12),
                    _AdminOutlinedBtn(
                      text: "Delete account",
                      textColor: Colors.red,
                      borderColor: kPurple.withOpacity(0.25),
                      onPressed: () => c.deleteAccount(context),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildOtherProfile() {
    final profile = c.profile!;

    ImageProvider? avatar;
    if (profile.photoUrl != null && profile.photoUrl!.isNotEmpty) {
      avatar = NetworkImage(profile.photoUrl!);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: CircleAvatar(
              radius: 46,
              backgroundColor: const Color(0xFFF6F2FB),
              backgroundImage: avatar,
              child: avatar == null
                  ? const Icon(Icons.person, size: 42, color: kPurple)
                  : null,
            ),
          ),
          const SizedBox(height: 14),

          Center(
            child: Text(
              profile.fullName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),

          Center(
            child: Text(
              _displayServiceField,
              style: const TextStyle(
                fontSize: 15,
                color: kPurple,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (widget.readOnlyMode && profile.isBlocked) ...[
            const SizedBox(height: 12),
            const Center(child: _BlockedStatusBadge()),
          ],
          const SizedBox(height: 10),

          const SizedBox(height: 10),

          Center(
            child: _StarsReadOnly(
              value: _viewedUserStoredRating ?? 0,
              size: 22,
            ),
          ),
          const SizedBox(height: 24),
          const SizedBox(height: 10),
          if (!widget.fromChat && !widget.readOnlyMode)
            Align(
              alignment: Alignment.centerRight,
              child: SendRequestButton(
                freelancerId: widget.userId!,
                freelancerName: profile.fullName,
              ),
            ),

          const SizedBox(height: 24),

          _PublicInfoTile(title: 'Bio', value: _displayBio),

          _PublicInfoTile(title: 'Email Address', value: _displayEmail),

          if ((profile.serviceType ?? '').trim().isNotEmpty)
            _PublicInfoTile(title: 'Service Type', value: profile.serviceType!),

          if ((profile.workingMode ?? '').trim().isNotEmpty)
            _PublicInfoTile(title: 'Working Mode', value: profile.workingMode!),

          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F2FB),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Experience',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                if (profile.experiences.isEmpty)
                  const Text(
                    'No experience added yet.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  )
                else
                  ...profile.experiences.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: kPurple.withOpacity(0.18),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFFF2EAFB),
                              child: Icon(Icons.school, color: kPurple),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.field,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    e.org,
                                    style: TextStyle(
                                      color: kPurple,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    e.period,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F2FB),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reviews',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                if (c.reviews.isEmpty)
                  const Text(
                    'No reviews yet.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  )
                else
                  ...c.reviews.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ReviewFigmaTile(
                        name: r.reviewerName,
                        reviewerProfileUrl: r.reviewerProfileUrl,
                        rating: r.rating,
                        text: r.text,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Text(
            "Portfolio",
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),

          Builder(
            builder: (context) {
              final items = profile.portfolioUrls;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.isEmpty ? 4 : items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (ctx, i) {
                  if (items.isEmpty) {
                    return _PlaceholderTile(purple: kPurple);
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(items[i], fit: BoxFit.cover),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  static void _emptyAction() {}

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final fixedMq = mq.copyWith(textScaler: const TextScaler.linear(1.0));

    return MediaQuery(
      data: fixedMq,
      child: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          final currentUserId = FirebaseAuth.instance.currentUser?.uid;
          final viewedFreelancerId =
              c.profile?.uid ?? widget.userId?.trim() ?? '';
          final showProfileReportAction =
              viewedFreelancerId.isNotEmpty &&
              currentUserId != viewedFreelancerId;

          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              title: const Text('Profile'),
              centerTitle: true,
              backgroundColor: Colors.white,
              foregroundColor: _FreelancerProfileViewState.kPurple,
              elevation: 0,
              actions: [
                if (!widget.readOnlyMode && !_isOwnProfile && c.profile != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: FavoriteHeartButton(
                      favoriteUserId: c.profile!.uid,
                      favoriteUserName: c.profile!.fullName,
                      favoriteUserRole: 'freelancer',
                      favoriteUserProfileImage: c.profile!.photoUrl ?? '',
                      serviceField: c.profile!.serviceField ?? '',
                      rating: _viewedUserStoredRating ?? c.profile!.rating,
                      iconSize: 24,
                      padding: const EdgeInsets.all(10),
                      backgroundColor: const Color(0xFFF6F2FB),
                    ),
                  ),
                if (!widget.readOnlyMode && showProfileReportAction)
                  ReportFlagButton(
                    onPressed: () {
                      final profile = c.profile;
                      if (profile == null) return;
                      showReportIssueDialog(
                        context: context,
                        source: 'profile',
                        reportedUserId: profile.uid,
                        reportedUserName: profile.fullName,
                        reportedUserRole: 'freelancer',
                      );
                    },
                  ),
                if (_isOwnProfile)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: IconButton(
                      tooltip: "Log out",
                      onPressed: () => c.logout(context),
                      icon: const Icon(
                        Icons.logout,
                        color: Colors.red,
                        size: 28,
                      ),
                    ),
                  ),

                if (!_isOwnProfile && widget.fromCategory)
                  IconButton(
                    icon: const Icon(
                      Icons.home_outlined,
                      color: Color(0xFF5A3E9E),
                      size: 26,
                    ),
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ClientHomeScreen(),
                        ),
                        (route) => false,
                      );
                    },
                  ),
              ],
            ),
            body: c.isLoading
                ? const Center(child: CircularProgressIndicator())
                : (c.profile == null)
                ? Center(child: Text(c.error ?? "Failed to load profile"))
                : (_isOwnProfile ? _buildOwnProfile() : _buildOtherProfile()),
          );
        },
      ),
    );
  }
}

class _BlockedStatusBadge extends StatelessWidget {
  const _BlockedStatusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.red.withOpacity(0.22)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_rounded, color: Colors.red, size: 18),
          SizedBox(width: 8),
          Text(
            'Blocked',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicInfoTile extends StatelessWidget {
  const _PublicInfoTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F2FB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 6),
          Text(
            value.trim().isEmpty ? '-' : value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagInfoBlock extends StatelessWidget {
  const _TagInfoBlock({
    required this.title,
    required this.value,
    required this.purple,
  });

  final String title;
  final String value;
  final Color purple;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: purple.withOpacity(0.25), width: 1.2),
          ),
          child: Text(
            value,
            style: TextStyle(color: purple, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ProfileInfoBlock extends StatelessWidget {
  const _ProfileInfoBlock({
    required this.title,
    required this.value,
    required this.purple,
  });

  final String title;
  final String value;
  final Color purple;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: purple.withOpacity(0.25), width: 1.2),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderLikeAdmin_NoJobTitle extends StatelessWidget {
  const _HeaderLikeAdmin_NoJobTitle({
    required this.purple,
    required this.headerBg,
    required this.isEditing,
    required this.profile,
    required this.pickedImageFile,
    required this.onPickImage,
    required this.onDeleteImage,
    required this.firstNameCtrl,
    required this.lastNameCtrl,
    required this.onEditTap,
    required this.firstNameValidator,
    required this.lastNameValidator,
    required this.serviceFieldOptions,
    required this.onServiceFieldChanged,
    required this.userId,
  });

  final Color purple;
  final Color headerBg;
  final bool isEditing;
  final FreelancerProfileModel profile;
  final Uint8List? pickedImageFile;
  final VoidCallback onPickImage;
  final Future<void> Function() onDeleteImage;
  final TextEditingController firstNameCtrl;
  final TextEditingController lastNameCtrl;
  final VoidCallback? onEditTap;
  final String? Function(String?) firstNameValidator;
  final String? Function(String?) lastNameValidator;
  final List<String> serviceFieldOptions;
  final void Function(String) onServiceFieldChanged;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatar;
    if (pickedImageFile != null) {
      // MemoryImage بدل FileImage: يشتغل بكل المنصات بما فيها الويب.
      avatar = MemoryImage(pickedImageFile!);
    } else if (profile.photoUrl != null && profile.photoUrl!.isNotEmpty) {
      avatar = NetworkImage(profile.photoUrl!);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        // بدل رقم ثابت (كان يفتح overflow جديد كل ما زاد المحتوى: رسالة
        // خطأ، اسم أطول...)، نخليه يكبر تلقائياً حسب المحتوى الفعلي مع
        // إبقاء حد أدنى للشكل بوضع العرض العادي.
        constraints: const BoxConstraints(minHeight: 235),

        decoration: BoxDecoration(
          color: headerBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: purple.withOpacity(0.22), width: 1.2),
        ),
        child: Stack(
          children: [
            if (!isEditing && onEditTap != null)
              Positioned(
                top: 10,
                right: 10,
                // دائرة بنفسجية فاتحة بظل حول أيقونة القلم بدل ما تكون
                // طايرة بدون خلفية.
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: purple.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: purple.withOpacity(0.35),
                      width: 1.2,
                    ),
                  ),
                  child: IconButton(
                    onPressed: onEditTap,
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.edit, color: purple, size: 20),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 110,
                      height: 110,
                      child: Stack(
                        children: [
                          Center(
                            child: CircleAvatar(
                              radius: 44,
                              backgroundColor: Colors.white,
                              child: CircleAvatar(
                                radius: 41,
                                backgroundColor: headerBg,
                                backgroundImage: avatar,
                                child: avatar == null
                                    ? Icon(
                                        Icons.person,
                                        color: purple,
                                        size: 34,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          if (isEditing)
                            Positioned(
                              right: 10,
                              bottom: 8,
                              child: GestureDetector(
                                onTap: onPickImage,
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: purple,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          if (isEditing && avatar != null)
                            Positioned(
                              left: 10,
                              bottom: 8,
                              child: GestureDetector(
                                onTap: onDeleteImage,
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (!isEditing)
                      Text(
                        profile.fullName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: purple,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    else
                      // نفس قوانين حقول التطبيق (زي حقل National ID / Iqama
                      // بشاشة التسجيل): تسمية فوق الحقل + صندوق مستقل بلون
                      // فاتح وحواف مستديرة خفيفة، بدل صندوق واحد ملتصق.
                      SizedBox(
                        width: 280,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _EditableField(
                                label: "First name",
                                enabled: true,
                                controller: firstNameCtrl,
                                validator: firstNameValidator,
                                purple: purple,
                                maxLength: 20,
                                counterText: "",
                                errorMaxLines: 2,
                                textCapitalization: TextCapitalization.words,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(20),
                                  TextInputFormatter.withFunction((
                                    oldValue,
                                    newValue,
                                  ) {
                                    final capitalized =
                                        FreelancerProfileController.capitalizeWords(
                                          newValue.text,
                                        );
                                    if (capitalized == newValue.text) {
                                      return newValue;
                                    }
                                    return newValue.copyWith(
                                      text: capitalized,
                                      selection: newValue.selection,
                                    );
                                  }),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _EditableField(
                                label: "Last name",
                                enabled: true,
                                controller: lastNameCtrl,
                                validator: lastNameValidator,
                                purple: purple,
                                maxLength: 20,
                                counterText: "",
                                errorMaxLines: 2,
                                textCapitalization: TextCapitalization.words,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(20),
                                  TextInputFormatter.withFunction((
                                    oldValue,
                                    newValue,
                                  ) {
                                    final capitalized =
                                        FreelancerProfileController.capitalizeWords(
                                          newValue.text,
                                        );
                                    if (capitalized == newValue.text) {
                                      return newValue;
                                    }
                                    return newValue.copyWith(
                                      text: capitalized,
                                      selection: newValue.selection,
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 4),

                    if (!isEditing)
                      Text(
                        (profile.serviceField == null ||
                                profile.serviceField!.isEmpty)
                            ? "Add your job title *"
                            : profile.serviceField!,
                        style: TextStyle(
                          color:
                              (profile.serviceField == null ||
                                  profile.serviceField!.isEmpty)
                              ? Colors.grey.shade500
                              : Colors.grey.shade700,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      // نفس عرض صف الاسم بالضبط (280) بدل صندوق أضيق
                      // معلّق بالنص، عشان الشكل يطلع مستطيل منظم
                      // مو متدرّج (مثلث).
                      SizedBox(
                        width: 280,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // تسمية واضحة فوق الحقل (بدل الاعتماد على
                            // النص الشفاف بالداخل فقط)، بنفس قوانين
                            // باقي حقول الشاشة.
                            Text(
                              "Job Title",
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              value:
                                  (profile.serviceField == null ||
                                      profile.serviceField!.isEmpty)
                                  ? null
                                  : profile.serviceField,
                              items: serviceFieldOptions.map((field) {
                                return DropdownMenuItem<String>(
                                  value: field,
                                  // بدون فونت صريح: يرث نفس الخط الافتراضي
                                  // اللي تستخدمه حقول Bio/Email عشان تكون
                                  // كل الحقول موحّدة تماماً.
                                  child: Text(
                                    field,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  onServiceFieldChanged(value);
                                }
                              },
                              decoration: InputDecoration(
                                hintText: "Select",
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                // نفس نصف قطر وحد باقي الحقول (14 /
                                // 0.25 شفافية) عشان تكون كل الحقول
                                // موحّدة الشكل.
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: purple.withOpacity(0.25),
                                    width: 1.2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: purple.withOpacity(0.25),
                                    width: 1.2,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: purple,
                                    width: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InnerBox extends StatelessWidget {
  const _InnerBox({required this.child, required this.borderColor});
  final Widget child;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: child,
    );
  }
}

class _AdminOutlinedBtn extends StatelessWidget {
  const _AdminOutlinedBtn({
    required this.text,
    required this.textColor,
    required this.borderColor,
    required this.onPressed,
  });

  final String text;
  final Color textColor;
  final Color borderColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: BorderSide(color: borderColor, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _EditableField extends StatelessWidget {
  const _EditableField({
    required this.label,
    required this.enabled,
    required this.controller,
    required this.purple,
    this.maxLength,
    this.maxLines = 1,
    this.validator,
    this.keyboardType,
    this.counterText,
    this.hintText,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.errorMaxLines,
  });

  final String label;
  final bool enabled;
  final TextEditingController controller;
  final Color purple;
  final int? maxLength;
  final int maxLines;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final String? counterText;
  final String? hintText;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final int? errorMaxLines;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: purple.withOpacity(0.25), width: 1.2),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          enabled: enabled,
          validator: validator,
          keyboardType: keyboardType,
          maxLength: maxLength,
          maxLines: maxLines,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
            hintText: hintText,
            counterText: counterText ?? "",
            errorMaxLines: errorMaxLines,
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: purple, width: 1.4),
            ),
            disabledBorder: border.copyWith(
              borderSide: BorderSide(
                color: purple.withOpacity(0.18),
                width: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyBlock extends StatelessWidget {
  const _ReadOnlyBlock({
    required this.title,
    required this.value,
    required this.purple,
  });

  final String title;
  final String value;
  final Color purple;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: purple,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ExperienceCard extends StatelessWidget {
  const _ExperienceCard({
    required this.purple,
    required this.experience,
    required this.editable,
    required this.onEdit,
    required this.onDelete,
  });

  final Color purple;
  final ExperienceModel experience;
  final bool editable;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: purple.withOpacity(0.22), width: 1.2),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFF2EAFB),
            child: Icon(Icons.school, color: purple),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  experience.field,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  experience.org,
                  style: TextStyle(color: purple, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  experience.period,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          if (editable) ...[
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit, size: 18),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlaceholderTile extends StatelessWidget {
  const _PlaceholderTile({required this.purple});
  final Color purple;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E6E6)),
      ),
      child: Icon(Icons.image, color: purple),
    );
  }
}

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({
    required this.options,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.purple,
  });

  final List<String> options;
  final String? value;
  final bool enabled;
  final void Function(String v) onChanged;
  final Color purple;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: purple.withOpacity(0.25), width: 1.2),
      ),
      child: Row(
        children: options.map((o) {
          final selected = o == value;
          return Expanded(
            child: InkWell(
              onTap: enabled ? () => onChanged(o) : null,
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? purple.withOpacity(0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    o,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? purple : Colors.grey.shade700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StarsReadOnly extends StatelessWidget {
  const _StarsReadOnly({required this.value, this.size = 20});

  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(0, 5); // حماية

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        if (i < safeValue.floor()) {
          return Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(Icons.star, size: size, color: Colors.amber),
          );
        } else if (i == safeValue.floor() && safeValue % 1 != 0) {
          return Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(Icons.star_half, size: size, color: Colors.amber),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(
              Icons.star_border,
              size: size,
              color: Colors.grey.shade400,
            ),
          );
        }
      }),
    );
  }
}

class _ReviewFigmaTile extends StatelessWidget {
  const _ReviewFigmaTile({
    required this.name,
    required this.reviewerProfileUrl,
    required this.rating,
    required this.text,
  });

  final String name;
  final String reviewerProfileUrl;
  final int rating;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F3FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0x66B8A9D9).withOpacity(0.7),
          width: 1.1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0x66B8A9D9).withOpacity(0.6),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: reviewerProfileUrl.trim().isNotEmpty
                  ? Image.network(
                      reviewerProfileUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return const Icon(Icons.person_outline, size: 20);
                      },
                    )
                  : const Icon(Icons.person_outline, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    _StarsReadOnly(value: rating.toDouble(), size: 16),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

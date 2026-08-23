import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../controlles/account_access_service.dart';
import '../controlles/client_profile_controller.dart';
import 'favorite_heart_button.dart';
import 'report_flag_button.dart';

class ClientProfile extends StatelessWidget {
  final String? userId;
  final bool readOnlyMode;

  const ClientProfile({
    super.key,
    this.userId,
    this.readOnlyMode = false,
  });

  static const Color kPurple = Color(0xFF4F378B);
  static const Color kHeaderBg = Color(0xFFF2EAFB);
  static const Color kCardBg = Color(0xFFF4F1FA);
  static const Color kBorder = Color(0x66B8A9D9);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final fixedMq = mq.copyWith(textScaler: const TextScaler.linear(1.0));

    return MediaQuery(
      data: fixedMq,
      child: ChangeNotifierProvider(
        create: (_) => ClientProfileController()..init(userId: userId),
        child: _ClientProfileBody(readOnlyMode: readOnlyMode),
      ),
    );
  }
}

class _ClientProfileBody extends StatefulWidget {
  const _ClientProfileBody({
    required this.readOnlyMode,
  });

  final bool readOnlyMode;

  @override
  State<_ClientProfileBody> createState() => _ClientProfileBodyState();
}

class _ClientProfileBodyState extends State<_ClientProfileBody> {
  final _formKey = GlobalKey<FormState>();

  Future<void> _pickProfileImage(ClientProfileController c) async {
    if (!c.isEditing || !c.isOwnProfile) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    final XFile? x = await ImagePicker().pickImage(
      source: source,
      imageQuality: 90,
    );
    if (x == null) return;
    c.setPickedImage(await x.readAsBytes());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ClientProfileController>();

    if (c.isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (c.error != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: Text(c.error!)),
      );
    }

    final p = c.profile!;
    final purple = ClientProfile.kPurple;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final showProfileReportAction = currentUserId != p.uid;

    ImageProvider? avatar;
    if (c.pickedImageFile != null) {
      avatar = MemoryImage(c.pickedImageFile!);
    } else if (p.photoUrl != null && p.photoUrl!.isNotEmpty) {
      avatar = NetworkImage(p.photoUrl!);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: ClientProfile.kPurple,
        elevation: 0,
        actions: [
          if (!widget.readOnlyMode && !c.isOwnProfile && c.profile != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FavoriteHeartButton(
                favoriteUserId: c.profile!.uid,
                favoriteUserName: c.profile!.name,
                favoriteUserRole: 'client',
                favoriteUserProfileImage: c.profile!.photoUrl ?? '',
                serviceField: 'Client',
                rating: c.profile!.rating,
                iconSize: 24,
                padding: const EdgeInsets.all(10),
                backgroundColor: const Color(0xFFF6F2FB),
              ),
            ),
          if (!widget.readOnlyMode && showProfileReportAction)
            ReportFlagButton(
              onPressed: () {
                showReportIssueDialog(
                  context: context,
                  source: 'profile',
                  reportedUserId: p.uid,
                  reportedUserName: p.name,
                  reportedUserRole: 'client',
                );
              },
            ),
          if (c.isOwnProfile) ...[
            IconButton(
              tooltip: "Log out",
              onPressed: () => c.logout(context),
              icon: const Icon(Icons.logout, color: Colors.red),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
      body: c.isOwnProfile
          ? _buildOwnProfile(context, c, p, purple, avatar)
          : _buildOtherProfile(context, c, p, avatar),
    );
  }

  Widget _buildOwnProfile(
    BuildContext context,
    ClientProfileController c,
    dynamic p,
    Color purple,
    ImageProvider? avatar,
  ) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 10),

          _HeaderOwnClient(
            purple: purple,
            isEditing: c.isEditing,
            nameCtrl: c.nameCtrl,
            nameValidator: c.validateName,
            roleText: "Client",
            onPickImage: () => _pickProfileImage(c),
            avatar: avatar,
            onEditTap: c.startEdit,
          ),

          const SizedBox(height: 14),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
              decoration: BoxDecoration(
                color: ClientProfile.kCardBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: ClientProfile.kBorder, width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EditableField(
                    label: "Bio",
                    enabled: c.isEditing,
                    controller: c.bioCtrl,
                    maxLength: ClientProfileController.bioMax,
                    maxLines: 4,
                    validator: c.validateBio,
                    counterText:
                        "${c.bioLen.clamp(0, ClientProfileController.bioMax)}/${ClientProfileController.bioMax}",
                    hintText: "Write your bio...",
                    purple: purple,
                  ),

                  const SizedBox(height: 16),

                  _ReadOnlyBlock(
                    title: "National ID / Iqama",
                    value: p.nationalId,
                    purple: purple,
                  ),

                  const SizedBox(height: 14),

                  _EditableField(
                    label: "Email Address",
                    enabled: c.isEditing,
                    controller: c.emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    validator: c.validateGmail,
                    hintText: "name@gmail.com",
                    purple: purple,
                  ),

                  const SizedBox(height: 14),

                  _InnerBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Rating",
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _StarsReadOnly(value: p.rating, size: 22),
                            const SizedBox(width: 10),
                            Text(
                              p.rating.toStringAsFixed(1),
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
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
                            children: c.reviews
                                .map(
                                  (r) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _ReviewFigmaTile(
                                      name: r.reviewerName,
                                      reviewerProfileUrl: r.reviewerProfileUrl,
                                      rating: r.rating,
                                      text: r.text,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ),

                  const SizedBox(height: 16),

                  if (c.isEditing) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: c.isSaving ? null : c.cancelEdit,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text("Cancel"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: purple,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: c.isSaving
                                ? null
                                : () async {
                                    final ok =
                                        _formKey.currentState?.validate() ??
                                        false;
                                    if (!ok) return;

                                    final saved = await c.save();
                                    if (!mounted) return;

                                    if (saved) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text("Saved successfully ✅"),
                                        ),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            c.error ==
                                                    AccountAccessService
                                                        .blockedActionMessage
                                                ? c.error!
                                                : "Save failed: ${c.error ?? ''}",
                                          ),
                                        ),
                                      );
                                    }
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
                  ] else ...[
                    _ActionBtn(
                      text: "Reset password",
                      color: const Color(0xFF2F7BFF),
                      onPressed: () =>
                          Navigator.pushNamed(context, '/forgotPassword'),
                    ),
                    const SizedBox(height: 12),
                    _ActionBtn(
                      text: "Delete account",
                      color: Colors.red,
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

  Widget _buildOtherProfile(
    BuildContext context,
    ClientProfileController c,
    dynamic p,
    ImageProvider? avatar,
  ) {
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
                  ? const Icon(
                      Icons.person,
                      size: 42,
                      color: ClientProfile.kPurple,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 14),

          Center(
            child: Text(
              p.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),

          const Center(
            child: Text(
              "Client",
              style: TextStyle(
                fontSize: 15,
                color: ClientProfile.kPurple,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (widget.readOnlyMode && p.isBlocked) ...[
            const SizedBox(height: 12),
            const Center(child: _BlockedStatusBadge()),
          ],
          const SizedBox(height: 8),

          Center(child: _StarsReadOnly(value: p.rating, size: 20)),
          const SizedBox(height: 24),

          _PublicInfoTile(
            title: 'Bio',
            value: p.bio.trim().isEmpty ? 'No bio added yet.' : p.bio,
          ),
          _PublicInfoTile(
            title: 'Email Address',
            value: p.email.trim().isEmpty ? '-' : p.email,
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
        ],
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

class _HeaderOwnClient extends StatelessWidget {
  const _HeaderOwnClient({
    required this.purple,
    required this.isEditing,
    required this.nameCtrl,
    required this.nameValidator,
    required this.roleText,
    required this.onPickImage,
    required this.avatar,
    required this.onEditTap,
  });

  final Color purple;
  final bool isEditing;
  final TextEditingController nameCtrl;
  final String? Function(String?) nameValidator;
  final String roleText;
  final VoidCallback onPickImage;
  final ImageProvider? avatar;
  final VoidCallback onEditTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 210,
        decoration: BoxDecoration(
          color: ClientProfile.kHeaderBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: purple.withOpacity(0.22), width: 1.2),
        ),
        child: Stack(
          children: [
            if (!isEditing)
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  tooltip: "Edit",
                  onPressed: onEditTap,
                  icon: Icon(Icons.edit, color: purple, size: 20),
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
                                backgroundColor: ClientProfile.kHeaderBg,
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
                                onTap: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('Delete image?'),
                                      content: const Text(
                                        'Are you sure you want to delete your profile image?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    await context
                                        .read<ClientProfileController>()
                                        .deleteProfileImage();
                                    final controller =
                                        context.read<ClientProfileController>();

                                    if (!context.mounted) return;

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          controller.error ==
                                                  AccountAccessService
                                                      .blockedActionMessage
                                              ? controller.error!
                                              : 'Profile image deleted successfully',
                                        ),
                                      ),
                                    );
                                  }
                                },
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
                    SizedBox(
                      width: 250,
                      child: TextFormField(
                        controller: nameCtrl,
                        enabled: isEditing,
                        validator: nameValidator,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: purple,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 2),
                        ),
                      ),
                    ),
                    Text(
                      roleText,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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

class _InnerBox extends StatelessWidget {
  const _InnerBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ClientProfile.kBorder, width: 1.2),
      ),
      child: child,
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

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: purple.withOpacity(0.35), width: 1.2),
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
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
            hintText: hintText,
            counterText: counterText ?? "",
            filled: true,
            fillColor: Colors.white.withOpacity(0.75),
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
            errorBorder: border.copyWith(
              borderSide: const BorderSide(color: Colors.red, width: 1.3),
            ),
            focusedErrorBorder: border.copyWith(
              borderSide: const BorderSide(color: Colors.red, width: 1.4),
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
          color: ClientProfile.kBorder.withOpacity(0.7),
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
              border: Border.all(color: ClientProfile.kBorder.withOpacity(0.6)),
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

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.text,
    required this.color,
    required this.onPressed,
  });

  final String text;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: Colors.grey.shade300),
        padding: const EdgeInsets.symmetric(vertical: 14),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: Colors.white.withOpacity(0.6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: color,
        ),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        if (i < value.floor()) {
          return Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(Icons.star, size: size, color: Colors.amber),
          );
        } else if (i == value.floor() && value % 1 != 0) {
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

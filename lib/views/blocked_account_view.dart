import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../controlles/app_notification_service.dart';
import '../controlles/login_controller.dart';

class BlockedAccountView extends StatefulWidget {
  const BlockedAccountView({super.key});

  static const String restrictionMessage =
      'Your account has been restricted by the admin. You cannot use app features until the restriction is lifted.';

  @override
  State<BlockedAccountView> createState() => _BlockedAccountViewState();
}

class _BlockedAccountViewState extends State<BlockedAccountView> {
  static const Color _primary = Color(0xFF5A3E9E);
  static const Color _surface = Color(0xFFF6F2FB);
  static const Color _background = Color(0xFFFCFAFF);
  static const Color _border = Color(0xFFE6DDF6);
  static const int _appealMaxLength = 300;

  final LoginController _loginController = LoginController();
  final AppNotificationService _notificationService = AppNotificationService();
  final GlobalKey<FormState> _appealFormKey = GlobalKey<FormState>();
  final TextEditingController _appealMessageController =
      TextEditingController();

  bool _isLoggingOut = false;
  bool _isAppealFormOpen = false;
  bool _isSubmittingAppeal = false;

  @override
  void dispose() {
    _appealMessageController.dispose();
    _loginController.dispose();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    if (_isLoggingOut) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      await _loginController.logout();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/intro', (route) => false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to log out. Please try again.')),
      );
      debugPrint('Blocked account logout error: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  int? _intOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String _resolveUserName(Map<String, dynamic> userData, User? user) {
    final explicitName = (userData['name'] ?? '').toString().trim();
    if (explicitName.isNotEmpty) return explicitName;

    final firstName = (userData['firstName'] ?? '').toString().trim();
    final lastName = (userData['lastName'] ?? '').toString().trim();
    final composedName = '$firstName $lastName'.trim();
    if (composedName.isNotEmpty) return composedName;

    final displayName = (user?.displayName ?? '').trim();
    if (displayName.isNotEmpty) return displayName;

    return 'User';
  }

  String _resolveUserEmail(Map<String, dynamic> userData, User? user) {
    final email = (userData['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;
    return (user?.email ?? '').trim();
  }

  String _appealStatus(Map<String, dynamic> data) {
    return (data['status'] ?? '').toString().trim().toLowerCase();
  }

  int _appealSortValue(Map<String, dynamic> data) {
    final updatedAt = data['updatedAt'];
    if (updatedAt is Timestamp) {
      return updatedAt.millisecondsSinceEpoch;
    }

    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) {
      return createdAt.millisecondsSinceEpoch;
    }

    return 0;
  }

  Future<void> _submitReviewRequest(Map<String, dynamic> userData) async {
    if (_isSubmittingAppeal) return;

    final formState = _appealFormKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to submit review request.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmittingAppeal = true;
    });

    try {
      final existingAppeals = await FirebaseFirestore.instance
          .collection('blocked_user_appeals')
          .where('userId', isEqualTo: uid)
          .get();

      final hasPendingAppeal = existingAppeals.docs.any((doc) {
        final status = (doc.data()['status'] ?? '').toString().trim();
        return status.toLowerCase() == 'pending';
      });

      if (hasPendingAppeal) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You already have a pending review request.'),
          ),
        );
        return;
      }

      final blockedReason = (userData['blockedReason'] ?? '')
          .toString()
          .trim();
      final warningCount = _intOrNull(userData['warningCount']);
      final userName = _resolveUserName(userData, user);
      final userEmail = _resolveUserEmail(userData, user);

      final appealRef = await FirebaseFirestore.instance
          .collection('blocked_user_appeals')
          .add({
        'userId': uid,
        'userName': userName,
        'userEmail': userEmail,
        'message': _appealMessageController.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isReadByAdmin': false,
        if (blockedReason.isNotEmpty) 'blockedReason': blockedReason,
        if (warningCount != null) 'warningCount': warningCount,
      });

      try {
        await _notificationService.createBlockedUserAppealNotification(
          appealId: appealRef.id,
          userId: uid,
          userName: userName,
        );
      } catch (error) {
        debugPrint('Blocked account appeal notification error: $error');
      }

      _appealMessageController.clear();
      if (!mounted) return;
      setState(() {
        _isAppealFormOpen = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your review request has been submitted.'),
        ),
      );
    } catch (error) {
      debugPrint('Blocked account appeal submission error: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to submit review request. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingAppeal = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final userStream = uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

    return WillPopScope(
      onWillPop: () async => false,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userStream,
        builder: (context, snapshot) {
          final userData = snapshot.data?.data() ?? <String, dynamic>{};
          final isBlocked = userData['isBlocked'] == true;
          final blockedReason = (userData['blockedReason'] ?? '')
              .toString()
              .trim();
          final appealsStream = uid == null
              ? null
              : FirebaseFirestore.instance
                    .collection('blocked_user_appeals')
                    .where('userId', isEqualTo: uid)
                    .snapshots();

          // The app-wide _BlockedUserGate (in main.dart) is the single
          // authority that navigates away from this screen once it sees
          // isBlocked flip to false — it owns the transition so this
          // widget doesn't race it with a second redirect. If our own
          // (slightly less fresh) stream still thinks we're unblocked,
          // just hold on a loading frame until the gate takes over.
          if (uid != null && snapshot.hasData && !isBlocked) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return Scaffold(
            backgroundColor: _background,
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: _border),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 24,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: _border),
                            ),
                            child: const Text(
                              'Access Limited',
                              style: TextStyle(
                                color: _primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(
                              Icons.block_rounded,
                              color: _primary,
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Account Restricted',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF1F1B2D),
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            BlockedAccountView.restrictionMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                          if (blockedReason.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _surface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: _border),
                              ),
                              child: Text(
                                'Reason: $blockedReason',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Request Review',
                                  style: TextStyle(
                                    color: _primary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>
                                >(
                                  stream: appealsStream,
                                  builder: (context, appealsSnapshot) {
                                    final appealDocs =
                                        appealsSnapshot.data?.docs.toList() ??
                                        <QueryDocumentSnapshot<
                                          Map<String, dynamic>
                                        >>[];

                                    appealDocs.sort(
                                      (a, b) => _appealSortValue(
                                        b.data(),
                                      ).compareTo(_appealSortValue(a.data())),
                                    );

                                    final hasPendingAppeal = appealDocs.any(
                                      (doc) =>
                                          _appealStatus(doc.data()) ==
                                          'pending',
                                    );
                                    final latestAppealStatus = appealDocs.isEmpty
                                        ? ''
                                        : _appealStatus(appealDocs.first.data());
                                    final showRejectedState =
                                        !hasPendingAppeal &&
                                        latestAppealStatus == 'rejected';
                                    final canSubmitAppeal = !hasPendingAppeal;

                                    if (appealsSnapshot.connectionState ==
                                            ConnectionState.waiting &&
                                        !appealsSnapshot.hasData) {
                                      return const Padding(
                                        padding: EdgeInsets.only(top: 14),
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      );
                                    }

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'If you believe this restriction should be reviewed, send a message to the admin team.',
                                          style: TextStyle(
                                            color: Colors.black87,
                                            fontSize: 13.5,
                                            height: 1.45,
                                          ),
                                        ),
                                        if (hasPendingAppeal) ...[
                                          const SizedBox(height: 14),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: _border,
                                              ),
                                            ),
                                            child: const Text(
                                              'Your review request is pending admin review.',
                                              style: TextStyle(
                                                color: _primary,
                                                fontWeight: FontWeight.w700,
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (showRejectedState) ...[
                                          const SizedBox(height: 14),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: const Color(0xFFD8A3A3),
                                              ),
                                            ),
                                            child: const Text(
                                              'Your previous review request was rejected.',
                                              style: TextStyle(
                                                color: Color(0xFFB04A4A),
                                                fontWeight: FontWeight.w700,
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (canSubmitAppeal) ...[
                                          const SizedBox(height: 14),
                                          if (!_isAppealFormOpen)
                                            SizedBox(
                                              width: double.infinity,
                                              child: OutlinedButton(
                                                onPressed: () {
                                                  setState(() {
                                                    _isAppealFormOpen = true;
                                                  });
                                                },
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: _primary,
                                                  side: const BorderSide(
                                                    color: _primary,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 14,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'Request Review',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            )
                                          else
                                            Form(
                                              key: _appealFormKey,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  TextFormField(
                                                    controller:
                                                        _appealMessageController,
                                                    maxLength:
                                                        _appealMaxLength,
                                                    maxLines: 5,
                                                    autovalidateMode:
                                                        AutovalidateMode
                                                            .onUserInteraction,
                                                    decoration: InputDecoration(
                                                      labelText:
                                                          'Explain why your account should be reviewed',
                                                      alignLabelWithHint: true,
                                                      filled: true,
                                                      fillColor: Colors.white,
                                                      border:
                                                          OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  16,
                                                                ),
                                                          ),
                                                      enabledBorder:
                                                          OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  16,
                                                                ),
                                                            borderSide:
                                                                BorderSide(
                                                                  color:
                                                                      _border,
                                                                ),
                                                          ),
                                                      focusedBorder:
                                                          OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  16,
                                                                ),
                                                            borderSide:
                                                                const BorderSide(
                                                                  color:
                                                                      _primary,
                                                                ),
                                                          ),
                                                    ),
                                                    validator: (value) {
                                                      final message =
                                                          (value ?? '').trim();
                                                      if (message.isEmpty) {
                                                        return 'This field is required.';
                                                      }
                                                      if (message.length >
                                                          _appealMaxLength) {
                                                        return 'Message must be 300 characters or less.';
                                                      }
                                                      return null;
                                                    },
                                                  ),
                                                  const SizedBox(height: 14),
                                                  SizedBox(
                                                    width: double.infinity,
                                                    child: ElevatedButton(
                                                      onPressed:
                                                          _isSubmittingAppeal
                                                          ? null
                                                          : () =>
                                                                _submitReviewRequest(
                                                                  userData,
                                                                ),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            _primary,
                                                        disabledBackgroundColor:
                                                            _primary
                                                                .withOpacity(
                                                                  0.45,
                                                                ),
                                                        foregroundColor:
                                                            Colors.white,
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 14,
                                                            ),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                16,
                                                              ),
                                                        ),
                                                      ),
                                                      child: _isSubmittingAppeal
                                                          ? const SizedBox(
                                                              width: 18,
                                                              height: 18,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                            )
                                                          : const Text(
                                                              'Submit Review Request',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                            ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isLoggingOut ? null : _handleLogout,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primary,
                                disabledBackgroundColor: _primary.withOpacity(
                                  0.45,
                                ),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: _isLoggingOut
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.logout_rounded),
                              label: Text(
                                _isLoggingOut ? 'Logging out...' : 'Log out',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

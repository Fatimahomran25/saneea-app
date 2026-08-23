import 'dart:io';
//تمت
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../controlles/account_access_service.dart';
import '../controlles/recommendation_controller.dart';
import '../models/recommendation_model.dart';

class HighlightOverflowController extends TextEditingController {
  HighlightOverflowController({
    required this.limit,
    required this.normalStyle,
    required this.overflowStyle,
  });

  final int limit;
  final TextStyle normalStyle;
  final TextStyle overflowStyle;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = value.text;

    if (text.length <= limit) {
      return TextSpan(text: text, style: normalStyle);
    }

    final before = text.substring(0, limit);
    final after = text.substring(limit);

    return TextSpan(
      children: [
        TextSpan(text: before, style: normalStyle),
        TextSpan(text: after, style: overflowStyle),
      ],
    );
  }
}

class AnnouncementView extends StatefulWidget {
  final String? freelancerId;
  final String? freelancerName;
  final String? requestId;
  final String? announcementId;
  final String? initialDescription;
  final double? initialBudget;
  final String? initialDeadline;

  const AnnouncementView({
    super.key,
    this.freelancerId,
    this.freelancerName,
    this.requestId,
    this.announcementId,
    this.initialDescription,
    this.initialBudget,
    this.initialDeadline,
  });

  @override
  State<AnnouncementView> createState() => _AnnouncementViewState();
}

class _AnnouncementViewState extends State<AnnouncementView> {
  static const int _characterLimit = 150;
  static const Color _primaryColor = Color(0xFF5A3E9E);

  late HighlightOverflowController _descriptionController;
  final TextEditingController _budgetController = TextEditingController();
  final TextEditingController _deadlineController = TextEditingController();

  bool _hasLink = false;
  bool _isTooLong = false;

  final RegExp _linkRegex = RegExp(
    r'(\bhttps?:\/\/\S+|\bwww\S+|\b\S+\.[a-zA-Z]{1,}\b)',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();

    _descriptionController = HighlightOverflowController(
      limit: _characterLimit,
      normalStyle: const TextStyle(fontSize: 18, color: Colors.black),
      overflowStyle: const TextStyle(
        fontSize: 18,
        color: Colors.black,
        backgroundColor: Color(0x33FF0000),
      ),
    );

    _descriptionController.addListener(_recalculateState);
    _budgetController.addListener(_refreshPageState);
    _deadlineController.addListener(_refreshPageState);

    if (widget.announcementId != null || widget.requestId != null) {
      _descriptionController.text = widget.initialDescription ?? '';
      _budgetController.text = widget.initialBudget?.toString() ?? '';
      _deadlineController.text = widget.initialDeadline ?? '';
    }
  }

  @override
  void dispose() {
    _descriptionController.removeListener(_recalculateState);
    _descriptionController.dispose();
    _budgetController.dispose();
    _deadlineController.dispose();
    super.dispose();
  }

  void _refreshPageState() {
    if (mounted) {
      setState(() {});
    }
  }

  void _recalculateState() {
    final text = _descriptionController.text;
    final hasLinkNow = _linkRegex.hasMatch(text);
    final isTooLongNow = text.length > _characterLimit;

    if (hasLinkNow != _hasLink || isTooLongNow != _isTooLong) {
      setState(() {
        _hasLink = hasLinkNow;
        _isTooLong = isTooLongNow;
      });
    } else {
      setState(() {});
    }
  }

  double _clamp(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  bool _containsLetter(String text) {
    return RegExp(r'[a-zA-Z\u0600-\u06FF]').hasMatch(text);
  }

  Future<bool> _hasInternetConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.every((r) => r == ConnectivityResult.none)) {
      return false;
    }

    // على الويب: connectivity_plus أصلاً يعتمد على navigator.onLine
    // بالمتصفح، وهذا مؤشر دقيق بما فيه الكفاية بيئة الويب. أي طلب
    // خارجي إضافي (زي gstatic) يرفضه المتصفح بسبب CORS حتى لو
    // السيرفر رد فعلياً، فيرجع "لا يوجد اتصال" بشكل خاطئ.
    if (kIsWeb) return true;

    // على الموبايل/الديسكتوب: نتأكد بطلب حقيقي (بدل InternetAddress.lookup
    // اللي أصلاً غير مدعوم بالويب) لأن الاتصال بشبكة مو دايماً يعني
    // نت شغّال فعلياً (زي شبكات بوابة captive).
    try {
      final response = await http
          .get(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _pickDeadline() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null) {
      _deadlineController.text =
          '${pickedDate.day}/${pickedDate.month}/${pickedDate.year}';
      setState(() {});
    }
  }

  bool get _canSubmit {
    return _descriptionController.text.trim().isNotEmpty &&
        !_hasLink &&
        !_isTooLong &&
        _budgetController.text.trim().isNotEmpty &&
        _deadlineController.text.trim().isNotEmpty;
  }

  Future<void> _submit() async {
    if (widget.announcementId != null) {
      await _updateAnnouncement();
    } else if (widget.requestId != null) {
      await _updateDirectRequest();
    } else if (widget.freelancerId != null) {
      await _sendDirectRequest();
    } else {
      await _publishAnnouncement();
    }
  }

  Future<void> _updateAnnouncement() async {
    final description = _descriptionController.text.trim();
    final budgetText = _budgetController.text.trim();
    final budget = double.tryParse(budgetText);
    final deadline = _deadlineController.text.trim();
    final announcementId = widget.announcementId;

    if (description.isEmpty || _hasLink || _isTooLong) return;

    if (!_containsLetter(description)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service request must contain at least one letter'),
        ),
      );
      return;
    }

    if (description.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe your request in more details'),
        ),
      );
      return;
    }

    if (budgetText.isEmpty || budget == null || budget <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid budget')));
      return;
    }

    if (deadline.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a deadline')));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be logged in')));
      return;
    }

    if (announcementId == null || announcementId.isEmpty) return;

    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Please try again.'),
        ),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('announcements')
          .doc(announcementId)
          .update({
            'description': description,
            'budget': budget,
            'deadline': deadline,
            'updatedAt': FieldValue.serverTimestamp(),
            'isEdited': true,
          });

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Updated successfully ✏️')),
      );
    } on FirebaseException catch (e) {
      final message =
          (e.code == 'unavailable' || e.code == 'network-request-failed')
          ? 'No internet connection. Please try again.'
          : 'Failed to update: ${e.message ?? e.code}';

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on SocketException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Please try again.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    }
  }

  Future<void> _updateDirectRequest() async {
    try {
      final controller = RecommendationController();

      await controller.updateRequest(
        requestId: widget.requestId!,
        description: _descriptionController.text.trim(),
        budget: double.parse(_budgetController.text.trim()),
        deadline: _deadlineController.text.trim(),
      );

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Request updated ✏️')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    }
  }

  Future<void> _publishAnnouncement() async {
    final description = _descriptionController.text.trim();
    final budgetText = _budgetController.text.trim();
    final budget = double.tryParse(budgetText);
    final deadline = _deadlineController.text.trim();

    if (description.isEmpty || _hasLink || _isTooLong) return;

    if (!_containsLetter(description)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service request must contain at least one letter'),
        ),
      );
      return;
    }

    if (description.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe your request in more details'),
        ),
      );
      return;
    }

    if (budgetText.isEmpty || budget == null || budget <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid budget')));
      return;
    }

    if (deadline.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a deadline')));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be logged in')));
      return;
    }

    if (await AccountAccessService().isCurrentUserBlocked()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AccountAccessService.blockedActionMessage),
        ),
      );
      return;
    }

    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Please try again.'),
        ),
      );
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userDoc.data() ?? {};
      final clientName =
          "${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}".trim();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('announcements')
          .add({
            'description': description,
            'budget': budget,
            'deadline': deadline,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
            'clientId': user.uid,
            'clientName': clientName,
          });

      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseException catch (e) {
      final message =
          (e.code == 'unavailable' || e.code == 'network-request-failed')
          ? 'No internet connection. Please try again.'
          : 'Failed to publish: ${e.message ?? e.code}';

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on SocketException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Please try again.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final errorMessage = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            errorMessage == AccountAccessService.blockedActionMessage
                ? errorMessage
                : 'Failed to publish: $e',
          ),
        ),
      );
    }
  }

  Future<void> _sendDirectRequest() async {
    final description = _descriptionController.text.trim();
    final budgetText = _budgetController.text.trim();
    final budget = double.tryParse(budgetText);
    final deadline = _deadlineController.text.trim();

    if (description.isEmpty || _hasLink || _isTooLong) return;

    if (!_containsLetter(description)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service request must contain at least one letter'),
        ),
      );
      return;
    }

    if (description.length < 10) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please add more details')));
      return;
    }

    if (budgetText.isEmpty || budget == null || budget <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid budget')));
      return;
    }

    if (deadline.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a deadline')));
      return;
    }

    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Please try again.'),
        ),
      );
      return;
    }

    try {
      final controller = RecommendationController();

      await controller.sendRequest(
        freelancer: FreelancerRecommendation(
          id: widget.freelancerId!,
          name: widget.freelancerName ?? '',
          serviceField: '',
          serviceType: '',
          workingMode: '',
          rating: 0,
          portfolioUrls: [],
          profileImage: null,
        ),
        description: description,
        budget: budget,
        deadline: deadline,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request sent successfully ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      final errorMessage = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessage == AccountAccessService.blockedActionMessage
                ? errorMessage
                : e.toString().contains('already sent')
                ? 'You can only send one request. Cancel it first or wait for response.'
                : 'Failed to send request.',
          ),
        ),
      );
    }
  }

  InputDecoration _fieldDecoration({
    required String labelText,
    required String hintText,
    Widget? suffixIcon,
    String? prefixText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixText: prefixText,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryColor, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          widget.announcementId != null || widget.requestId != null
              ? 'Edit Service Request'
              : widget.freelancerId != null
              ? 'Send Service Request'
              : 'Create Service Request',
        ),
        backgroundColor: Colors.white,
        foregroundColor: _primaryColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final contentMaxWidth = width > 600 ? 520.0 : width;
            final horizontalPadding = _clamp(width * 0.06, 16, 28);
            final topPadding = _clamp(width * 0.04, 12, 20);
            final hintFontSize = _clamp(width * 0.05, 18, 22);

            final normalStyle = TextStyle(
              fontSize: hintFontSize,
              fontWeight: FontWeight.w400,
              color: Colors.black,
            );

            final text = _descriptionController.text;
            final remaining = _characterLimit - text.length;

            return SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMaxWidth),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      topPadding,
                      horizontalPadding,
                      0,
                    ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_hasLink)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Links are not allowed',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      if (_isTooLong)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Too long (max 150 characters)',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),

                      TextField(
                        controller: _budgetController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _fieldDecoration(
                          labelText: 'Budget',
                          hintText: 'Enter your budget',
                          prefixText: 'SAR ',
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: _deadlineController,
                        readOnly: true,
                        onTap: _pickDeadline,
                        decoration: _fieldDecoration(
                          labelText: 'Deadline',
                          hintText: 'Select deadline date',
                          suffixIcon: const Icon(Icons.calendar_today_outlined),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: TextField(
                          controller: _descriptionController,
                          autofocus: true,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          minLines: 8,
                          maxLines: null,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(12),
                            hintText: 'What are you looking for?',
                            hintStyle: TextStyle(
                              fontSize: hintFontSize,
                              fontWeight: FontWeight.w400,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          style: normalStyle,
                          cursorColor: Colors.black,
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${text.length}/$_characterLimit',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: remaining >= 0
                                  ? Colors.grey.shade600
                                  : Colors.red,
                            ),
                          ),
                        ),
                      ),

                      ElevatedButton(
                        onPressed: _canSubmit ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          widget.announcementId != null ||
                                  widget.requestId != null
                              ? 'Save Changes'
                              : widget.freelancerId != null
                              ? 'Send'
                              : 'Publish',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              ),
            );
          },
        ),
      ),
    );
  }
}

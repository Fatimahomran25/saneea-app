import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../config/api_config.dart';
import '../controlles/account_access_service.dart';
import '../controlles/chat_controller.dart';
import '../models/message_model.dart';
import 'freelancer_client_profile_view.dart';
import 'freelancer_profile.dart';
import 'report_flag_button.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:moyasar/moyasar.dart';
import '../widgets/web_moyasar_card_form.dart';

class _DeliveryLocalFile {
  const _DeliveryLocalFile({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

class _DeliveryRemoteFile {
  const _DeliveryRemoteFile({
    required this.name,
    this.url = '',
    this.storagePath = '',
    this.previewUrl = '',
    this.watermarkedPreviewUrl = '',
  });

  final String name;
  final String url;
  final String storagePath;
  final String previewUrl;
  final String watermarkedPreviewUrl;

  String get bestPreviewUrl =>
      watermarkedPreviewUrl.isNotEmpty ? watermarkedPreviewUrl : previewUrl;

  bool get hasAccessibleUrl =>
      bestPreviewUrl.isNotEmpty ||
      storagePath.trim().isNotEmpty ||
      url.trim().isNotEmpty;
}

class _DeliverySubmissionDraft {
  const _DeliverySubmissionDraft({
    required this.keepImageUrls,
    required this.keepFileItems,
    required this.newImageFiles,
    required this.newDocumentFiles,
    required this.linkUrls,
    required this.notes,
  });

  final List<String> keepImageUrls;
  final List<_DeliveryRemoteFile> keepFileItems;
  final List<PickedImageData> newImageFiles;
  final List<_DeliveryLocalFile> newDocumentFiles;
  final List<String> linkUrls;
  final String notes;

  bool get hasContent =>
      keepImageUrls.isNotEmpty ||
      keepFileItems.isNotEmpty ||
      newImageFiles.isNotEmpty ||
      newDocumentFiles.isNotEmpty ||
      linkUrls.isNotEmpty;
}

String _friendlyErrorMessage(Object error) {
  final rawError = error.toString().replaceFirst('Exception: ', '').trim();
  final normalizedError = rawError.toLowerCase();
  final statusCode = error is int ? error : int.tryParse(rawError);
  final firebaseCode = error is FirebaseException
      ? error.code.trim().toLowerCase()
      : '';

  if (rawError == AccountAccessService.blockedActionMessage) {
    return rawError;
  }

  if (error is TimeoutException ||
      normalizedError.contains('timeout') ||
      normalizedError.contains('timed out')) {
    return 'Check your internet or server';
  }

  if (error is SocketException ||
      error is http.ClientException ||
      firebaseCode == 'unavailable' ||
      normalizedError.contains('socketexception') ||
      normalizedError.contains('clientexception') ||
      normalizedError.contains('failed host lookup') ||
      normalizedError.contains('connection reset') ||
      normalizedError.contains('connection refused') ||
      normalizedError.contains('network request failed') ||
      normalizedError.contains('network')) {
    return 'Check your internet or server';
  }

  if (statusCode == 401 ||
      statusCode == 403 ||
      firebaseCode == 'permission-denied' ||
      normalizedError.contains('permission') ||
      normalizedError.contains('not allowed') ||
      normalizedError.contains('access denied')) {
    return 'You are not allowed to do this';
  }

  if (statusCode == 404 ||
      firebaseCode == 'not-found' ||
      normalizedError.contains('not found') ||
      normalizedError.contains('missing') ||
      normalizedError.contains('requestid is missing')) {
    return 'Data not found';
  }

  return 'Something went wrong';
}

Future<void> _showErrorDialogForContext(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

class ChatView extends StatefulWidget {
  final String chatId;
  final String otherUserName;

  final String otherUserId;
  final String otherUserRole;
  final bool adminReadOnlyMode;
  final String adminClientId;
  final String adminClientName;
  final String adminFreelancerId;
  final String adminFreelancerName;

  const ChatView({
    super.key,
    required this.chatId,
    required this.otherUserName,
    required this.otherUserId,
    required this.otherUserRole,
    this.adminReadOnlyMode = false,
    this.adminClientId = '',
    this.adminClientName = '',
    this.adminFreelancerId = '',
    this.adminFreelancerName = '',
  });

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  static const Color primary = Color(0xFF5A3E9E);
  static const String contractDisplayTitle = 'Freelancer Service Agreement';
  static const String moyasarPublishableKey =
      String.fromEnvironment('MOYASAR_PUBLISHABLE_KEY');
  static const Duration _contractRequestTimeout = Duration(seconds: 25);
  static const Duration _generateContractRequestTimeout = Duration(seconds: 90);
  static const Duration _panelSwitchDuration = Duration(milliseconds: 220);
  static const double _pinnedPanelHeaderMinHeight = 92;
  static const double _chatPanelRadius = 16;
  static const double _chatPanelInnerRadius = 14;
  static const Color _chatPanelShellBackground = Color(0xFFF6F3FB);
  static const Color _chatPanelBackground = Colors.white;
  static const Color _chatPanelSurface = Color(0xFFF8F4FD);
  static const Color _chatPanelBorder = Color(0xFFE7DFF4);
  static const int _adminReviewDetailsMaxLength = 150;
  List<PickedImageData> _selectedImages = [];
  String? _otherUserPhotoUrl;
  final ImagePicker _picker = ImagePicker();
  final AccountAccessService _accountAccessService = AccountAccessService();
  final ChatController _controller = ChatController();
  final TextEditingController _messageController = TextEditingController();
  Map<String, dynamic>? _contractData;
  Map<String, dynamic>? _currentUserReviewData;
  bool _isGeneratingContract = false;
  bool _isSavingContract = false;
  bool _isApprovingContract = false;
  bool _isTerminatingContract = false;
  bool _isEditingContract = false;
  bool _isLoadingReviewData = false;
  bool _isSavingReview = false;
  bool _isApprovedContractPanelExpanded = false;
  bool _isFreelancerProgressPanelExpanded = false;
  bool _isWorkProgressSheetOpen = false;
  bool _isSwitchingPanels = false;
  bool _isLoadingContractData = true;
  bool _isContractPreviewExpanded = true;
  bool _isAddingClause = false;
  int _selectedApprovedPanelTab = 0;
  Timer? _terminationCountdownTimer;
  String? _contractError;
  String _editableServiceDescription = '';
  String _editableAmount = '';
  String _editableDeadline = '';
  String? _requestId;
  List<Map<String, String>> _pendingCustomClauses = [];
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _requestContractSubscription;
  final TextEditingController _clauseTitleController = TextEditingController();
  final TextEditingController _clauseContentController =
      TextEditingController();
  final ScrollController _contractPreviewScrollController = ScrollController();
  final ScrollController _contractMessageCardScrollController =
      ScrollController();
  final ScrollController _approvedContractPanelScrollController =
      ScrollController();
  final ScrollController _freelancerProgressPanelScrollController =
      ScrollController();
  @override
  void initState() {
    super.initState();
    _isApprovedContractPanelExpanded = false;
    _isFreelancerProgressPanelExpanded = false;

    if (!widget.adminReadOnlyMode) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _controller.markMessagesAsRead(widget.chatId);
      });
      _loadOtherUserPhoto();
      _listenToRequestContract();
      _terminationCountdownTimer = Timer.periodic(const Duration(minutes: 1), (
        _,
      ) {
        if (!mounted) return;
        setState(() {});
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(jump: true);
    });
  }

  Future<void> _showErrorDialog(String message) {
    return _showErrorDialogForContext(context, message);
  }

  Future<bool> _isCurrentUserBlocked() {
    return _accountAccessService.isCurrentUserBlocked();
  }

  Future<bool> _showBlockedActionAndStopIfNeeded() async {
    if (!await _isCurrentUserBlocked()) return false;
    if (!mounted) return true;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(AccountAccessService.blockedActionMessage),
        ),
      );
    return true;
  }

  bool _isSuccessfulStatusCode(int statusCode) =>
      statusCode >= 200 && statusCode < 300;

  void _logCaughtError(String label, Object error, StackTrace stackTrace) {
    debugPrint('$label: $error');
    debugPrintStack(label: '$label stack', stackTrace: stackTrace);
  }

  Future<void> _showLoggedError(
    String label,
    Object error,
    StackTrace stackTrace, {
    bool updateContractError = false,
  }) async {
    _logCaughtError(label, error, stackTrace);
    if (!mounted) return;

    final message = _friendlyErrorMessage(error);
    if (updateContractError) {
      setState(() {
        _contractError = message;
      });
    }
    await _showErrorDialog(message);
  }

  Future<void> _runNonBlockingSecondaryAction(
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on FirebaseException catch (error, stackTrace) {
      _logCaughtError('$label secondary error', error, stackTrace);
    } on TimeoutException catch (error, stackTrace) {
      _logCaughtError('$label secondary error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      _logCaughtError('$label secondary error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      _logCaughtError('$label secondary error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      _logCaughtError('$label secondary error', error, stackTrace);
    } catch (error, stackTrace) {
      _logCaughtError('$label secondary error', error, stackTrace);
    }
  }

  Map<String, dynamic> _decodeResponseBodyAsMap(
    http.Response response, {
    required String actionLabel,
  }) {
    final trimmedBody = response.body.trim();
    if (trimmedBody.isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(trimmedBody);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);

    throw FormatException('$actionLabel returned an unexpected response body');
  }

  Map<String, dynamic> _tryDecodeResponseBodyAsMap(
    http.Response response, {
    required String actionLabel,
  }) {
    try {
      return _decodeResponseBodyAsMap(response, actionLabel: actionLabel);
    } on FormatException catch (error, stackTrace) {
      _logCaughtError('$actionLabel response decode error', error, stackTrace);
    } catch (error, stackTrace) {
      _logCaughtError('$actionLabel response decode error', error, stackTrace);
    }

    return <String, dynamic>{};
  }

  bool _didApiResponseSucceed(
    http.Response response,
    Map<String, dynamic> responseData,
  ) {
    if (!_isSuccessfulStatusCode(response.statusCode)) {
      return false;
    }

    final success = responseData['success'];
    if (success is bool) {
      return success;
    }

    return true;
  }

  String _responseErrorMessage(
    Map<String, dynamic> responseData,
    int statusCode,
  ) {
    final apiMessage = _firstFilled([
      responseData['error'],
      responseData['message'],
      responseData['detail'],
    ]);
    return apiMessage.isNotEmpty
        ? apiMessage
        : _friendlyErrorMessage(statusCode);
  }

  Future<void> _showApiFailure({
    required String actionLabel,
    required http.Response response,
    required Map<String, dynamic> responseData,
    bool updateContractError = false,
  }) async {
    debugPrint(
      '$actionLabel failed: '
      'status=${response.statusCode}, body=${response.body}',
    );

    if (!mounted) return;

    final message = _responseErrorMessage(responseData, response.statusCode);
    if (updateContractError) {
      setState(() {
        _contractError = message;
      });
    }

    await _showErrorDialog(message);
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Uri _backendUri(String endpointPath, {Map<String, String>? queryParameters}) {
    final normalizedBaseUrl = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    final uri = Uri.parse('$normalizedBaseUrl/$endpointPath');

    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }

    return uri.replace(queryParameters: queryParameters);
  }

  Future<http.Response> _postContractApi({
    required String endpointPath,
    required Map<String, dynamic> body,
    required String logLabel,
    Duration? timeout,
  }) async {
    await _accountAccessService.ensureCurrentUserNotBlocked();

    final uri = _backendUri(endpointPath);
    final encodedBody = jsonEncode(body);

    debugPrint('$logLabel request URL: $uri');
    debugPrint('$logLabel request body: $encodedBody');

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: encodedBody,
          )
          .timeout(timeout ?? _contractRequestTimeout);

      debugPrint('$logLabel status code: ${response.statusCode}');
      debugPrint('$logLabel response body: ${response.body}');
      return response;
    } on TimeoutException catch (error) {
      debugPrint('$logLabel request URL: $uri');
      debugPrint('$logLabel exception: $error');
      rethrow;
    } catch (error) {
      debugPrint('$logLabel request URL: $uri');
      debugPrint('$logLabel exception: $error');
      rethrow;
    }
  }

  Future<void> _openDeliveryPreviewImage(
    String imageUrl, {
    String? overlayLabel,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Image.network(imageUrl, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
              if ((overlayLabel ?? '').trim().isNotEmpty)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      overlayLabel!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _extractRequestId(Map<String, dynamic>? chatData) {
    final requestId = (chatData?['requestId'] ?? '').toString().trim();

    if (requestId.isEmpty) {
      throw Exception('requestId is missing in chat document');
    }

    return requestId;
  }

  Future<void> _listenToRequestContract() async {
    if (mounted) {
      setState(() {
        _isLoadingContractData = true;
      });
    }

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .get();

      final chatData = chatDoc.data();
      final requestId = _extractRequestId(chatData);
      _requestId = requestId;
      final announcementId = (chatData?['announcementId'] ?? '')
          .toString()
          .trim();
      final proposalId = (chatData?['proposalId'] ?? '').toString().trim();
      debugPrint('requestId: $requestId');
      debugPrint('CHAT ID: ${widget.chatId}');
      debugPrint('REQUEST ID: $requestId');
      debugPrint('ANNOUNCEMENT ID: $announcementId');
      debugPrint('PROPOSAL ID: $proposalId');

      await _requestContractSubscription?.cancel();

      final isAnnouncementProposalChat = proposalId.isNotEmpty;
      final sourceCollection = isAnnouncementProposalChat
          ? 'announcement_requests'
          : 'requests';
      final sourceDocumentId = isAnnouncementProposalChat
          ? proposalId
          : requestId;

      debugPrint('Listening source: $sourceCollection');
      debugPrint('Listening document id: $sourceDocumentId');

      final sourceStream = FirebaseFirestore.instance
          .collection(sourceCollection)
          .doc(sourceDocumentId)
          .snapshots();

      _requestContractSubscription = sourceStream.listen((sourceDoc) {
        final rawContractData = sourceDoc.data()?['contractData'];
        final hasContractData =
            rawContractData is Map && rawContractData.isNotEmpty;

        debugPrint('Listening source: $sourceCollection');
        debugPrint('Listening document id: $sourceDocumentId');
        debugPrint('contractData exists: $hasContractData');

        if (!mounted) return;

        setState(() {
          _isLoadingContractData = false;
          _contractData = hasContractData
              ? Map<String, dynamic>.from(rawContractData as Map)
              : null;
        });

        unawaited(_refreshCurrentUserReviewState());
      });
    } catch (e) {
      debugPrint('Error listening to request contract: $e');

      if (!mounted) return;
      setState(() {
        _isLoadingContractData = false;
        _contractData = null;
        _currentUserReviewData = null;
        _isLoadingReviewData = false;
      });
    }
  }

  Future<void> _refreshContractDataFromSource() async {
    final savedContractData = await _loadContractDataFromSource();
    if (!mounted) return;

    setState(() {
      _contractData = savedContractData ?? _contractData;
    });
  }

  String _reviewDocumentId({
    required String requestId,
    required String reviewerId,
  }) {
    return '${requestId}_$reviewerId';
  }

  String _reviewedUserRole() {
    final role = widget.otherUserRole.trim().toLowerCase();
    if (role == 'client' || role == 'freelancer') {
      return role;
    }
    return _currentUserRole() == 'client' ? 'freelancer' : 'client';
  }

  bool _isContractCompletedForReview(Map<String, dynamic>? contractData) {
    if (contractData == null) return false;

    final approval = _asMap(contractData['approval']);
    final contractStatus = (approval['contractStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return contractStatus == 'completed';
  }

  Future<Map<String, dynamic>> _loadCurrentUserProfileData() async {
    final currentUserId = _controller.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw Exception('Current user not found');
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .get();

    if (!userDoc.exists) {
      throw Exception('Current user profile not found');
    }

    return userDoc.data() ?? <String, dynamic>{};
  }

  Future<void> _refreshReviewedUserRatingSummary(String reviewedUserId) async {
    final reviewsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(reviewedUserId)
        .collection('reviews')
        .get();

    final docs = reviewsSnapshot.docs;
    final count = docs.length;
    double average = 0;

    if (count > 0) {
      final total = docs.fold<double>(0, (sum, doc) {
        final rawRating = doc.data()['rating'];
        final rating = rawRating is num ? rawRating.toDouble() : 0.0;
        return sum + rating;
      });
      average = double.parse((total / count).toStringAsFixed(1));
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(reviewedUserId)
        .set({
          'rating': average,
          'reviewsCount': count,
        }, SetOptions(merge: true));
  }

  Future<void> _refreshCurrentUserReviewState() async {
    final currentUserId = _controller.currentUserId;
    final reviewedUserId = widget.otherUserId.trim();
    final requestId = (_requestId ?? '').trim();

    if (currentUserId == null ||
        currentUserId.isEmpty ||
        reviewedUserId.isEmpty ||
        requestId.isEmpty ||
        !_isContractCompletedForReview(_contractData)) {
      if (!mounted) return;
      setState(() {
        _currentUserReviewData = null;
        _isLoadingReviewData = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingReviewData = true;
      });
    }

    try {
      final reviewDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(reviewedUserId)
          .collection('reviews')
          .doc(
            _reviewDocumentId(requestId: requestId, reviewerId: currentUserId),
          )
          .get();

      if (!mounted) return;
      setState(() {
        _currentUserReviewData = reviewDoc.exists
            ? <String, dynamic>{'reviewId': reviewDoc.id, ...?reviewDoc.data()}
            : null;
        _isLoadingReviewData = false;
      });
    } catch (e) {
      debugPrint('Refresh review state error: $e');
      if (!mounted) return;
      setState(() {
        _currentUserReviewData = null;
        _isLoadingReviewData = false;
      });
    }
  }

  Future<void> _createReviewNotification({
    required String receiverId,
    required String requestId,
    required String contractId,
    required String actionText,
    required String snippet,
    required Map<String, dynamic> senderData,
  }) async {
    try {
      final senderId = _controller.currentUserId;
      if (senderId == null || senderId.trim().isEmpty) return;

      final senderName = _displayName(senderData, 'User');
      final senderProfileUrl = _firstFilled([
        senderData['photoUrl'],
        senderData['profile'],
      ]);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(receiverId)
          .collection('notifications')
          .add({
            'type': 'rating_review',
            'senderId': senderId,
            'senderName': senderName,
            'senderProfileUrl': senderProfileUrl,
            'senderProfileImage': senderProfileUrl,
            'receiverId': receiverId,
            'title': senderName.isEmpty ? 'New Review' : senderName,
            'message': actionText,
            'actionText': actionText,
            'snippet': snippet,
            'requestId': requestId,
            'contractId': contractId,
            'chatId': widget.chatId,
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Create review notification error: $e');
    }
  }

  Future<void> _createAdminContractReportNotification({
    required String reviewId,
  }) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'type': 'new_contract_report',
      'title': 'New Contract Review Request',
      'message': 'A new contract review request needs admin attention.',
      'targetRole': 'admin',
      'reviewId': reviewId,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _submitOrUpdateReview({
    required int rating,
    required String reviewText,
  }) async {
    await _accountAccessService.ensureCurrentUserNotBlocked();

    final currentUserId = _controller.currentUserId;
    final reviewedUserId = widget.otherUserId.trim();
    final requestId = (_requestId ?? '').trim();
    final contractData = _contractData;

    if (currentUserId == null || currentUserId.isEmpty) {
      throw Exception('Current user not found');
    }
    if (reviewedUserId.isEmpty || requestId.isEmpty) {
      throw Exception('Review target not found');
    }
    if (!_isContractCompletedForReview(contractData)) {
      throw Exception('Reviews are only available after completion');
    }

    final currentUserData = await _loadCurrentUserProfileData();
    final reviewerName = _displayName(currentUserData, 'User');
    final reviewDocId = _reviewDocumentId(
      requestId: requestId,
      reviewerId: currentUserId,
    );
    final contractId =
        (_asMap(contractData?['meta'])['contractId'] ?? requestId)
            .toString()
            .trim();

    final reviewRef = FirebaseFirestore.instance
        .collection('users')
        .doc(reviewedUserId)
        .collection('reviews')
        .doc(reviewDocId);

    final existingReviewDoc = await reviewRef.get();
    final isNewReview = !existingReviewDoc.exists;
    final trimmedText = reviewText.trim();
    final now = FieldValue.serverTimestamp();
    final reviewerProfileUrl = _firstFilled([
      currentUserData['photoUrl'],
      currentUserData['profile'],
    ]);

    final reviewPayload = <String, dynamic>{
      'reviewId': reviewDocId,
      'requestId': requestId,
      'contractId': contractId.isEmpty ? requestId : contractId,
      'reviewerId': currentUserId,
      'reviewerName': reviewerName,
      'reviewerRole': _currentUserRole(),
      'reviewedUserId': reviewedUserId,
      'reviewedUserRole': _reviewedUserRole(),
      'reviewerProfileUrl': reviewerProfileUrl,
      'rating': rating,
      'reviewText': trimmedText,
      'text': trimmedText,
      'updatedAt': now,
    };

    if (existingReviewDoc.exists) {
      final existingReviewerId = (existingReviewDoc.data()?['reviewerId'] ?? '')
          .toString()
          .trim();
      if (existingReviewerId.isNotEmpty &&
          existingReviewerId != currentUserId) {
        throw Exception('You can only edit your own review');
      }

      await reviewRef.set(reviewPayload, SetOptions(merge: true));
    } else {
      await reviewRef.set({...reviewPayload, 'createdAt': now});
    }

    if (isNewReview) {
      final actionText = _currentUserRole() == 'client'
          ? 'The client has rated and reviewed your completed service.'
          : 'The freelancer has rated and reviewed you for the completed service.';
      final notificationSnippet = _firstFilled([
        (_asMap(contractData?['meta'])['title'] ?? '').toString().trim(),
        contractDisplayTitle,
      ]);

      await _createReviewNotification(
        receiverId: reviewedUserId,
        requestId: requestId,
        contractId: contractId.isEmpty ? requestId : contractId,
        actionText: actionText,
        snippet: notificationSnippet,
        senderData: currentUserData,
      );
    }

    await _refreshReviewedUserRatingSummary(reviewedUserId);
    await _refreshCurrentUserReviewState();
  }

  Future<void> _deleteCurrentUserReview() async {
    final currentUserId = _controller.currentUserId;
    final reviewedUserId = widget.otherUserId.trim();
    final requestId = (_requestId ?? '').trim();

    if (currentUserId == null || currentUserId.isEmpty) {
      throw Exception('Current user not found');
    }
    if (reviewedUserId.isEmpty || requestId.isEmpty) {
      throw Exception('Review target not found');
    }

    final reviewRef = FirebaseFirestore.instance
        .collection('users')
        .doc(reviewedUserId)
        .collection('reviews')
        .doc(
          _reviewDocumentId(requestId: requestId, reviewerId: currentUserId),
        );

    final reviewDoc = await reviewRef.get();
    if (!reviewDoc.exists) return;

    final reviewerId = (reviewDoc.data()?['reviewerId'] ?? '')
        .toString()
        .trim();
    if (reviewerId.isNotEmpty && reviewerId != currentUserId) {
      throw Exception('You can only delete your own review');
    }

    await reviewRef.delete();
    await _refreshReviewedUserRatingSummary(reviewedUserId);
    await _refreshCurrentUserReviewState();
  }

  Future<void> _openReviewEditor({bool isEditing = false}) async {
    final existingReview = _currentUserReviewData;
    final initialRating = isEditing
        ? (() {
            final rawRating = existingReview?['rating'];
            final parsedRating = rawRating is num ? rawRating.toInt() : 0;
            return parsedRating.clamp(0, 5);
          })()
        : 0;
    final initialText =
        (existingReview?['reviewText'] ?? existingReview?['text'] ?? '')
            .toString();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewEditorSheet(
        primary: primary,
        isEditing: isEditing,
        initialRating: initialRating,
        initialText: initialText,
        reviewedUserName: widget.otherUserName,
        onSubmit: (rating, reviewText) async {
          if (mounted) {
            setState(() {
              _isSavingReview = true;
            });
          }

          try {
            await _submitOrUpdateReview(rating: rating, reviewText: reviewText);
            if (!mounted) return true;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isEditing
                      ? 'Review updated successfully'
                      : 'Review submitted successfully',
                ),
              ),
            );
            return true;
          } catch (error) {
            if (!mounted) return false;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_friendlyErrorMessage(error))),
            );
            return false;
          } finally {
            if (mounted) {
              setState(() {
                _isSavingReview = false;
              });
            }
          }
        },
      ),
    );

    if (submitted == true) {
      await _refreshCurrentUserReviewState();
    }
  }

  Future<void> _confirmDeleteReview() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Review'),
          content: const Text(
            'Do you want to delete your rating and review for this completed service?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC75A5A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    setState(() {
      _isSavingReview = true;
    });

    try {
      await _deleteCurrentUserReview();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review deleted successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('Delete review error: $e');
      unawaited(_showErrorDialog(_friendlyErrorMessage(e)));
    } finally {
      if (!mounted) return;
      setState(() {
        _isSavingReview = false;
      });
    }
  }

  Future<void> _loadOtherUserPhoto() async {
    try {
      if (widget.otherUserId.isEmpty) {
        debugPrint('⚠️  Cannot load photo: otherUserId is empty');
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .get();

      if (!doc.exists) return;

      final data = doc.data() ?? {};
      final photo = (data['photoUrl'] ?? data['profile'] ?? '').toString();

      if (!mounted) return;

      setState(() {
        _otherUserPhotoUrl = photo;
      });
    } catch (e) {
      debugPrint('❌ Error loading photo: $e');
    }
  }

  Future<void> _openOtherUserProfile() async {
    if (widget.adminReadOnlyMode) {
      return;
    }

    if (widget.otherUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User information not available')),
      );
      return;
    }

    var otherRole = widget.otherUserRole.trim().toLowerCase();

    if (otherRole != 'client' && otherRole != 'freelancer') {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.otherUserId)
            .get();

        final accountType = (doc.data()?['accountType'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (accountType == 'client' || accountType == 'freelancer') {
          otherRole = accountType;
        }
      } catch (e) {
        debugPrint('⚠️ Could not resolve other user role: $e');
      }
    }

    if (!mounted) return;

    if (otherRole == 'client') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FreelancerClientProfileView(
            clientId: widget.otherUserId,
            fromChat: true,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              FreelancerProfileView(userId: widget.otherUserId, fromChat: true),
        ),
      );
    }
  }

  void _scrollToBottom({bool jump = false}) {
    if (!_scrollController.hasClients) return;

    final bottom = _scrollController.position.maxScrollExtent;

    if (jump) {
      _scrollController.jumpTo(bottom);
    } else {
      _scrollController.animateTo(
        bottom,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        imageQuality: 85,
      );

      if (pickedFiles.isEmpty) return;

      final images = await Future.wait(
        pickedFiles.map(
          (e) async => (
            bytes: await e.readAsBytes(),
            mimeType: e.mimeType ?? 'image/jpeg',
          ),
        ),
      );

      setState(() {
        _selectedImages.addAll(images);
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Pick images error: $e');
      unawaited(_showErrorDialog(_friendlyErrorMessage(e)));
    }
  }

  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _clauseTitleController.dispose();
    _clauseContentController.dispose();
    _requestContractSubscription?.cancel();
    _terminationCountdownTimer?.cancel();
    _contractPreviewScrollController.dispose();
    _contractMessageCardScrollController.dispose();
    _approvedContractPanelScrollController.dispose();
    _freelancerProgressPanelScrollController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty && _selectedImages.isEmpty) return;
    if (await _showBlockedActionAndStopIfNeeded()) return;

    setState(() {
      _isSending = true;
    });

    try {
      await _controller.sendCombinedMessage(
        chatId: widget.chatId,
        text: text,
        images: _selectedImages,
      );

      _messageController.clear();
      _selectedImages.clear();

      await Future.delayed(const Duration(milliseconds: 100));

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Send message error: $e');
      unawaited(_showErrorDialog(_friendlyErrorMessage(e)));
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Widget _buildMessageBubble(MessageModel message) {
    if (widget.adminReadOnlyMode) {
      return _buildAdminReadOnlyMessageBubble(message);
    }

    if (message.type == 'contract') {
      final currentContractStatus =
          ((_contractData?['approval']
                      as Map<String, dynamic>?)?['contractStatus']
                  as Object?)
              ?.toString()
              .trim()
              .toLowerCase();
      if (currentContractStatus == 'approved') {
        return const SizedBox.shrink();
      }
      return _buildContractMessageCard(message);
    }

    final isMe = message.senderId == _controller.currentUserId;

    final hasImages =
        message.imageUrls.isNotEmpty || message.imageUrl.isNotEmpty;

    final displayImages = message.imageUrls.isNotEmpty
        ? message.imageUrls
        : (message.imageUrl.isNotEmpty ? [message.imageUrl] : []);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: hasImages
              ? const Color(0xFFF6F2FB)
              : (isMe ? primary : const Color(0xFFF1F1F1)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.text.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: hasImages ? 8 : 0),
                child: Text(
                  message.text,
                  style: TextStyle(
                    color: hasImages
                        ? Colors.black87
                        : (isMe ? Colors.white : Colors.black87),
                    fontSize: 14,
                  ),
                ),
              ),

            if (displayImages.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: displayImages.map((url) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            backgroundColor: Colors.black,
                            body: Center(
                              child: Image.network(
                                url,
                                errorBuilder: (_, error, stackTrace) {
                                  debugPrint(
                                    'Failed to load chat image from Firebase Storage: $error',
                                  );
                                  return const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'Failed to load image',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url,
                        width: 110,
                        height: 110,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) {
                          return const SizedBox(
                            width: 110,
                            height: 110,
                            child: Center(child: Text('Failed')),
                          );
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),

            if (isMe) ...[
              const SizedBox(height: 4),
              Icon(
                Icons.done_all,
                size: 16,
                color: message.isRead
                    ? Colors.lightBlueAccent
                    : (hasImages ? Colors.grey : Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdminReadOnlyMessageBubble(MessageModel message) {
    if (message.type == 'contract') {
      return _buildAdminReadOnlyContractMessageCard(message);
    }

    final hasImages =
        message.imageUrls.isNotEmpty || message.imageUrl.isNotEmpty;
    final displayImages = message.imageUrls.isNotEmpty
        ? message.imageUrls
        : (message.imageUrl.isNotEmpty ? [message.imageUrl] : const <String>[]);
    final isFreelancerMessage =
        widget.adminFreelancerId.trim().isNotEmpty &&
        message.senderId == widget.adminFreelancerId.trim();
    final senderLabel = _adminSenderLabel(message);

    return Align(
      alignment: isFreelancerMessage
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment: isFreelancerMessage
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                senderLabel,
                style: TextStyle(
                  color: primary.withOpacity(0.90),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: hasImages
                    ? const Color(0xFFF6F2FB)
                    : (isFreelancerMessage ? primary : const Color(0xFFF1F1F1)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: isFreelancerMessage
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.text.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(bottom: hasImages ? 8 : 0),
                      child: Text(
                        message.text,
                        style: TextStyle(
                          color: hasImages
                              ? Colors.black87
                              : (isFreelancerMessage
                                    ? Colors.white
                                    : Colors.black87),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  if (displayImages.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: displayImages.map((url) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  backgroundColor: Colors.black,
                                  body: Center(
                                    child: Image.network(
                                      url,
                                      errorBuilder: (_, error, stackTrace) {
                                        debugPrint(
                                          'Failed to load chat image from Firebase Storage: $error',
                                        );
                                        return const Padding(
                                          padding: EdgeInsets.all(24),
                                          child: Text(
                                            'Failed to load image',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              url,
                              width: 110,
                              height: 110,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return const SizedBox(
                                  width: 110,
                                  height: 110,
                                  child: Center(child: Text('Failed')),
                                );
                              },
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminReadOnlyContractMessageCard(MessageModel message) {
    final summaryLines = message.contractSummary
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(3)
        .toList();
    final previewText = summaryLines.isNotEmpty
        ? summaryLines.join('\n')
        : message.contractText.trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F2FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message.contractTitle.trim().isEmpty
                      ? 'Contract Update'
                      : message.contractTitle,
                  style: const TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
          if (previewText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              previewText,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 13.2,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _adminSenderLabel(MessageModel message) {
    final senderId = message.senderId.trim();
    if (senderId.isNotEmpty && senderId == widget.adminClientId.trim()) {
      final clientName = widget.adminClientName.trim();
      return clientName.isEmpty ? 'Client' : clientName;
    }

    if (senderId.isNotEmpty && senderId == widget.adminFreelancerId.trim()) {
      final freelancerName = widget.adminFreelancerName.trim();
      return freelancerName.isEmpty ? 'Freelancer' : freelancerName;
    }

    return 'Participant';
  }

  Widget _buildAdminReadOnlyBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F2FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary.withOpacity(0.16)),
      ),
      child: const Row(
        children: [
          Icon(Icons.admin_panel_settings_outlined, color: primary, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Admin read-only view',
              style: TextStyle(
                color: primary,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminReadOnlyScaffold() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: primary,
        elevation: 0,
        title: const Text('Chat'),
      ),
      body: Column(
        children: [
          _buildAdminReadOnlyBanner(),
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: _controller.getMessages(widget.chatId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Failed to load messages: ${snapshot.error}'),
                  );
                }

                final messages = snapshot.data ?? [];
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom(jump: true);
                });

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet.',
                      style: TextStyle(fontSize: 15),
                    ),
                  );
                }

                return Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(messages[index]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _parseContractDeadline(String rawDeadline) {
    final deadline = rawDeadline.trim();
    if (deadline.isEmpty) return null;

    final parsedIsoDate = DateTime.tryParse(deadline);
    if (parsedIsoDate != null) {
      return DateTime(
        parsedIsoDate.year,
        parsedIsoDate.month,
        parsedIsoDate.day,
      );
    }

    final normalizedDeadline = deadline
        .replaceAll('-', '/')
        .replaceAll('.', '/');
    final parts = normalizedDeadline
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.length != 3) return null;

    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    final third = int.tryParse(parts[2]);

    if (first == null || second == null || third == null) return null;

    try {
      if (parts[0].length == 4) {
        return DateTime(first, second, third);
      }

      if (parts[2].length == 4) {
        return DateTime(third, second, first);
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<void> _pickContractDeadline() async {
    final parsedDeadline = _parseContractDeadline(_editableDeadline);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate =
        parsedDeadline != null && !parsedDeadline.isBefore(today)
        ? parsedDeadline
        : now;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) return;

    _editableDeadline =
        '${pickedDate.year.toString().padLeft(4, '0')}-'
        '${pickedDate.month.toString().padLeft(2, '0')}-'
        '${pickedDate.day.toString().padLeft(2, '0')}';

    setState(() {});
  }

  String? _validateContractInputs() {
    final amountText = _editableAmount.trim();
    if (amountText.isEmpty) {
      return 'Amount must not be empty';
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      return 'Amount must be a valid positive number';
    }

    final deadlineText = _editableDeadline.trim();
    if (deadlineText.isEmpty) {
      return 'Deadline must not be empty';
    }
    if (_parseContractDeadline(deadlineText) == null) {
      return 'Deadline is invalid';
    }

    for (final clause in _pendingCustomClauses) {
      final title = (clause['title'] ?? '').trim();
      final content = (clause['content'] ?? '').trim();

      if (title.isEmpty && content.isEmpty) {
        continue;
      }
      if (title.isEmpty || content.isEmpty) {
        return 'Every pending custom clause must have title and content';
      }
      if (title.length > 80) {
        return 'Clause title must be 80 characters or less';
      }
      if (content.length > 500) {
        return 'Clause content must be 500 characters or less';
      }
    }

    return null;
  }

  String? _validateContractDescription(String? value) {
    final serviceDescription = (value ?? '').trim();
    if (serviceDescription.isEmpty) {
      return 'Service description must not be empty';
    }
    if (RegExp(
      r'(https?:\/\/|www\.)',
      caseSensitive: false,
    ).hasMatch(serviceDescription)) {
      return 'Service description must not contain links';
    }
    if (RegExp(r'^\d+$').hasMatch(serviceDescription)) {
      return 'Service description must not contain only digits';
    }
    if (serviceDescription.length > 150) {
      return 'Service description must be 150 characters or less';
    }

    return null;
  }

  bool _hasContractDeadlinePassed(String rawDeadline) {
    final parsedDeadline = _parseContractDeadline(rawDeadline);
    if (parsedDeadline == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return today.isAfter(parsedDeadline);
  }

  Widget _buildContractMessageCard(MessageModel message) {
    final currentContractStatus =
        ((_contractData?['approval']
                    as Map<String, dynamic>?)?['contractStatus']
                as Object?)
            ?.toString()
            .trim()
            .toLowerCase();
    if (currentContractStatus != 'approved') {
      return const SizedBox.shrink();
    }

    final requestId = message.requestId.trim().isNotEmpty
        ? message.requestId.trim()
        : widget.chatId;
    final isApprovedContract = currentContractStatus == 'approved';
    final cardTitleText = currentContractStatus == 'approved'
        ? 'Approved Contract'
        : currentContractStatus == 'rejected'
        ? 'Rejected Contract'
        : currentContractStatus == 'termination_pending'
        ? 'Contract'
        : 'Generated Contract';
    final statusChipText = currentContractStatus == 'approved'
        ? 'Approved'
        : currentContractStatus == 'rejected'
        ? 'Rejected'
        : currentContractStatus == 'termination_pending'
        ? 'Termination Pending'
        : 'Waiting';
    final statusChipBackgroundColor = currentContractStatus == 'approved'
        ? const Color(0xFFE8F5E9)
        : currentContractStatus == 'rejected'
        ? const Color(0xFFFFEBEE)
        : currentContractStatus == 'termination_pending'
        ? const Color(0xFFFFF4E5)
        : const Color(0xFFFFF4E5);
    final statusChipTextColor = currentContractStatus == 'approved'
        ? const Color(0xFF2E7D32)
        : currentContractStatus == 'rejected'
        ? Colors.redAccent
        : currentContractStatus == 'termination_pending'
        ? const Color(0xFFEF6C00)
        : const Color(0xFFEF6C00);
    final summaryLines = message.contractSummary
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(2)
        .toList();
    final fallbackText = message.contractText.trim();
    final previewText = summaryLines.isNotEmpty
        ? summaryLines.join('\n')
        : (fallbackText.length > 180
              ? '${fallbackText.substring(0, 180)}...'
              : fallbackText);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: _chatPanelDecoration(
          backgroundColor: _chatPanelBackground,
          borderColor: primary.withOpacity(0.16),
          showShadow: false,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cardTitleText,
              style: _chatPanelTitleStyle.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusChipBackgroundColor,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                statusChipText,
                style: TextStyle(
                  color: statusChipTextColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              contractDisplayTitle,
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (previewText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                previewText,
                style: const TextStyle(color: Colors.black87, height: 1.4),
              ),
            ],
            const SizedBox(height: 12),
            _buildContractProgressSection(
              contractStatus: currentContractStatus ?? '',
              currentUserRole: _currentUserRole(),
            ),
            if (isApprovedContract) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => downloadContract(requestId),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primary,
                        side: BorderSide(
                          color: primary.withOpacity(0.22),
                          width: 1,
                        ),
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Download Contract'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () async {
          if (await _showBlockedActionAndStopIfNeeded()) return;

          setState(() {
            _isGeneratingContract = true;
            _contractError = null;
            _contractData = null;
          });

          try {
            final chatDoc = await FirebaseFirestore.instance
                .collection('chat')
                .doc(widget.chatId)
                .get();

            final chatData = chatDoc.data();
            final requestId = _extractRequestId(chatData);
            final proposalId = (chatData?['proposalId'] ?? '')
                .toString()
                .trim();
            final announcementId = (chatData?['announcementId'] ?? '')
                .toString()
                .trim();
            final requestBody = <String, dynamic>{'requestId': requestId};
            if (proposalId.isNotEmpty) {
              requestBody['proposalId'] = proposalId;
            }
            debugPrint('Generate Contract requestId: $requestId');
            debugPrint('Generate Contract proposalId: $proposalId');
            debugPrint('Generate Contract announcementId: $announcementId');

            final response = await _postContractApi(
              endpointPath: 'generate-contract-from-request-id',
              body: requestBody,
              logLabel: 'Generate contract',
              timeout: _generateContractRequestTimeout,
            );

            final data = _tryDecodeResponseBodyAsMap(
              response,
              actionLabel: 'Generate contract',
            );

            if (_isSuccessfulStatusCode(response.statusCode)) {
              debugPrint('Generate contract response: $data');

              final freshContractData = _normalizeGeneratedContractData(
                await _resolveContractDataForUiSync(
                  actionLabel: 'Generate contract',
                  responseData: data,
                  retrySavedSource: true,
                ),
              );

              if (!mounted) return;

              setState(() {
                _contractError = null;
                if (freshContractData != null) {
                  _contractData = freshContractData;
                }
              });

              if (freshContractData == null) {
                debugPrint(
                  'Generate contract returned HTTP ${response.statusCode}, '
                  'but Flutter could not reload contractData yet.',
                );
              }

              await _runNonBlockingSecondaryAction(
                'Generate contract notification',
                () => _createContractNotification(
                  type: 'contract_generated',
                  actionText: 'generated a contract draft',
                  requestId: requestId,
                  chatData: chatData,
                  contractData: freshContractData,
                  notifyBothUsers: true,
                ),
              );

              debugPrint('Stored contract data: $_contractData');
            } else {
              await _showApiFailure(
                actionLabel: 'Generate contract',
                response: response,
                responseData: data,
                updateContractError: true,
              );
            }
          } on TimeoutException catch (error, stackTrace) {
            await _handleGenerateContractException(
              'Generate contract error',
              error,
              stackTrace,
            );
          } on SocketException catch (error, stackTrace) {
            await _handleGenerateContractException(
              'Generate contract error',
              error,
              stackTrace,
            );
          } on http.ClientException catch (error, stackTrace) {
            await _handleGenerateContractException(
              'Generate contract error',
              error,
              stackTrace,
            );
          } on FirebaseException catch (error, stackTrace) {
            await _handleGenerateContractException(
              'Generate contract error',
              error,
              stackTrace,
            );
          } on FormatException catch (error, stackTrace) {
            await _handleGenerateContractException(
              'Generate contract error',
              error,
              stackTrace,
            );
          } catch (error, stackTrace) {
            await _handleGenerateContractException(
              'Generate contract error',
              error,
              stackTrace,
            );
          } finally {
            if (!mounted) return;
            setState(() {
              _isGeneratingContract = false;
            });
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Text(
          'Generate Contract',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildGenerateContractSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _buildGenerateButton(),
    );
  }

  List<BoxShadow> get _chatPanelShadow => [
    BoxShadow(
      color: const Color(0xFF22113C).withOpacity(0.05),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  TextStyle get _chatPanelTitleStyle => const TextStyle(
    color: primary,
    fontWeight: FontWeight.w700,
    fontSize: 14.5,
  );

  TextStyle get _chatPanelSubtitleStyle => const TextStyle(
    color: Colors.black54,
    fontSize: 12.5,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );

  TextStyle get _chatPanelBodyStyle =>
      const TextStyle(color: Colors.black87, fontSize: 12.5, height: 1.4);

  BoxDecoration _chatPanelDecoration({
    Color? backgroundColor,
    Color? borderColor,
    double radius = _chatPanelRadius,
    bool showShadow = true,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? _chatPanelBackground,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? _chatPanelBorder),
      boxShadow: showShadow ? _chatPanelShadow : const [],
    );
  }

  Widget _buildChatPanelContainer({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    EdgeInsetsGeometry? margin,
    Color? backgroundColor,
    Color? borderColor,
    double radius = _chatPanelRadius,
    bool showShadow = true,
  }) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: _chatPanelDecoration(
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        radius: radius,
        showShadow: showShadow,
      ),
      child: child,
    );
  }

  Widget _buildChatPanelSurface({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    EdgeInsetsGeometry? margin,
    Color? backgroundColor,
    Color? borderColor,
    double radius = _chatPanelInnerRadius,
  }) {
    return _buildChatPanelContainer(
      padding: padding,
      margin: margin,
      backgroundColor: backgroundColor ?? _chatPanelSurface,
      borderColor: borderColor ?? primary.withOpacity(0.10),
      radius: radius,
      showShadow: false,
      child: child,
    );
  }

  Widget _buildChatPanelHeader({required String title, String? subtitle}) {
    final normalizedSubtitle = (subtitle ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _chatPanelTitleStyle),
        if (normalizedSubtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(normalizedSubtitle, style: _chatPanelSubtitleStyle),
        ],
      ],
    );
  }

  Widget _buildContractSection({
    required String title,
    required List<Widget> children,
  }) {
    return _buildChatPanelContainer(
      padding: const EdgeInsets.all(14),
      showShadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _chatPanelTitleStyle.copyWith(fontSize: 14)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Future<void> _toggleContractEdit() async {
    final contractData = _contractData;
    if (contractData == null) return;

    final service =
        (contractData['service'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final payment =
        (contractData['payment'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final timeline =
        (contractData['timeline'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    if (_isEditingContract) {
      final descriptionValidationError = _validateContractDescription(
        _editableServiceDescription,
      );
      if (descriptionValidationError != null) {
        _showErrorDialog(descriptionValidationError);
        return;
      }

      final validationError = _validateContractInputs();

      if (validationError != null) {
        _showErrorDialog(validationError);
        return;
      }

      final updatedContractData = Map<String, dynamic>.from(contractData);
      final updatedService = Map<String, dynamic>.from(service);
      final updatedPayment = Map<String, dynamic>.from(payment);
      final updatedTimeline = Map<String, dynamic>.from(timeline);
      final existingCustomClauses =
          (contractData['customClauses'] as List?)?.toList() ?? [];
      final filledPendingClauses = _pendingCustomClauses
          .where(
            (clause) =>
                (clause['title'] ?? '').trim().isNotEmpty &&
                (clause['content'] ?? '').trim().isNotEmpty,
          )
          .map((clause) {
            return {
              'title': (clause['title'] ?? '').trim(),
              'content': (clause['content'] ?? '').trim(),
            };
          })
          .toList();

      updatedService['description'] = _editableServiceDescription.trim();
      updatedPayment['amount'] = _editableAmount.trim();
      updatedTimeline['deadline'] = _editableDeadline.trim();

      updatedContractData['service'] = updatedService;
      updatedContractData['payment'] = updatedPayment;
      updatedContractData['timeline'] = updatedTimeline;
      updatedContractData['customClauses'] = [
        ...existingCustomClauses,
        ...filledPendingClauses,
      ];

      setState(() {
        _isSavingContract = true;
      });

      try {
        await _saveWorkflowContractData(
          updatedContractData,
          logLabel: 'Update contract',
        );

        if (!mounted) return;

        setState(() {
          _isEditingContract = false;
          _isAddingClause = false;
          _pendingCustomClauses = [];
          _contractError = null;
        });

        _showSuccessSnackBar('Contract updated successfully');
      } on TimeoutException catch (error, stackTrace) {
        await _showLoggedError('Update contract error', error, stackTrace);
      } on SocketException catch (error, stackTrace) {
        await _showLoggedError('Update contract error', error, stackTrace);
      } on http.ClientException catch (error, stackTrace) {
        await _showLoggedError('Update contract error', error, stackTrace);
      } on FirebaseException catch (error, stackTrace) {
        await _showLoggedError('Update contract error', error, stackTrace);
      } on FormatException catch (error, stackTrace) {
        await _showLoggedError('Update contract error', error, stackTrace);
      } catch (error, stackTrace) {
        await _showLoggedError('Update contract error', error, stackTrace);
      } finally {
        if (!mounted) return;

        setState(() {
          _isSavingContract = false;
        });
      }

      return;
    }

    setState(() {
      _editableServiceDescription = (service['description'] ?? '').toString();
      _editableAmount = (payment['amount'] ?? '').toString();
      _editableDeadline = (timeline['deadline'] ?? '').toString();
      _isEditingContract = true;
      _isAddingClause = false;
      _pendingCustomClauses = [];
    });
  }

  Widget _buildContractInput({
    required String initialValue,
    required ValueChanged<String> onChanged,
    int maxLines = 1,
    TextInputType? keyboardType,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    bool readOnly = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      maxLines: maxLines,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      readOnly: readOnly,
      validator: validator,
      autovalidateMode: validator == null
          ? AutovalidateMode.disabled
          : AutovalidateMode.onUserInteraction,
      style: const TextStyle(color: Colors.black87, height: 1.4),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: _chatPanelSurface,
        suffixIcon: suffixIcon,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _chatPanelBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _chatPanelBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primary),
        ),
      ),
    );
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  // Milestone-schedule (10% / 40% / 50%) helpers ---------------------------
  //
  // Contracts generated before this schedule shipped have no `milestones`
  // key at all — `_milestones` returns an empty list for those, and every
  // caller below falls back to the legacy flat `payment`/`deliveryData`/
  // `paymentData` fields, so old contracts keep behaving exactly as they
  // did before (single lump-sum payment, single delivery cycle).

  List<Map<String, dynamic>> _milestones(Map<String, dynamic> contractData) {
    final raw = contractData['milestones'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw.map((item) => _asMap(item)).toList();
  }

  /// Index of the first not-yet-paid milestone ("the milestone currently in
  /// play"), or null once every milestone is paid (or there are none).
  int? _currentMilestoneIndex(Map<String, dynamic> contractData) {
    final milestones = _milestones(contractData);
    for (var i = 0; i < milestones.length; i++) {
      final status = (milestones[i]['status'] ?? '').toString().trim().toLowerCase();
      if (status != 'paid') return i;
    }
    return null;
  }

  Map<String, dynamic>? _currentMilestoneOrNull(
    Map<String, dynamic> contractData,
  ) {
    final milestones = _milestones(contractData);
    if (milestones.isEmpty) return null;
    final index = _currentMilestoneIndex(contractData);
    if (index == null) return null;
    return milestones[index];
  }

  /// The delivery data that live delivery actions (submit/approve/reject/
  /// withdraw, and access-gating checks) should read: the current
  /// milestone's own `deliveryData` for milestone-schedule contracts, or
  /// the legacy flat `deliveryData` field for contracts with none. Do NOT
  /// use the flat field directly for this — right after a milestone is
  /// paid it still mirrors the *just-paid* milestone, not the newly
  /// unlocked current one.
  Map<String, dynamic> _currentDeliveryData(Map<String, dynamic> contractData) {
    final milestone = _currentMilestoneOrNull(contractData);
    return milestone != null
        ? _asMap(milestone['deliveryData'])
        : _asMap(contractData['deliveryData']);
  }

  /// Same idea as [_currentDeliveryData], for `paymentData`.
  Map<String, dynamic> _currentPaymentData(Map<String, dynamic> contractData) {
    final milestone = _currentMilestoneOrNull(contractData);
    return milestone != null
        ? _asMap(milestone['paymentData'])
        : _asMap(contractData['paymentData']);
  }

  /// Writes a freshly-built `deliveryData` map back into
  /// [updatedContractData]: onto `milestones[currentIndex]` for
  /// milestone-schedule contracts (optionally also transitioning that
  /// milestone's own `status`), and always mirrored into the legacy flat
  /// `deliveryData` field so any not-yet-migrated reader still sees
  /// "what's happening right now" instead of stale data.
  void _applyDeliveryDataUpdate(
    Map<String, dynamic> updatedContractData,
    Map<String, dynamic> deliveryData, {
    String? milestoneStatus,
  }) {
    updatedContractData['deliveryData'] = deliveryData;

    final milestones = _milestones(updatedContractData);
    if (milestones.isEmpty) return;
    final index = _currentMilestoneIndex(updatedContractData);
    if (index == null) return;

    final updatedMilestones = milestones
        .map((milestone) => Map<String, dynamic>.from(milestone))
        .toList();
    final milestone = Map<String, dynamic>.from(updatedMilestones[index]);
    milestone['deliveryData'] = deliveryData;
    if (milestoneStatus != null) {
      milestone['status'] = milestoneStatus;
    }
    updatedMilestones[index] = milestone;
    updatedContractData['milestones'] = updatedMilestones;
  }

  Map<String, dynamic>? _nonEmptyMapOrNull(dynamic value) {
    final map = _asMap(value);
    return map.isEmpty ? null : map;
  }

  String _firstFilled(List<dynamic> values) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _fileNameFromPath(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) return 'Attachment';

    final segments = normalized.split(RegExp(r'[\\/]'));
    final name = segments.isEmpty ? normalized : segments.last.trim();
    return name.isEmpty ? 'Attachment' : name;
  }

  String _fileNameFromUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return 'Attachment';

    final segments = parsed.pathSegments;
    if (segments.isEmpty) return 'Attachment';

    final name = segments.last.trim();
    return name.isEmpty ? 'Attachment' : name;
  }

  String _storagePathFromDownloadUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    if (trimmed.startsWith('gs://')) {
      final withoutScheme = trimmed.substring(5);
      final slashIndex = withoutScheme.indexOf('/');
      if (slashIndex == -1 || slashIndex == withoutScheme.length - 1) {
        return '';
      }
      return withoutScheme.substring(slashIndex + 1).trim();
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return '';

    const objectMarker = '/o/';
    final markerIndex = uri.path.indexOf(objectMarker);
    if (markerIndex == -1) return '';

    final encodedPath = uri.path
        .substring(markerIndex + objectMarker.length)
        .trim();
    if (encodedPath.isEmpty) return '';

    return Uri.decodeComponent(encodedPath);
  }

  bool _isPreviewStoragePath(String path) {
    return path.trim().toLowerCase().startsWith('delivery_previews/');
  }

  String _legacyPreviewUrl(String url, String storagePath) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty || !_isPreviewStoragePath(storagePath)) return '';
    return trimmedUrl;
  }

  bool _isImageReference(String value) {
    final lowercase = value.trim().toLowerCase();
    return lowercase.endsWith('.jpg') ||
        lowercase.endsWith('.jpeg') ||
        lowercase.endsWith('.png') ||
        lowercase.endsWith('.gif') ||
        lowercase.endsWith('.webp') ||
        lowercase.endsWith('.bmp');
  }

  List<String> _dedupeStrings(Iterable<String> values) {
    final seen = <String>{};
    final output = <String>[];

    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) continue;
      seen.add(trimmed);
      output.add(trimmed);
    }

    return output;
  }

  List<_DeliveryRemoteFile> _deliveryImageItems(
    Map<String, dynamic> deliveryData,
  ) {
    final explicitItems = <_DeliveryRemoteFile>[];
    final rawItems = deliveryData['imageItems'];

    if (rawItems is List) {
      for (final item in rawItems) {
        final map = _asMap(item);
        final legacyUrl = (map['url'] ?? '').toString().trim();
        final inferredStoragePath = _storagePathFromDownloadUrl(legacyUrl);
        final storagePath = _firstFilled([
          map['storagePath'],
          inferredStoragePath,
        ]);
        final previewUrl = _firstFilled([
          map['previewUrl'],
          _legacyPreviewUrl(legacyUrl, storagePath),
        ]);
        final watermarkedPreviewUrl = (map['watermarkedPreviewUrl'] ?? '')
            .toString()
            .trim();
        final fileName = (map['fileName'] ?? '').toString().trim();

        if (storagePath.isEmpty &&
            previewUrl.isEmpty &&
            watermarkedPreviewUrl.isEmpty &&
            legacyUrl.isEmpty) {
          continue;
        }

        explicitItems.add(
          _DeliveryRemoteFile(
            name: fileName.isEmpty ? 'Image' : fileName,
            storagePath: storagePath,
            previewUrl: previewUrl,
            watermarkedPreviewUrl: watermarkedPreviewUrl,
            url: legacyUrl,
          ),
        );
      }
    }

    if (explicitItems.isNotEmpty) return explicitItems;

    final previewUrls = _stringList(deliveryData['previewImageUrls']);
    if (previewUrls.isNotEmpty) {
      return List<_DeliveryRemoteFile>.generate(previewUrls.length, (index) {
        final previewUrl = previewUrls[index];
        return _DeliveryRemoteFile(
          name: 'Preview ${index + 1}',
          previewUrl: previewUrl,
          url: previewUrl,
        );
      });
    }

    final finalUrls = _stringList(
      deliveryData['finalWorkUrls'],
    ).where(_isImageReference).toList();
    return List<_DeliveryRemoteFile>.generate(finalUrls.length, (index) {
      final url = finalUrls[index];
      final storagePath = _storagePathFromDownloadUrl(url);
      return _DeliveryRemoteFile(
        name: _fileNameFromUrl(url),
        storagePath: storagePath,
        url: url,
      );
    });
  }

  List<String> _deliveryImageUrls(Map<String, dynamic> deliveryData) {
    return _dedupeStrings(
      _deliveryImageItems(deliveryData)
          .map(
            (item) =>
                item.bestPreviewUrl.isNotEmpty ? item.bestPreviewUrl : item.url,
          )
          .where((url) => url.trim().isNotEmpty),
    );
  }

  List<_DeliveryRemoteFile> _deliveryFileItems(
    Map<String, dynamic> deliveryData,
  ) {
    final explicitItems = <_DeliveryRemoteFile>[];
    final rawItems = deliveryData['fileItems'];

    if (rawItems is List) {
      for (final item in rawItems) {
        final map = _asMap(item);
        final url = (map['url'] ?? '').toString().trim();
        final name = (map['name'] ?? '').toString().trim();
        final inferredStoragePath = _storagePathFromDownloadUrl(url);
        final storagePath = _firstFilled([
          map['storagePath'],
          inferredStoragePath,
        ]);
        final previewUrl = _firstFilled([
          map['previewUrl'],
          _legacyPreviewUrl(url, storagePath),
        ]);
        final watermarkedPreviewUrl = (map['watermarkedPreviewUrl'] ?? '')
            .toString()
            .trim();
        if (url.isEmpty &&
            storagePath.isEmpty &&
            previewUrl.isEmpty &&
            watermarkedPreviewUrl.isEmpty) {
          continue;
        }
        explicitItems.add(
          _DeliveryRemoteFile(
            url: url,
            storagePath: storagePath,
            previewUrl: previewUrl,
            watermarkedPreviewUrl: watermarkedPreviewUrl,
            name: name.isEmpty
                ? (url.isNotEmpty ? _fileNameFromUrl(url) : 'Attachment')
                : name,
          ),
        );
      }
    }

    if (explicitItems.isNotEmpty) return explicitItems;

    final finalWorkUrls = _stringList(
      deliveryData['finalWorkUrls'],
    ).where((url) => !_isImageReference(url)).toList();
    final fileNames = _stringList(deliveryData['fileNames']);

    return List<_DeliveryRemoteFile>.generate(finalWorkUrls.length, (index) {
      final url = finalWorkUrls[index];
      final fallbackName = index < fileNames.length
          ? fileNames[index]
          : _fileNameFromUrl(url);
      return _DeliveryRemoteFile(
        url: url,
        name: fallbackName,
        storagePath: _storagePathFromDownloadUrl(url),
      );
    });
  }

  List<String> _deliveryLinkUrls(Map<String, dynamic> deliveryData) {
    return _dedupeStrings([
      ..._stringList(deliveryData['linkUrls']),
      ..._stringList(deliveryData['links']),
    ]);
  }

  String _deliveryNotes(Map<String, dynamic> deliveryData) {
    return (deliveryData['notes'] ?? '').toString().trim();
  }

  bool _hasSubmittedWorkContent(Map<String, dynamic> deliveryData) {
    return _deliveryImageUrls(deliveryData).isNotEmpty ||
        _deliveryFileItems(deliveryData).isNotEmpty ||
        _deliveryLinkUrls(deliveryData).isNotEmpty;
  }

  bool _isDeliveryApproved(String status) {
    final normalized = _normalizeDeliveryStatus(status);
    return normalized == 'approved' || normalized == 'paid_delivered';
  }

  bool _isCompletedPaymentStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'paid' || normalized == 'completed';
  }

  bool _currentUserCanAccessFinalDelivery(Map<String, dynamic> contractData) {
    if (_currentUserRole() == 'freelancer') return true;

    // Milestone-aware: must check the CURRENT milestone's own payment/
    // delivery state, not the flat mirror fields — right after an earlier
    // milestone is paid, the flat fields still reflect *that* milestone
    // until the next one is acted on, which would otherwise prematurely
    // unlock the next (unpaid) milestone's files.
    final deliveryData = _currentDeliveryData(contractData);
    final paymentData = _currentPaymentData(contractData);
    final approval = _asMap(contractData['approval']);
    final deliveryStatus = _normalizeDeliveryStatus(deliveryData['status']);
    final paymentStatus = (paymentData['paymentStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final contractStatus = (approval['contractStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    return _isCompletedPaymentStatus(paymentStatus) ||
        deliveryStatus == 'paid_delivered' ||
        contractStatus == 'completed';
  }

  bool _shouldRestrictSubmittedWork(Map<String, dynamic> contractData) {
    return _currentUserRole() == 'client' &&
        !_currentUserCanAccessFinalDelivery(contractData);
  }

  Future<String?> _resolveDeliveryAssetUrl(
    _DeliveryRemoteFile item, {
    bool previewOnly = false,
  }) async {
    if (previewOnly) {
      final previewUrl = item.bestPreviewUrl;
      if (previewUrl.trim().isNotEmpty) {
        return previewUrl;
      }
    }

    if (item.storagePath.trim().isNotEmpty) {
      return await FirebaseStorage.instance
          .ref(item.storagePath)
          .getDownloadURL();
    }

    if (item.url.trim().isNotEmpty) {
      return item.url;
    }

    final previewUrl = item.bestPreviewUrl;
    return previewUrl.trim().isEmpty ? null : previewUrl;
  }

  Widget _buildDeliveryThumbnailPlaceholder({
    bool isLoading = false,
    bool isLocked = false,
  }) {
    return Container(
      width: 88,
      height: 88,
      color: const Color(0xFFF4EFFB),
      alignment: Alignment.center,
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: primary),
            )
          : Icon(
              isLocked ? Icons.lock_outline_rounded : Icons.image_outlined,
              color: primary,
            ),
    );
  }

  Widget _buildDeliveryImageThumbnail(
    _DeliveryRemoteFile item, {
    required bool previewOnly,
  }) {
    final directPreviewUrl = previewOnly
        ? item.bestPreviewUrl
        : item.bestPreviewUrl.isNotEmpty
        ? item.bestPreviewUrl
        : item.url;

    if (directPreviewUrl.trim().isNotEmpty) {
      return Image.network(
        directPreviewUrl,
        width: 88,
        height: 88,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _buildDeliveryThumbnailPlaceholder(isLoading: true);
        },
        errorBuilder: (_, __, ___) {
          return _buildDeliveryThumbnailPlaceholder(
            isLocked: !item.hasAccessibleUrl,
          );
        },
      );
    }

    if (!item.hasAccessibleUrl) {
      return _buildDeliveryThumbnailPlaceholder(isLocked: true);
    }

    return FutureBuilder<String?>(
      future: _resolveDeliveryAssetUrl(item, previewOnly: previewOnly),
      builder: (context, snapshot) {
        final resolvedUrl = snapshot.data?.trim() ?? '';
        if (resolvedUrl.isNotEmpty) {
          return Image.network(
            resolvedUrl,
            width: 88,
            height: 88,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return _buildDeliveryThumbnailPlaceholder(isLoading: true);
            },
            errorBuilder: (_, __, ___) {
              return _buildDeliveryThumbnailPlaceholder();
            },
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildDeliveryThumbnailPlaceholder(isLoading: true);
        }

        return _buildDeliveryThumbnailPlaceholder();
      },
    );
  }

  Future<void> _openDeliveryImageItem(
    _DeliveryRemoteFile item, {
    required bool previewOnly,
  }) async {
    try {
      final resolvedUrl = await _resolveDeliveryAssetUrl(
        item,
        previewOnly: previewOnly,
      );
      if (resolvedUrl == null || resolvedUrl.trim().isEmpty) {
        if (!mounted) return;
        await _showErrorDialog(
          previewOnly
              ? 'Preview only. Complete payment to download the final work.'
              : 'The final work could not be opened.',
        );
        return;
      }

      await _openDeliveryPreviewImage(
        resolvedUrl,
        overlayLabel: previewOnly
            ? 'Preview only - Payment required - Saneea'
            : null,
      );
    } catch (error, stackTrace) {
      _logCaughtError('Open delivery image error', error, stackTrace);
      if (!mounted) return;
      await _showErrorDialog(_friendlyErrorMessage(error));
    }
  }

  Future<void> _openDeliveryFileItem(
    _DeliveryRemoteFile item, {
    required bool previewOnly,
  }) async {
    try {
      final resolvedUrl = await _resolveDeliveryAssetUrl(
        item,
        previewOnly: previewOnly,
      );
      if (resolvedUrl == null || resolvedUrl.trim().isEmpty) {
        if (!mounted) return;
        await _showErrorDialog(
          previewOnly
              ? 'Preview only. Complete payment to download the final work.'
              : 'The final work could not be opened.',
        );
        return;
      }

      await _openDeliveryUrl(resolvedUrl);
    } catch (error, stackTrace) {
      _logCaughtError('Open delivery file error', error, stackTrace);
      if (!mounted) return;
      await _showErrorDialog(_friendlyErrorMessage(error));
    }
  }

  String _normalizeDeliveryLink(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  Future<void> _openDeliveryUrl(String url) async {
    final normalizedUrl = _normalizeDeliveryLink(url);
    final uri = Uri.tryParse(normalizedUrl);

    if (uri == null) {
      await _showErrorDialog('Could not open this link');
      return;
    }

    final opened = await launchUrl(uri);
    if (!opened && mounted) {
      await _showErrorDialog('Could not open this link');
    }
  }

  String _singleLineSnippet(String rawText) {
    return rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _displayName(Map<String, dynamic> data, String fallback) {
    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();
    final fullName = '$firstName $lastName'.trim();
    final name = (data['name'] ?? '').toString().trim();

    if (fullName.isNotEmpty) return fullName;
    if (name.isNotEmpty) return name;
    return fallback;
  }

  Widget _buildLiveContractPartyNameText({
    required String userId,
    required String fallbackName,
  }) {
    final normalizedUserId = userId.trim();
    final safeFallback = fallbackName.trim().isEmpty
        ? '-'
        : fallbackName.trim();
    const textStyle = TextStyle(color: Colors.black87, height: 1.4);

    if (normalizedUserId.isEmpty) {
      return Text(safeFallback, style: textStyle);
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(normalizedUserId)
          .get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final displayName = data == null
            ? safeFallback
            : _displayName(data, safeFallback);

        return Text(displayName, style: textStyle);
      },
    );
  }

  DateTime? _parseContractDateTime(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return null;

    try {
      return DateTime.parse(text);
    } catch (_) {
      final parts = text.split('/');
      if (parts.length == 3) {
        final day = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        final year = int.tryParse(parts[2]);
        if (day != null && month != null && year != null) {
          return DateTime(year, month, day);
        }
      }
    }

    return null;
  }

  bool _isWithinTerminationGracePeriod() {
    final contractData = _contractData;
    if (contractData == null) return false;

    final meta = _asMap(contractData['meta']);
    final explicitDeadline = _parseContractDateTime(
      meta['terminationEligibleUntil'],
    );
    if (explicitDeadline != null) {
      return DateTime.now().isBefore(explicitDeadline) ||
          DateTime.now().isAtSameMomentAs(explicitDeadline);
    }

    final createdAt = _parseContractDateTime(
      meta['createdAtIso'] ?? meta['createdAt'],
    );
    if (createdAt == null) return false;

    final deadline = createdAt.add(const Duration(minutes: 3));
    return DateTime.now().isBefore(deadline) ||
        DateTime.now().isAtSameMomentAs(deadline);
  }

  Map<String, dynamic>? _terminationGracePeriodData() {
    final contractData = _contractData;
    if (contractData == null) return null;

    final approval = _asMap(contractData['approval']);
    final contractStatus = (approval['contractStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (contractStatus != 'approved') return null;

    final meta = _asMap(contractData['meta']);
    final startedAt = _parseContractDateTime(
      meta['createdAtIso'] ?? meta['approvedAt'] ?? meta['createdAt'],
    );
    final explicitDeadline = _parseContractDateTime(
      meta['terminationEligibleUntil'],
    );
    final effectiveDeadline =
        explicitDeadline ??
        (startedAt != null ? startedAt.add(const Duration(minutes: 3)) : null);
    if (effectiveDeadline == null) return null;

    final now = DateTime.now();
    final isExpired = now.isAfter(effectiveDeadline);
    final totalDuration = startedAt != null
        ? effectiveDeadline.difference(startedAt)
        : null;
    final remainingDuration = effectiveDeadline.difference(now);
    final remainingMinutes = remainingDuration.inMinutes.clamp(0, 1000000);
    final hours = remainingMinutes ~/ 60;
    final minutes = remainingMinutes % 60;

    String label;
    if (isExpired) {
      label = 'Expired';
    } else if (hours > 0) {
      label = '${hours}h ${minutes}m';
    } else {
      label = '${minutes}m';
    }

    double progress = 0;
    if (!isExpired && totalDuration != null && totalDuration.inSeconds > 0) {
      progress = (remainingDuration.inSeconds / totalDuration.inSeconds).clamp(
        0.0,
        1.0,
      );
    }

    Color indicatorColor;
    if (isExpired) {
      indicatorColor = const Color(0xFFC75A5A);
    } else if (progress > 0.5) {
      indicatorColor = const Color(0xFF43A047);
    } else if (progress > 0.2) {
      indicatorColor = const Color(0xFFEF6C00);
    } else {
      indicatorColor = const Color(0xFFC75A5A);
    }

    return {
      'label': label,
      'progress': progress,
      'isExpired': isExpired,
      'indicatorColor': indicatorColor,
      'subtitle': isExpired
          ? 'Free termination period has ended.'
          : 'Free termination window',
    };
  }

  String _terminationCompensationText() {
    final contractData = _contractData;
    if (contractData == null) return '20% of the contract amount';

    final payment = _asMap(contractData['payment']);
    final amountText = (payment['amount'] ?? '').toString().trim();
    final currency = (payment['currency'] ?? 'SAR').toString().trim();
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      return '20% of the contract amount';
    }

    final compensation = amount * 0.20;
    final formattedCompensation = compensation == compensation.roundToDouble()
        ? compensation.toInt().toString()
        : compensation.toStringAsFixed(2);
    return '$formattedCompensation $currency';
  }

  double? _terminationCompensationAmount() {
    final contractData = _contractData;
    if (contractData == null) return null;

    final payment = _asMap(contractData['payment']);
    final amountText = (payment['amount'] ?? '').toString().trim();
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) return null;
    return amount * 0.20;
  }

  String _currentUserRole() {
    final otherRole = widget.otherUserRole.trim().toLowerCase();
    if (otherRole == 'client') return 'freelancer';
    return 'client';
  }

  String _normalizeContractProgressStage(dynamic value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    switch (normalized) {
      case 'processing':
      case 'under_review':
      case 'completed':
        return normalized;
      case 'started':
      default:
        return 'started';
    }
  }

  List<String> get _contractProgressStages => const [
    'started',
    'processing',
    'under_review',
    'completed',
  ];

  int _contractProgressIndex(String stage) {
    return _contractProgressStages.indexOf(
      _normalizeContractProgressStage(stage),
    );
  }

  String _contractProgressLabel(String stage) {
    switch (_normalizeContractProgressStage(stage)) {
      case 'processing':
        return 'Processing';
      case 'under_review':
        return 'Under Review';
      case 'completed':
        return 'Completed';
      case 'started':
      default:
        return 'Started';
    }
  }

  Future<void> _switchPanels({
    required bool openApprovedContract,
    required bool openFreelancerProgress,
    required bool openWorkProgressSheet,
  }) async {
    if (!mounted || _isSwitchingPanels) return;

    final shouldCloseFirst =
        (openApprovedContract &&
            (_isFreelancerProgressPanelExpanded || _isWorkProgressSheetOpen)) ||
        (openFreelancerProgress &&
            (_isApprovedContractPanelExpanded || _isWorkProgressSheetOpen)) ||
        (openWorkProgressSheet &&
            (_isApprovedContractPanelExpanded ||
                _isFreelancerProgressPanelExpanded));

    if (shouldCloseFirst) {
      setState(() {
        _isSwitchingPanels = true;
        _isApprovedContractPanelExpanded = false;
        _isFreelancerProgressPanelExpanded = false;
        _isWorkProgressSheetOpen = false;
      });

      await Future.delayed(_panelSwitchDuration);
      if (!mounted) return;
    }

    setState(() {
      _isApprovedContractPanelExpanded = openApprovedContract;
      _isFreelancerProgressPanelExpanded = openFreelancerProgress;
      _isWorkProgressSheetOpen = openWorkProgressSheet;
      _isSwitchingPanels = false;
    });
  }

  Future<void> _toggleApprovedContractPanelSize() {
    final nextExpanded = !_isApprovedContractPanelExpanded;
    return _switchPanels(
      openApprovedContract: nextExpanded,
      openFreelancerProgress: false,
      openWorkProgressSheet: false,
    );
  }

  Future<void> _toggleFreelancerProgressPanel() {
    final nextExpanded = !_isFreelancerProgressPanelExpanded;
    return _switchPanels(
      openApprovedContract: false,
      openFreelancerProgress: nextExpanded,
      openWorkProgressSheet: false,
    );
  }

  bool _shouldShowWorkProgressAction() {
    final contractData = _contractData;
    if (contractData == null) return false;

    final approval = _asMap(contractData['approval']);
    final contractStatus = (approval['contractStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    return contractStatus == 'approved' ||
        contractStatus == 'completed' ||
        contractStatus == 'termination_pending' ||
        contractStatus == 'terminated';
  }

  Future<void> _openWorkProgressSheet() {
    final contractData = _contractData;
    if (contractData == null) {
      return Future.value();
    }

    if (!_shouldShowWorkProgressAction()) {
      return Future.value();
    }

    final nextOpen = !_isWorkProgressSheetOpen;
    return _switchPanels(
      openApprovedContract: false,
      openFreelancerProgress: false,
      openWorkProgressSheet: nextOpen,
    );
  }

  Widget _buildReviewActionSection() {
    if (!_isContractCompletedForReview(_contractData)) {
      return const SizedBox.shrink();
    }

    final existingReview = _currentUserReviewData;
    final hasSubmittedReview = existingReview != null;
    final existingRating = (() {
      final rawRating = existingReview?['rating'];
      return rawRating is num ? rawRating.toInt().clamp(0, 5) : 0;
    })();
    final existingText =
        (existingReview?['reviewText'] ?? existingReview?['text'] ?? '')
            .toString()
            .trim();

    if (hasSubmittedReview && !_isLoadingReviewData) {
      return _buildChatPanelContainer(
        padding: const EdgeInsets.all(14),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Rating & Review',
                    style: _chatPanelTitleStyle.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  if (existingText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(existingText, style: _chatPanelBodyStyle),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: List.generate(5, (index) {
                      return Icon(
                        index < existingRating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 18,
                      );
                    }),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: 'Edit Review',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                onPressed: _isSavingReview
                    ? null
                    : () => _openReviewEditor(isEditing: true),
                icon: const Icon(Icons.edit_outlined, color: primary, size: 22),
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: IconButton(
                tooltip: 'Delete Review',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                onPressed: _isSavingReview ? null : _confirmDeleteReview,
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFC75A5A),
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _buildChatPanelContainer(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rating & Review',
            style: _chatPanelTitleStyle.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 10),
          Text(
            hasSubmittedReview
                ? 'You already reviewed this completed service. You can edit or delete your review.'
                : 'This service is completed. You can now rate and review the other user.',
            style: _chatPanelSubtitleStyle.copyWith(
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_isLoadingReviewData) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: primary,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Loading review status.',
                  style: TextStyle(color: primary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ] else if (!hasSubmittedReview) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSavingReview ? null : () => _openReviewEditor(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.star_rounded),
                label: const Text('Rate & Review'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _contractProgressColor(String stage) {
    switch (_normalizeContractProgressStage(stage)) {
      case 'processing':
        return const Color(0xFF1565C0);
      case 'under_review':
        return const Color(0xFFEF6C00);
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'started':
      default:
        return const Color(0xFF9575CD);
    }
  }

  String _normalizeDeliveryStatus(dynamic value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    switch (normalized) {
      case 'submitted':
      case 'changes_requested':
      case 'approved':
      case 'approved_awaiting_payment':
      case 'paid_delivered':
        return normalized == 'approved_awaiting_payment'
            ? 'approved'
            : normalized;
      case 'not_submitted':
      default:
        return 'not_submitted';
    }
  }

  String _deliveryStatusLabel(String status) {
    switch (_normalizeDeliveryStatus(status)) {
      case 'submitted':
        return 'Work Submitted';
      case 'changes_requested':
        return 'Changes Requested';
      case 'approved':
      case 'paid_delivered':
        return 'Approved';
      case 'not_submitted':
      default:
        return 'Waiting for Submitted Work';
    }
  }

  String _deliveryStatusPaymentMessage({
    required String status,
    required bool isClientView,
  }) {
    switch (_normalizeDeliveryStatus(status)) {
      case 'submitted':
        return isClientView
            ? 'Work is submitted. Payment is available after approval.'
            : 'The submitted work is waiting for client review.';
      case 'changes_requested':
        return isClientView
            ? 'Changes were requested. Payment will stay disabled until the freelancer submits an updated delivery.'
            : 'Changes were requested. Submit an updated delivery to re-enable client review.';
      case 'approved':
        return isClientView
            ? 'Payment is available after approval.'
            : 'The client approved the submitted work. The submitted files remain available below.';
      case 'paid_delivered':
        return 'Payment was completed successfully and the submitted work remains available below.';
      case 'not_submitted':
      default:
        return isClientView
            ? 'Payment will be enabled after the freelancer submits the final work.'
            : 'Submit the final work to unlock client review and payment.';
    }
  }

  String _normalizeAdminReviewStatus(dynamic value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    switch (normalized) {
      case 'requested':
      case 'under_review':
      case 'resolved':
        return normalized;
      case 'none':
      default:
        return 'none';
    }
  }

  String _adminReviewReasonLabel(String reasonType) {
    switch ((reasonType).trim().toLowerCase()) {
      case 'no_response':
        return 'No response';
      case 'delivery_dispute':
        return 'Delivery dispute';
      case 'inappropriate_content':
        return 'Inappropriate content';
      case 'abuse_or_manipulation':
        return 'Abuse or manipulation';
      case 'general_issue':
        return 'General issue';
      default:
        return 'General issue';
    }
  }

  String _contractReviewReasonLabel(String reasonType) {
    switch ((reasonType).trim().toLowerCase()) {
      case 'no_response':
        return 'No response from the other party';
      case 'mismatched_delivery':
        return 'Delivered work does not match the agreement';
      case 'party_disagreement':
        return 'Disagreement between both parties';
      case 'payment_delivery_issue':
        return 'Payment or delivery issue';
      case 'other_contract_issue':
      default:
        return 'Other contract issue';
    }
  }

  bool _canFreelancerSubmitWork(String contractStatus) {
    if (_currentUserRole() != 'freelancer') return false;
    if (contractStatus != 'approved') return false;

    final contractData = _contractData;
    if (contractData == null) return false;

    // Milestone-schedule contracts: only the current milestone can accept
    // a submission, and only if it actually has a deliverable (milestone
    // 1 / "on signing" has none — it's a payment-only gate).
    final milestones = _milestones(contractData);
    if (milestones.isNotEmpty) {
      final currentIndex = _currentMilestoneIndex(contractData);
      if (currentIndex == null) return false;
      final milestone = milestones[currentIndex];
      if (milestone['deliveryRequired'] != true) return false;
      final milestoneStatus =
          (milestone['status'] ?? '').toString().trim().toLowerCase();
      if (milestoneStatus == 'locked' || milestoneStatus == 'paid') {
        return false;
      }
    }

    final deliveryData = _currentDeliveryData(contractData);
    final paymentData = _currentPaymentData(contractData);
    final deliveryStatus = _normalizeDeliveryStatus(deliveryData['status']);
    final paymentStatus = (paymentData['paymentStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final isPaidDelivered =
        deliveryStatus == 'paid_delivered' ||
        _isCompletedPaymentStatus(paymentStatus);

    if (isPaidDelivered || contractStatus == 'completed') return false;

    return deliveryStatus == 'not_submitted' ||
        deliveryStatus == 'changes_requested' ||
        deliveryStatus == 'submitted';
  }

  Future<void> _saveWorkflowContractData(
    Map<String, dynamic> updatedContractData, {
    String logLabel = 'Save workflow contract',
  }) async {
    final chatDoc = await FirebaseFirestore.instance
        .collection('chat')
        .doc(widget.chatId)
        .get();
    final chatData = chatDoc.data();
    final requestId = _extractRequestId(chatData);
    final proposalId = (chatData?['proposalId'] ?? '').toString().trim();

    final response = await _postContractApi(
      endpointPath: 'update-contract',
      body: {
        'requestId': requestId,
        if (proposalId.isNotEmpty) 'proposalId': proposalId,
        'role': _currentUserRole(),
        'contractData': updatedContractData,
      },
      logLabel: logLabel,
    );

    final responseData = _tryDecodeResponseBodyAsMap(
      response,
      actionLabel: logLabel,
    );

    if (!_isSuccessfulStatusCode(response.statusCode)) {
      throw Exception(_responseErrorMessage(responseData, response.statusCode));
    }

    final responseReportedFailure =
        responseData['success'] is bool && responseData['success'] == false;
    if (responseReportedFailure) {
      throw Exception(_responseErrorMessage(responseData, response.statusCode));
    }

    _contractData = Map<String, dynamic>.from(updatedContractData);

    if (responseData.isEmpty) return;

    await _runNonBlockingSecondaryAction('$logLabel contract sync', () async {
      final savedContractData = await _resolveContractDataForUiSync(
        actionLabel: logLabel,
        responseData: responseData,
      );

      if (savedContractData != null) {
        _contractData = savedContractData;
      }
    });
  }

  Future<void> _submitDeliveryWork() async {
    final contractData = _contractData;
    if (contractData == null) return;
    if (await _showBlockedActionAndStopIfNeeded()) return;

    try {
      final deliveryData = _currentDeliveryData(contractData);
      final currentImageItems = _deliveryImageItems(deliveryData);
      final currentFileItems = _deliveryFileItems(deliveryData);
      final draft = await _showDeliverySubmissionDialog(
        deliveryData,
        isUpdate: _hasSubmittedWorkContent(deliveryData),
      );
      if (draft == null || !draft.hasContent) return;
      if (!mounted) return;

      setState(() {
        _isSavingContract = true;
      });

      final keptImageItems = currentImageItems
          .where(
            (item) => draft.keepImageUrls.contains(
              item.bestPreviewUrl.isNotEmpty ? item.bestPreviewUrl : item.url,
            ),
          )
          .map((item) {
            final shouldKeepLegacyUrl =
                item.url.isNotEmpty &&
                item.storagePath.isEmpty &&
                item.bestPreviewUrl.isEmpty;
            return {
              'fileName': item.name,
              if (item.storagePath.isNotEmpty) 'storagePath': item.storagePath,
              if (item.previewUrl.isNotEmpty) 'previewUrl': item.previewUrl,
              if (item.watermarkedPreviewUrl.isNotEmpty)
                'watermarkedPreviewUrl': item.watermarkedPreviewUrl,
              if (shouldKeepLegacyUrl) 'url': item.url,
            };
          })
          .toList();
      final uploadedImageItems = <Map<String, String>>[];
      if (draft.newImageFiles.isNotEmpty) {
        uploadedImageItems.addAll(
          await _controller.uploadDeliveryImages(
            chatId: widget.chatId,
            images: draft.newImageFiles,
          ),
        );
      }

      final keptFileItems = draft.keepFileItems
          .where(
            (item) => currentFileItems.any(
              (existingItem) =>
                  existingItem.storagePath == item.storagePath &&
                  existingItem.name == item.name,
            ),
          )
          .map((item) {
            final shouldKeepLegacyUrl =
                item.url.isNotEmpty &&
                item.storagePath.isEmpty &&
                item.bestPreviewUrl.isEmpty;
            return {
              'name': item.name,
              if (item.storagePath.isNotEmpty) 'storagePath': item.storagePath,
              if (item.previewUrl.isNotEmpty) 'previewUrl': item.previewUrl,
              if (item.watermarkedPreviewUrl.isNotEmpty)
                'watermarkedPreviewUrl': item.watermarkedPreviewUrl,
              if (shouldKeepLegacyUrl) 'url': item.url,
            };
          })
          .toList();
      final uploadedFileItems = <Map<String, String>>[];

      for (final file in draft.newDocumentFiles) {
        final uploadedItem = await _controller.uploadDeliveryFile(
          chatId: widget.chatId,
          fileBytes: file.bytes,
          fileName: file.name,
        );
        uploadedFileItems.add(uploadedItem);
      }

      final imageItems = [...keptImageItems, ...uploadedImageItems];
      final imagePreviewUrls = imageItems
          .map(
            (item) =>
                (item['watermarkedPreviewUrl'] ?? item['previewUrl'] ?? '')
                    .trim(),
          )
          .where((url) => url.isNotEmpty)
          .toList();
      final fileItems = [...keptFileItems, ...uploadedFileItems];
      final normalizedLinks = _dedupeStrings(
        draft.linkUrls.map(_normalizeDeliveryLink),
      );

      final submittedAt = DateTime.now().toIso8601String();
      final updatedContractData = Map<String, dynamic>.from(contractData);
      final updatedDeliveryData = _currentDeliveryData(updatedContractData);
      final updatedProgressData = _asMap(updatedContractData['progressData']);
      updatedDeliveryData['status'] = 'submitted';
      updatedDeliveryData['previewImageUrls'] = imagePreviewUrls;
      updatedDeliveryData['imageUrls'] = imagePreviewUrls;
      updatedDeliveryData['imageItems'] = imageItems;
      updatedDeliveryData['fileItems'] = fileItems;
      updatedDeliveryData['finalWorkUrls'] = <String>[];
      updatedDeliveryData['fileNames'] = [
        ...imageItems
            .map((item) => item['fileName'] ?? '')
            .where((name) => name.isNotEmpty),
        ...fileItems
            .map((item) => item['name'] ?? '')
            .where((name) => name.isNotEmpty),
      ];
      updatedDeliveryData['linkUrls'] = normalizedLinks;
      updatedDeliveryData['notes'] = draft.notes.trim();
      updatedDeliveryData['submittedBy'] = _currentUserRole();
      updatedDeliveryData['submittedAt'] = submittedAt;
      updatedDeliveryData['changesRequestedBy'] = '';
      updatedDeliveryData['changesRequestedAt'] = '';
      updatedDeliveryData['approvedBy'] = '';
      updatedDeliveryData['approvedAt'] = '';
      updatedDeliveryData['approvedByClient'] = false;
      updatedProgressData['stage'] = 'completed';
      updatedProgressData['updatedAt'] = submittedAt;
      updatedProgressData['updatedBy'] = _currentUserRole();
      _applyDeliveryDataUpdate(
        updatedContractData,
        updatedDeliveryData,
        milestoneStatus: 'submitted',
      );
      updatedContractData['progressData'] = updatedProgressData;

      await _saveWorkflowContractData(updatedContractData);

      if (!mounted) return;
      _showSuccessSnackBar(
        _hasSubmittedWorkContent(deliveryData)
            ? 'Submission updated successfully'
            : 'Work submitted successfully',
      );
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError('Submit delivery error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError('Submit delivery error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError('Submit delivery error', error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError('Submit delivery error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError('Submit delivery error', error, stackTrace);
    } catch (error, stackTrace) {
      await _showLoggedError('Submit delivery error', error, stackTrace);
    } finally {
      if (!mounted) return;
      setState(() {
        _isSavingContract = false;
      });
    }
  }

  Future<void> _requestDeliveryChanges() async {
    final contractData = _contractData;
    if (contractData == null) return;

    setState(() {
      _isSavingContract = true;
    });

    try {
      final updatedContractData = Map<String, dynamic>.from(contractData);
      final deliveryData = _currentDeliveryData(updatedContractData);
      deliveryData['status'] = 'changes_requested';
      deliveryData['changesRequestedBy'] = _currentUserRole();
      deliveryData['changesRequestedAt'] = DateTime.now().toIso8601String();
      deliveryData['approvedByClient'] = false;
      _applyDeliveryDataUpdate(
        updatedContractData,
        deliveryData,
        milestoneStatus: 'changes_requested',
      );

      await _saveWorkflowContractData(updatedContractData);

      if (!mounted) return;
      _showSuccessSnackBar('Changes requested successfully');
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError(
        'Request delivery changes error',
        error,
        stackTrace,
      );
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError(
        'Request delivery changes error',
        error,
        stackTrace,
      );
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError(
        'Request delivery changes error',
        error,
        stackTrace,
      );
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError(
        'Request delivery changes error',
        error,
        stackTrace,
      );
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError(
        'Request delivery changes error',
        error,
        stackTrace,
      );
    } catch (error, stackTrace) {
      await _showLoggedError(
        'Request delivery changes error',
        error,
        stackTrace,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isSavingContract = false;
      });
    }
  }

  Future<void> _approveDeliveryForPayment() async {
    final contractData = _contractData;
    if (contractData == null) return;

    setState(() {
      _isSavingContract = true;
    });

    try {
      final updatedContractData = Map<String, dynamic>.from(contractData);
      final deliveryData = _currentDeliveryData(updatedContractData);
      deliveryData['status'] = 'approved';
      deliveryData['approvedBy'] = _currentUserRole();
      deliveryData['approvedAt'] = DateTime.now().toIso8601String();
      deliveryData['approvedByClient'] = true;
      _applyDeliveryDataUpdate(
        updatedContractData,
        deliveryData,
        milestoneStatus: 'approved',
      );

      await _saveWorkflowContractData(updatedContractData);

      if (!mounted) return;
      _showSuccessSnackBar('Submitted work approved');
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError('Approve delivery error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError('Approve delivery error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError('Approve delivery error', error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError('Approve delivery error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError('Approve delivery error', error, stackTrace);
    } catch (error, stackTrace) {
      await _showLoggedError('Approve delivery error', error, stackTrace);
    } finally {
      if (!mounted) return;
      setState(() {
        _isSavingContract = false;
      });
    }
  }

  Future<void> _withdrawDeliverySubmission() async {
    final contractData = _contractData;
    if (contractData == null) return;

    final shouldWithdraw = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Withdraw Submission'),
          content: const Text(
            'Do you want to withdraw the submitted work and return it to draft state?',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFC75A5A),
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: Color(0xFFC75A5A), width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: OutlinedButton.styleFrom(
                foregroundColor: primary,
                backgroundColor: Colors.transparent,
                side: BorderSide(color: primary, width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text('Withdraw'),
            ),
          ],
        );
      },
    );

    if (shouldWithdraw != true || !mounted) return;

    setState(() {
      _isSavingContract = true;
    });

    try {
      final updatedContractData = Map<String, dynamic>.from(contractData);
      final deliveryData = _currentDeliveryData(updatedContractData);
      deliveryData['status'] = 'not_submitted';
      deliveryData['previewImageUrls'] = <String>[];
      deliveryData['imageUrls'] = <String>[];
      deliveryData['imageItems'] = <Map<String, String>>[];
      deliveryData['fileItems'] = <Map<String, String>>[];
      deliveryData['finalWorkUrls'] = <String>[];
      deliveryData['fileNames'] = <String>[];
      deliveryData['linkUrls'] = <String>[];
      deliveryData['notes'] = '';
      deliveryData['submittedBy'] = '';
      deliveryData['submittedAt'] = '';
      deliveryData['changesRequestedBy'] = '';
      deliveryData['changesRequestedAt'] = '';
      deliveryData['approvedBy'] = '';
      deliveryData['approvedAt'] = '';
      deliveryData['approvedByClient'] = false;
      // Reset back to "pending" (payable/actionable), never "locked" — the
      // freelancer was already allowed into this milestone, withdrawing a
      // submission shouldn't lock them back out of it.
      _applyDeliveryDataUpdate(
        updatedContractData,
        deliveryData,
        milestoneStatus: 'pending',
      );

      await _saveWorkflowContractData(updatedContractData);

      if (!mounted) return;
      _showSuccessSnackBar('Submitted work withdrawn successfully');
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError(
        'Withdraw delivery submission error',
        error,
        stackTrace,
      );
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError(
        'Withdraw delivery submission error',
        error,
        stackTrace,
      );
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError(
        'Withdraw delivery submission error',
        error,
        stackTrace,
      );
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError(
        'Withdraw delivery submission error',
        error,
        stackTrace,
      );
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError(
        'Withdraw delivery submission error',
        error,
        stackTrace,
      );
    } catch (error, stackTrace) {
      await _showLoggedError(
        'Withdraw delivery submission error',
        error,
        stackTrace,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isSavingContract = false;
      });
    }
  }

  Future<void> _requestAdminReview() async {
    final contractData = _contractData;
    if (contractData == null) return;

    const options = <Map<String, String>>[
      {'value': 'delivery_dispute', 'label': 'Delivery dispute'},
      {'value': 'inappropriate_content', 'label': 'Inappropriate content'},
      {'value': 'abuse_or_manipulation', 'label': 'Abuse or manipulation'},
      {'value': 'general_issue', 'label': 'General issue'},
    ];

    final selectedReason = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Request Admin Review'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Choose the reason for requesting admin review.'),
              const SizedBox(height: 12),
              ...options.map((option) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(option['value']),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primary,
                        side: BorderSide(color: primary.withOpacity(0.22)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        alignment: Alignment.centerLeft,
                      ),
                      child: Text(
                        option['label']!,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFC75A5A),
                side: const BorderSide(color: Color(0xFFC75A5A)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (selectedReason == null || !mounted) return;

    setState(() {
      _isSavingContract = true;
    });

    try {
      final updatedContractData = Map<String, dynamic>.from(contractData);
      final adminReview = _asMap(updatedContractData['adminReview']);
      adminReview['status'] = 'requested';
      adminReview['requestedBy'] = _currentUserRole();
      adminReview['requestedAt'] = DateTime.now().toIso8601String();
      adminReview['reasonType'] = selectedReason;
      adminReview['reasonText'] = _adminReviewReasonLabel(selectedReason);
      adminReview['relatedArea'] = 'chat_delivery';
      updatedContractData['adminReview'] = adminReview;

      await _saveWorkflowContractData(updatedContractData);

      if (!mounted) return;
      _showSuccessSnackBar('Admin review requested successfully');
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError('Request admin review error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError('Request admin review error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError('Request admin review error', error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError('Request admin review error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError('Request admin review error', error, stackTrace);
    } catch (error, stackTrace) {
      await _showLoggedError('Request admin review error', error, stackTrace);
    } finally {
      if (!mounted) return;
      setState(() {
        _isSavingContract = false;
      });
    }
  }

  Future<void> _withdrawAdminReview() async {
    final contractData = _contractData;
    if (contractData == null) return;

    final shouldWithdraw = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Withdraw Complaint'),
          content: const Text(
            'Do you want to withdraw this admin review request?',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFC75A5A),
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: Color(0xFFC75A5A), width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: OutlinedButton.styleFrom(
                foregroundColor: primary,
                backgroundColor: Colors.transparent,
                side: BorderSide(color: primary, width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text('Withdraw'),
            ),
          ],
        );
      },
    );

    if (shouldWithdraw != true || !mounted) return;

    setState(() {
      _isSavingContract = true;
    });

    try {
      final updatedContractData = Map<String, dynamic>.from(contractData);
      updatedContractData['adminReview'] = {
        'status': 'none',
        'requestedBy': '',
        'requestedAt': '',
        'reasonType': '',
        'reasonText': '',
        'relatedArea': '',
      };

      await _saveWorkflowContractData(updatedContractData);

      if (!mounted) return;
      _showSuccessSnackBar('Complaint withdrawn successfully');
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError('Withdraw admin review error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError('Withdraw admin review error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError('Withdraw admin review error', error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError('Withdraw admin review error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError('Withdraw admin review error', error, stackTrace);
    } catch (error, stackTrace) {
      await _showLoggedError('Withdraw admin review error', error, stackTrace);
    } finally {
      if (!mounted) return;
      setState(() {
        _isSavingContract = false;
      });
    }
  }

  Future<String> _resolveRequestIdForContractReview() async {
    final cachedRequestId = (_requestId ?? '').trim();
    if (cachedRequestId.isNotEmpty) {
      return cachedRequestId;
    }

    final chatDoc = await FirebaseFirestore.instance
        .collection('chat')
        .doc(widget.chatId)
        .get();
    final requestId = _extractRequestId(chatDoc.data());
    _requestId = requestId;
    return requestId;
  }

  String _contractTerminationReportDocumentId({
    required String requestId,
    required String reporterId,
  }) {
    return 'termination_${requestId}_$reporterId';
  }

  String _terminationAdminReviewReasonLabel(String reasonType) {
    switch (reasonType.trim().toLowerCase()) {
      case 'no_response':
        return 'No response from the other party';
      case 'mismatched_delivery':
        return 'Delivered work does not match the agreement';
      case 'party_disagreement':
        return 'Disagreement between both parties';
      default:
        return 'Contract review';
    }
  }

  Future<Map<String, dynamic>?> _loadContractDataFromSource() async {
    final chatDoc = await FirebaseFirestore.instance
        .collection('chat')
        .doc(widget.chatId)
        .get();

    final chatData = chatDoc.data();
    final requestId = _extractRequestId(chatData);
    final proposalId = (chatData?['proposalId'] ?? '').toString().trim();
    final isAnnouncementProposalChat = proposalId.isNotEmpty;
    final sourceCollection = isAnnouncementProposalChat
        ? 'announcement_requests'
        : 'requests';
    final sourceDocumentId = isAnnouncementProposalChat
        ? proposalId
        : requestId;

    final sourceDoc = await FirebaseFirestore.instance
        .collection(sourceCollection)
        .doc(sourceDocumentId)
        .get();
    final sourceContractData = _nonEmptyMapOrNull(
      sourceDoc.data()?['contractData'],
    );
    if (sourceContractData != null) {
      return sourceContractData;
    }

    final requestDoc = await FirebaseFirestore.instance
        .collection('requests')
        .doc(requestId)
        .get();
    return _nonEmptyMapOrNull(requestDoc.data()?['contractData']);
  }

  Future<Map<String, dynamic>?> _waitForSavedContractData({
    int attempts = 24,
    Duration delay = const Duration(seconds: 1),
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      final savedContractData = await _loadContractDataFromSource();
      if (savedContractData != null) {
        return savedContractData;
      }

      debugPrint(
        'Waiting for saved contractData attempt ${attempt + 1}/$attempts',
      );

      if (attempt < attempts - 1) {
        await Future<void>.delayed(delay);
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> _resolveContractDataForUiSync({
    required String actionLabel,
    required Map<String, dynamic> responseData,
    bool retrySavedSource = false,
  }) async {
    final responseContractData = _contractDataFromApiResponse(responseData);
    if (responseContractData != null) {
      return responseContractData;
    }

    try {
      final savedContractData = retrySavedSource
          ? await _waitForSavedContractData()
          : await _loadContractDataFromSource();
      if (savedContractData != null) {
        return savedContractData;
      }

      debugPrint(
        '$actionLabel succeeded, but no contract data was found in the '
        'API response or saved source.',
      );
    } on FirebaseException catch (error, stackTrace) {
      _logCaughtError('$actionLabel contract sync error', error, stackTrace);
    } on TimeoutException catch (error, stackTrace) {
      _logCaughtError('$actionLabel contract sync error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      _logCaughtError('$actionLabel contract sync error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      _logCaughtError('$actionLabel contract sync error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      _logCaughtError('$actionLabel contract sync error', error, stackTrace);
    } catch (error, stackTrace) {
      _logCaughtError('$actionLabel contract sync error', error, stackTrace);
    }

    return null;
  }

  Map<String, dynamic>? _contractDataFromApiResponse(
    Map<String, dynamic> responseData,
  ) {
    final directContractData = _nonEmptyMapOrNull(responseData['contractData']);
    if (directContractData != null) {
      return directContractData;
    }

    final contract = _nonEmptyMapOrNull(responseData['contract']);
    if (contract == null) {
      return null;
    }

    return _nonEmptyMapOrNull(contract['contractData']) ?? contract;
  }

  Future<void> _handleGenerateContractException(
    String label,
    Object error,
    StackTrace stackTrace,
  ) async {
    _logCaughtError(label, error, stackTrace);

    try {
      final savedContractData = _normalizeGeneratedContractData(
        await _waitForSavedContractData(),
      );

      if (savedContractData != null) {
        if (!mounted) return;
        setState(() {
          _contractError = null;
          _contractData = savedContractData;
        });
        debugPrint(
          '$label ignored because contractData was saved successfully.',
        );
        return;
      }
    } on FirebaseException catch (syncError, syncStackTrace) {
      _logCaughtError(
        '$label post-error contract sync error',
        syncError,
        syncStackTrace,
      );
    } catch (syncError, syncStackTrace) {
      _logCaughtError(
        '$label post-error contract sync error',
        syncError,
        syncStackTrace,
      );
    }

    await _showLoggedError(label, error, stackTrace, updateContractError: true);
  }

  Map<String, dynamic>? _normalizeGeneratedContractData(
    Map<String, dynamic>? contractData,
  ) {
    if (contractData == null) return null;

    final normalizedContractData = Map<String, dynamic>.from(contractData);
    final approval = Map<String, dynamic>.from(
      (normalizedContractData['approval'] as Map?) ?? const {},
    );
    final freshStatus = (approval['contractStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    approval['clientApproved'] = false;
    approval['freelancerApproved'] = false;
    approval['contractStatus'] = freshStatus == 'pending_approval'
        ? 'pending_approval'
        : 'draft';
    approval.remove('termination');

    normalizedContractData['approval'] = approval;
    normalizedContractData['signatures'] = {
      'clientSignature': null,
      'freelancerSignature': null,
    };

    return normalizedContractData;
  }

  Future<void> _openContractTerminationAdminReviewSheet() async {
    final currentUserId = (_controller.currentUserId ?? '').trim();
    final otherPartyId = widget.otherUserId.trim();

    if (currentUserId.isEmpty || otherPartyId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User information is not available for this review.'),
        ),
      );
      return;
    }

    final detailsController = TextEditingController();
    final messenger = ScaffoldMessenger.maybeOf(context);
    String? selectedReason;
    String? sheetErrorMessage;
    bool detailsLimitReached = false;
    bool isSubmitting = false;
    bool isSheetActive = true;

    const reasonOptions = <Map<String, String>>[
      {'value': 'no_response', 'label': 'No response from the other party'},
      {
        'value': 'mismatched_delivery',
        'label': 'Delivered work does not match the agreement',
      },
      {
        'value': 'party_disagreement',
        'label': 'Disagreement between both parties',
      },
    ];

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              Future<void> submitReview() async {
                final normalizedReason = (selectedReason ?? '').trim();
                final isValidReason = reasonOptions.any(
                  (option) => option['value'] == normalizedReason,
                );

                if (!isValidReason) {
                  if (isSheetActive) {
                    setSheetState(() {
                      sheetErrorMessage = 'Choose a reason before submitting';
                    });
                  }
                  return;
                }

                if (isSheetActive) {
                  setSheetState(() {
                    sheetErrorMessage = null;
                    isSubmitting = true;
                  });
                }

                try {
                  final requestId = await _resolveRequestIdForContractReview();
                  final contractData = _contractData;
                  final meta = _asMap(contractData?['meta']);
                  final approval = _asMap(contractData?['approval']);
                  final contractId = (meta['contractId'] ?? requestId)
                      .toString()
                      .trim();
                  final contractStatus = (approval['contractStatus'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();

                  final currentUserDoc = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUserId)
                      .get();
                  final currentUserData =
                      currentUserDoc.data() ?? <String, dynamic>{};
                  final reporterName = _displayName(currentUserData, 'User');
                  final otherPartyName = widget.otherUserName.trim().isEmpty
                      ? 'User'
                      : widget.otherUserName.trim();

                  final reviewRef = FirebaseFirestore.instance
                      .collection('contract_reports')
                      .doc(
                        _contractTerminationReportDocumentId(
                          requestId: requestId,
                          reporterId: currentUserId,
                        ),
                      );

                  final existingReview = await reviewRef.get();
                  final isNewReview = !existingReview.exists;

                  await reviewRef.set({
                    'type': 'contract_review',
                    'reasonType': normalizedReason,
                    'reasonLabel': _terminationAdminReviewReasonLabel(
                      normalizedReason,
                    ),
                    'details': detailsController.text.trim(),
                    'requestId': requestId,
                    'contractId': contractId.isEmpty ? requestId : contractId,
                    'chatId': widget.chatId,
                    'reporterId': currentUserId,
                    'reporterName': reporterName,
                    'otherPartyId': otherPartyId,
                    'otherPartyName': otherPartyName,
                    'otherUserId': otherPartyId,
                    'contractStatus': contractStatus,
                    'status': 'requested',
                    'updatedAt': FieldValue.serverTimestamp(),
                    if (isNewReview) 'createdAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));

                  if (isNewReview) {
                    try {
                      await _createAdminContractReportNotification(
                        reviewId: reviewRef.id,
                      );
                    } catch (error) {
                      debugPrint(
                        'Create admin contract review notification error: '
                        '$error',
                      );
                    }
                  }

                  isSheetActive = false;
                  if (!sheetContext.mounted) return;
                  final sheetNavigator = Navigator.of(sheetContext);
                  if (sheetNavigator.canPop()) {
                    sheetNavigator.pop();
                  }

                  if (!mounted) return;
                  messenger
                    ?..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('Contract review request submitted'),
                      ),
                    );
                } catch (e) {
                  if (!mounted) return;
                  debugPrint('Termination contract review error: $e');
                  if (isSheetActive) {
                    setSheetState(() {
                      sheetErrorMessage =
                          'Failed to submit contract review: ${_friendlyErrorMessage(e)}';
                    });
                  }
                } finally {
                  if (isSheetActive) {
                    setSheetState(() {
                      isSubmitting = false;
                    });
                  }
                }
              }

              return SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 12,
                    right: 12,
                    bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
                  ),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Request Admin Review',
                          style: TextStyle(
                            color: primary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Choose the reason for requesting admin review.',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ...reasonOptions.map((option) {
                          final value = option['value']!;
                          final label = option['label']!;
                          final isSelected = selectedReason == value;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: isSubmitting
                                  ? null
                                  : () {
                                      setSheetState(() {
                                        selectedReason = value;
                                        sheetErrorMessage = null;
                                      });
                                    },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFFF2EAFB)
                                      : const Color(0xFFF8F6FC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? primary
                                        : primary.withOpacity(0.12),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      color: primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        if (sheetErrorMessage != null) ...[
                          const SizedBox(height: 2),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3F3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE8A0A0),
                              ),
                            ),
                            child: Text(
                              sheetErrorMessage!,
                              style: const TextStyle(
                                color: Color(0xFF9A3434),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        TextField(
                          controller: detailsController,
                          onChanged: (value) {
                            final hasReachedLimit =
                                value.length >= _adminReviewDetailsMaxLength;
                            if (detailsLimitReached == hasReachedLimit) {
                              return;
                            }

                            setSheetState(() {
                              detailsLimitReached = hasReachedLimit;
                            });
                          },
                          maxLength: _adminReviewDetailsMaxLength,
                          maxLengthEnforcement: MaxLengthEnforcement.enforced,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(
                              _adminReviewDetailsMaxLength,
                            ),
                          ],
                          maxLines: 4,
                          enabled: !isSubmitting,
                          decoration: InputDecoration(
                            labelText: 'Add details for the admin',
                            alignLabelWithHint: true,
                            filled: true,
                            fillColor: const Color(0xFFF8F6FC),
                            counterStyle: TextStyle(
                              color: detailsLimitReached
                                  ? const Color(0xFFC75A5A)
                                  : null,
                              fontWeight: detailsLimitReached
                                  ? FontWeight.w700
                                  : null,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: detailsLimitReached
                                    ? const Color(0xFFC75A5A)
                                    : primary.withOpacity(0.12),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: detailsLimitReached
                                    ? const Color(0xFFC75A5A)
                                    : primary.withOpacity(0.12),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(16),
                              ),
                              borderSide: BorderSide(
                                color: detailsLimitReached
                                    ? const Color(0xFFC75A5A)
                                    : primary,
                              ),
                            ),
                          ),
                        ),
                        if (detailsLimitReached) ...[
                          const SizedBox(height: 4),
                          const Text(
                            'Maximum character limit reached.',
                            style: TextStyle(
                              color: Color(0xFFC75A5A),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isSubmitting
                                    ? null
                                    : () {
                                        isSheetActive = false;
                                        Navigator.of(sheetContext).pop();
                                      },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primary,
                                  side: BorderSide(
                                    color: primary.withOpacity(0.20),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isSubmitting ? null : submitReview,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: isSubmitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Submit'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ).whenComplete(() {
        isSheetActive = false;
      });
    } finally {
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 350), () {
          detailsController.dispose();
        }),
      );
    }
  }

  Future<Map<String, dynamic>?> _loadTerminationContractReview() async {
    final reporterId = (_controller.currentUserId ?? '').trim();
    if (reporterId.isEmpty) return null;

    final requestId = await _resolveRequestIdForContractReview();
    final reviewDoc = await FirebaseFirestore.instance
        .collection('contract_reports')
        .doc(
          _contractTerminationReportDocumentId(
            requestId: requestId,
            reporterId: reporterId,
          ),
        )
        .get();

    if (!reviewDoc.exists) return null;

    return <String, dynamic>{'reviewId': reviewDoc.id, ...?reviewDoc.data()};
  }

  Future<void> _showTerminationContractReviewStatusDialog(
    Map<String, dynamic> reviewData,
  ) {
    final normalizedStatus = (reviewData['status'] ?? 'requested')
        .toString()
        .trim()
        .toLowerCase();
    final reasonLabel =
        (reviewData['reasonLabel'] ??
                _contractReviewReasonLabel(
                  (reviewData['reasonType'] ?? '').toString(),
                ))
            .toString();
    final details = (reviewData['details'] ?? '').toString().trim();
    final statusTitle = normalizedStatus == 'resolved'
        ? 'Contract Review Resolved'
        : normalizedStatus == 'under_review'
        ? 'Contract Review In Progress'
        : 'Contract Review Requested';

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(statusTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                normalizedStatus == 'resolved'
                    ? 'This contract review has already been resolved.'
                    : 'Your contract review request has already been submitted.',
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Reason: $reasonLabel',
                style: const TextStyle(color: Colors.black87, fontSize: 12.5),
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Details: $details',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: primary,
                side: BorderSide(color: primary.withOpacity(0.24)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openTerminationContractReviewSheet() async {
    final currentUserId = (_controller.currentUserId ?? '').trim();
    if (currentUserId.isEmpty) {
      await _showErrorDialog('Current user not found');
      return;
    }

    final normalizedOtherUserId = widget.otherUserId.trim();
    if (normalizedOtherUserId.isEmpty) {
      await _showErrorDialog('The other user is not available');
      return;
    }

    const options = <Map<String, String>>[
      {'value': 'no_response', 'label': 'No response from the other party'},
      {
        'value': 'mismatched_delivery',
        'label': 'Delivered work does not match the agreement',
      },
      {
        'value': 'party_disagreement',
        'label': 'Disagreement between both parties',
      },
    ];

    final detailsController = TextEditingController();
    final messenger = ScaffoldMessenger.maybeOf(context);
    String selectedReason = '';
    String? sheetErrorMessage;
    bool detailsLimitReached = false;
    bool isSubmitting = false;
    bool isSheetActive = true;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetBodyContext, setSheetState) {
              final bottomInset = MediaQuery.of(
                sheetBodyContext,
              ).viewInsets.bottom;

              Future<void> submitReviewRequest() async {
                final normalizedReason = selectedReason.trim();
                final isValidReason = options.any(
                  (option) => option['value'] == normalizedReason,
                );

                if (!isValidReason) {
                  if (isSheetActive) {
                    setSheetState(() {
                      sheetErrorMessage = 'Choose a reason before submitting';
                    });
                  }
                  return;
                }

                if (isSheetActive) {
                  setSheetState(() {
                    sheetErrorMessage = null;
                    isSubmitting = true;
                  });
                }

                try {
                  final requestId = await _resolveRequestIdForContractReview();
                  final contractData = _contractData;
                  final meta = _asMap(contractData?['meta']);
                  final approval = _asMap(contractData?['approval']);
                  final contractId = (meta['contractId'] ?? requestId)
                      .toString()
                      .trim();
                  final contractStatus = (approval['contractStatus'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();
                  final reviewRef = FirebaseFirestore.instance
                      .collection('contract_reports')
                      .doc(
                        _contractTerminationReportDocumentId(
                          requestId: requestId,
                          reporterId: currentUserId,
                        ),
                      );
                  final existingReview = await reviewRef.get();

                  final payload = <String, dynamic>{
                    'type': 'contract_review',
                    'source': 'contract_termination',
                    'reasonType': normalizedReason,
                    'reasonLabel': _contractReviewReasonLabel(normalizedReason),
                    'details': detailsController.text.trim(),
                    'requestId': requestId,
                    'contractId': contractId.isEmpty ? requestId : contractId,
                    'chatId': widget.chatId,
                    'reporterId': currentUserId,
                    'reportedUserId': normalizedOtherUserId,
                    'otherUserId': normalizedOtherUserId,
                    'contractStatus': contractStatus,
                    'status': 'requested',
                    'updatedAt': FieldValue.serverTimestamp(),
                  };

                  if (!existingReview.exists) {
                    payload['createdAt'] = FieldValue.serverTimestamp();
                  }

                  await reviewRef.set(payload, SetOptions(merge: true));

                  if (!existingReview.exists) {
                    try {
                      await _createAdminContractReportNotification(
                        reviewId: reviewRef.id,
                      );
                    } catch (error) {
                      debugPrint(
                        'Create admin contract review notification error: '
                        '$error',
                      );
                    }
                  }

                  if (!mounted) return;
                  isSheetActive = false;
                  if (!sheetContext.mounted) return;
                  final sheetNavigator = Navigator.of(sheetContext);
                  if (sheetNavigator.canPop()) {
                    sheetNavigator.pop();
                  }
                  if (!mounted) return;
                  messenger
                    ?..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('Contract review request submitted'),
                      ),
                    );
                } catch (e) {
                  if (!mounted) return;
                  debugPrint('Termination contract review error: $e');
                  if (isSheetActive) {
                    setSheetState(() {
                      sheetErrorMessage =
                          'Failed to submit contract review: ${_friendlyErrorMessage(e)}';
                    });
                  }
                } finally {
                  if (isSheetActive) {
                    setSheetState(() {
                      isSubmitting = false;
                    });
                  }
                }
              }

              return SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + bottomInset),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD8D3E5),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Request Admin Review',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Choose the reason for requesting admin review.',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ...options.map((option) {
                          final value = option['value']!;
                          final label = option['label']!;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selectedReason == value
                                    ? primary.withOpacity(0.26)
                                    : _chatPanelBorder,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: isSubmitting
                                  ? null
                                  : () {
                                      setSheetState(() {
                                        selectedReason = value;
                                        sheetErrorMessage = null;
                                      });
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Radio<String>(
                                      value: value,
                                      groupValue: selectedReason,
                                      onChanged: isSubmitting
                                          ? null
                                          : (nextValue) {
                                              setSheetState(() {
                                                selectedReason =
                                                    nextValue ?? '';
                                                sheetErrorMessage = null;
                                              });
                                            },
                                      activeColor: primary,
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.support_agent_outlined,
                                      size: 18,
                                      color: primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        if (sheetErrorMessage != null) ...[
                          const SizedBox(height: 2),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3F3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE8A0A0),
                              ),
                            ),
                            child: Text(
                              sheetErrorMessage!,
                              style: const TextStyle(
                                color: Color(0xFF9A3434),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextField(
                          controller: detailsController,
                          onChanged: (value) {
                            final hasReachedLimit =
                                value.length >= _adminReviewDetailsMaxLength;
                            if (detailsLimitReached == hasReachedLimit) {
                              return;
                            }

                            setSheetState(() {
                              detailsLimitReached = hasReachedLimit;
                            });
                          },
                          maxLength: _adminReviewDetailsMaxLength,
                          maxLengthEnforcement: MaxLengthEnforcement.enforced,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(
                              _adminReviewDetailsMaxLength,
                            ),
                          ],
                          maxLines: 4,
                          minLines: 3,
                          enabled: !isSubmitting,
                          decoration: InputDecoration(
                            labelText: 'Add details for the admin',
                            alignLabelWithHint: true,
                            filled: true,
                            fillColor: _chatPanelSurface,
                            contentPadding: const EdgeInsets.all(12),
                            counterStyle: TextStyle(
                              color: detailsLimitReached
                                  ? const Color(0xFFC75A5A)
                                  : null,
                              fontWeight: detailsLimitReached
                                  ? FontWeight.w700
                                  : null,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: _chatPanelBorder,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: detailsLimitReached
                                    ? const Color(0xFFC75A5A)
                                    : _chatPanelBorder,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: detailsLimitReached
                                    ? const Color(0xFFC75A5A)
                                    : primary,
                              ),
                            ),
                          ),
                        ),
                        if (detailsLimitReached) ...[
                          const SizedBox(height: 4),
                          const Text(
                            'Maximum character limit reached.',
                            style: TextStyle(
                              color: Color(0xFFC75A5A),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isSubmitting
                                ? null
                                : submitReviewRequest,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Submit Review Request'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ).whenComplete(() {
        isSheetActive = false;
      });
    } finally {
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 350), () {
          detailsController.dispose();
        }),
      );
    }
  }

  Future<void> _handleTerminationContractAdminReviewAction() async {
    try {
      final existingReview = await _loadTerminationContractReview();

      if (existingReview != null) {
        await _showTerminationContractReviewStatusDialog(existingReview);
        return;
      }

      await _openTerminationContractReviewSheet();
    } catch (e) {
      if (!mounted) return;
      debugPrint('Handle termination contract review action error: $e');
      unawaited(_showErrorDialog(_friendlyErrorMessage(e)));
    }
  }

  IconData _contractProgressIcon(String stage) {
    switch (_normalizeContractProgressStage(stage)) {
      case 'processing':
        return Icons.sync_rounded;
      case 'under_review':
        return Icons.rate_review_rounded;
      case 'completed':
        return Icons.task_alt_rounded;
      case 'started':
      default:
        return Icons.play_circle_outline_rounded;
    }
  }

  Future<void> _updateContractProgress(String stage) async {
    final contractData = _contractData;
    if (contractData == null) return;

    final normalizedStage = _normalizeContractProgressStage(stage);
    final currentProgress = _asMap(contractData['progressData']);
    if (_normalizeContractProgressStage(currentProgress['stage']) ==
        normalizedStage) {
      return;
    }

    setState(() {
      _isSavingContract = true;
    });

    try {
      final updatedContractData = Map<String, dynamic>.from(contractData);
      final updatedProgressData = _asMap(updatedContractData['progressData']);

      updatedProgressData['stage'] = normalizedStage;
      updatedProgressData['updatedAt'] = DateTime.now().toIso8601String();
      updatedProgressData['updatedBy'] = _currentUserRole();
      updatedContractData['progressData'] = updatedProgressData;

      await _saveWorkflowContractData(
        updatedContractData,
        logLabel: 'Update contract progress',
      );

      if (!mounted) return;

      _showSuccessSnackBar(
        'Progress updated to ${_contractProgressLabel(normalizedStage)}',
      );
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError('Update progress error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError('Update progress error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError('Update progress error', error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError('Update progress error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError('Update progress error', error, stackTrace);
    } catch (error, stackTrace) {
      await _showLoggedError('Update progress error', error, stackTrace);
    } finally {
      if (!mounted) return;

      setState(() {
        _isSavingContract = false;
      });
    }
  }

  Widget _buildContractProgressSection({
    required String contractStatus,
    required String currentUserRole,
    bool showSectionTitle = true,
    Color? surfaceColor,
  }) {
    final contractData = _contractData;
    if (contractData == null) return const SizedBox.shrink();

    final shouldShowProgress =
        contractStatus == 'approved' ||
        contractStatus == 'completed' ||
        contractStatus == 'termination_pending' ||
        contractStatus == 'terminated';

    if (!shouldShowProgress) return const SizedBox.shrink();

    final progressData = _asMap(contractData['progressData']);
    final currentStage = _normalizeContractProgressStage(progressData['stage']);
    final currentStageIndex = _contractProgressIndex(currentStage);
    final currentStageColor = _contractProgressColor(currentStage);
    final showClientTimeline = currentUserRole == 'client';
    final deliveryData = _currentDeliveryData(contractData);
    final paymentData = _currentPaymentData(contractData);
    final deliveryStatus = _normalizeDeliveryStatus(deliveryData['status']);
    final paymentStatus = (paymentData['paymentStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final isPaidDelivered =
        deliveryStatus == 'paid_delivered' ||
        _isCompletedPaymentStatus(paymentStatus);
    final isLocked = isPaidDelivered || contractStatus == 'completed';

    final progressContent = _buildChatPanelSurface(
      padding: const EdgeInsets.all(12),
      backgroundColor: surfaceColor ?? _chatPanelSurface,
      borderColor: currentStageColor.withOpacity(0.14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showClientTimeline)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _contractProgressStages.asMap().entries.map((
                      entry,
                    ) {
                      final index = entry.key;
                      final stage = entry.value;
                      final isCurrent = index == currentStageIndex;
                      final isPassed = index < currentStageIndex;
                      final isReached = index <= currentStageIndex;
                      final completedLineColor = const Color(0xFF66BB6A);
                      final circleColor = isReached
                          ? completedLineColor
                          : const Color(0xFFE6E6E6);
                      final textColor = isCurrent
                          ? Colors.black87
                          : isPassed
                          ? Colors.black87
                          : Colors.black54;

                      return Expanded(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                if (index > 0)
                                  Expanded(
                                    child: Container(
                                      height: 3,
                                      color: isReached
                                          ? completedLineColor
                                          : const Color(0xFFE6E6E6),
                                    ),
                                  ),
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: circleColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isReached
                                          ? circleColor
                                          : const Color(0xFFD6D6D6),
                                    ),
                                  ),
                                  child: isReached
                                      ? const Icon(
                                          Icons.check_rounded,
                                          size: 11,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                                if (index < _contractProgressStages.length - 1)
                                  Expanded(
                                    child: Container(
                                      height: 3,
                                      color: isPassed
                                          ? completedLineColor
                                          : const Color(0xFFE6E6E6),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _contractProgressLabel(stage),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            )
          else
            Column(
              children: _contractProgressStages.asMap().entries.map((entry) {
                final stage = entry.value;
                final stageIndex = entry.key;
                final isCurrent = stage == currentStage;
                final isCompleted = stageIndex <= currentStageIndex;
                final completedCheckColor = const Color(0xFF66BB6A);

                return Padding(
                  padding: EdgeInsets.only(
                    bottom: stageIndex == _contractProgressStages.length - 1
                        ? 0
                        : 10,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: (_isSavingContract || isLocked)
                        ? null
                        : () => _updateContractProgress(stage),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      decoration: BoxDecoration(
                        color: _chatPanelBackground,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isCurrent
                              ? const Color(0xFFBDBDBD)
                              : const Color(0xFFE0E0E0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: isCompleted
                                  ? completedCheckColor
                                  : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isCompleted
                                    ? completedCheckColor
                                    : const Color(0xFFBDBDBD),
                              ),
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 13,
                              color: isCompleted
                                  ? Colors.white
                                  : const Color(0xFFBDBDBD),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _contractProgressLabel(stage),
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );

    if (!showSectionTitle) {
      return progressContent;
    }

    return _buildContractSection(
      title: 'Work Progress',
      children: [progressContent],
    );
  }

  Widget _buildInlineWorkProgressHeader() {
    final progressData = _asMap(_contractData?['progressData']);
    final currentStage = _normalizeContractProgressStage(progressData['stage']);

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _chatPanelSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _chatPanelBorder),
          ),
          child: const Icon(Icons.timeline_rounded, size: 18, color: primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Work Progress',
                style: TextStyle(
                  color: primary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _contractProgressLabel(currentStage),
                style: TextStyle(
                  color: Colors.black.withOpacity(0.62),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPinnedApprovedContractCard({
    EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(12, 8, 12, 8),
    double? expandedBodyMaxHeight,
    bool fillAvailableHeight = false,
  }) {
    final contractData = _contractData;
    if (contractData == null) return const SizedBox.shrink();

    final approval = _asMap(contractData['approval']);
    final contractStatus = (approval['contractStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    final deliveryData = _asMap(contractData['deliveryData']);
    final paymentData = _asMap(contractData['paymentData']);
    final deliveryStatus = _normalizeDeliveryStatus(deliveryData['status']);
    final paymentStatus = (paymentData['paymentStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final isPaidDelivered =
        deliveryStatus == 'paid_delivered' ||
        _isCompletedPaymentStatus(paymentStatus);

    if (contractStatus != 'approved' &&
        contractStatus != 'completed' &&
        !isPaidDelivered) {
      return const SizedBox.shrink();
    }

    final meta = _asMap(contractData['meta']);
    final service = _asMap(contractData['service']);
    final payment = _asMap(contractData['payment']);
    final timeline = _asMap(contractData['timeline']);
    final description = (service['description'] ?? '').toString().trim();
    final amount = (payment['amount'] ?? '').toString().trim();
    final deadline = (timeline['deadline'] ?? '').toString().trim();

    final isCompleted = contractStatus == 'completed' || isPaidDelivered;
    final canDownloadFinalWork =
        deliveryStatus == 'paid_delivered' ||
        contractStatus == 'completed' ||
        _isCompletedPaymentStatus(paymentStatus);
    final isLocked = isPaidDelivered || contractStatus == 'completed';
    final isClientView = _currentUserRole() == 'client';
    final approvedPanelBody = Column(
      mainAxisSize: fillAvailableHeight ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: _buildApprovedPanelTabs(),
        ),
        const SizedBox(height: 12),
        if (fillAvailableHeight)
          Expanded(
            child: _buildApprovedPanelTabContent(
              expandedBodyMaxHeight: expandedBodyMaxHeight ?? 320,
            ),
          )
        else
          _buildApprovedPanelTabContent(
            expandedBodyMaxHeight: expandedBodyMaxHeight ?? 320,
          ),
      ],
    );
    return Container(
      width: double.infinity,
      margin: margin,
      decoration: _chatPanelDecoration(
        backgroundColor: _chatPanelShellBackground,
        borderColor: _chatPanelBorder,
        radius: 18,
      ),
      child: Column(
        mainAxisSize: fillAvailableHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: _pinnedPanelHeaderMinHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Service Workspace',
                          style: TextStyle(
                            color: primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? const Color(0xFF7C3AED).withOpacity(0.12)
                                : const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isCompleted ? 'Completed' : 'Approved',
                            style: TextStyle(
                              color: isCompleted
                                  ? const Color(0xFF7C3AED)
                                  : const Color(0xFF2E7D32),
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: _chatPanelDecoration(
                      backgroundColor: _chatPanelSurface,
                      borderColor: _chatPanelBorder,
                      radius: 999,
                      showShadow: false,
                    ),
                    child: IconButton(
                      onPressed: _isSwitchingPanels
                          ? null
                          : _toggleApprovedContractPanelSize,
                      icon: Icon(
                        _isApprovedContractPanelExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                      ),
                      color: primary,
                      tooltip: _isApprovedContractPanelExpanded
                          ? 'Collapse'
                          : 'Expand',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isApprovedContractPanelExpanded) ...[
            Divider(height: 1, color: primary.withOpacity(0.08)),
            if (fillAvailableHeight)
              Expanded(child: approvedPanelBody)
            else
              approvedPanelBody,
          ],
        ],
      ),
    );
  }

  Widget _buildPinnedFreelancerProgressCard({
    EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(12, 0, 12, 8),
    double? expandedBodyMaxHeight,
  }) {
    final contractData = _contractData;
    if (contractData == null) return const SizedBox.shrink();
    if (_currentUserRole() != 'freelancer') {
      return const SizedBox.shrink();
    }

    final approval = _asMap(contractData['approval']);
    final contractStatus = (approval['contractStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (contractStatus != 'approved' && contractStatus != 'completed') {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: margin,
      decoration: _chatPanelDecoration(
        backgroundColor: _chatPanelShellBackground,
        borderColor: _chatPanelBorder,
        radius: 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: _pinnedPanelHeaderMinHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Text(
                      'Work Progress',
                      style: TextStyle(
                        color: primary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    decoration: _chatPanelDecoration(
                      backgroundColor: _chatPanelSurface,
                      borderColor: _chatPanelBorder,
                      radius: 999,
                      showShadow: false,
                    ),
                    child: IconButton(
                      onPressed: _isSwitchingPanels
                          ? null
                          : _toggleFreelancerProgressPanel,
                      icon: Icon(
                        _isFreelancerProgressPanelExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                      ),
                      color: primary,
                      tooltip: _isFreelancerProgressPanelExpanded
                          ? 'Collapse'
                          : 'Expand',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isFreelancerProgressPanelExpanded) ...[
            Divider(height: 1, color: primary.withOpacity(0.08)),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: expandedBodyMaxHeight ?? double.infinity,
              ),
              child: Scrollbar(
                controller: _freelancerProgressPanelScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _freelancerProgressPanelScrollController,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildContractProgressSection(
                      contractStatus: contractStatus,
                      currentUserRole: _currentUserRole(),
                      showSectionTitle: false,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPinnedFreelancerPanelsRow() {
    final maxExpandedBodyHeight = MediaQuery.of(context).size.height * 0.28;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _buildPinnedApprovedContractCard(
              margin: EdgeInsets.zero,
              expandedBodyMaxHeight: maxExpandedBodyHeight,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildPinnedFreelancerProgressCard(
              margin: EdgeInsets.zero,
              expandedBodyMaxHeight: maxExpandedBodyHeight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedApprovedContractScrollable({
    bool overlayExpandedPanel = false,
  }) {
    if (!overlayExpandedPanel) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: _buildPinnedApprovedContractCard(margin: EdgeInsets.zero),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = MediaQuery.of(context).size.height;
        final availableHeight = constraints.maxHeight;
        final cappedPanelHeight = availableHeight > screenHeight * 0.95
            ? screenHeight * 0.95
            : availableHeight;
        final maxPanelHeight = cappedPanelHeight > 8
            ? cappedPanelHeight - 8
            : cappedPanelHeight;
        final maxExpandedBodyHeight =
            maxPanelHeight - _pinnedPanelHeaderMinHeight - 18;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: maxPanelHeight,
              child: _buildPinnedApprovedContractCard(
                margin: EdgeInsets.zero,
                expandedBodyMaxHeight: maxExpandedBodyHeight,
                fillAvailableHeight: true,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMoyasarPayment({int? milestoneIndex}) async {
    final contractData = _contractData;
    if (contractData == null) return;
    if (await _showBlockedActionAndStopIfNeeded()) return;

    final milestones = _milestones(contractData);
    final resolvedMilestoneIndex =
        milestoneIndex ?? _currentMilestoneIndex(contractData);
    final targetMilestone =
        (milestones.isNotEmpty && resolvedMilestoneIndex != null)
        ? milestones[resolvedMilestoneIndex]
        : null;

    // Milestone-schedule contracts: charge exactly the target milestone's
    // share, not the whole contract. Legacy contracts with no milestones
    // fall back to today's single lump-sum amount.
    final amountText = targetMilestone != null
        ? (targetMilestone['amount'] ?? '').toString().trim()
        : (_asMap(contractData['payment'])['amount'] ?? '').toString().trim();
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      await _showErrorDialog('Invalid payment amount');
      return;
    }

    if (targetMilestone != null) {
      final milestoneStatus =
          (targetMilestone['status'] ?? '').toString().trim().toLowerCase();
      final isPayable = targetMilestone['deliveryRequired'] == false
          ? milestoneStatus == 'pending'
          : milestoneStatus == 'approved';
      if (!isPayable) {
        await _showErrorDialog('This milestone is not ready for payment yet.');
        return;
      }
      if (resolvedMilestoneIndex! > 0) {
        final previousStatus = (milestones[resolvedMilestoneIndex - 1]['status'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (previousStatus != 'paid') {
          await _showErrorDialog(
            'A previous milestone has not been paid yet.',
          );
          return;
        }
      }
    }

    final amountInHalalas = (amount * 100).round();
    final paymentDescription = targetMilestone != null
        ? (targetMilestone['label'] ?? 'Contract Payment').toString()
        : 'Contract Payment';

    final paymentConfig = PaymentConfig(
      publishableApiKey: moyasarPublishableKey,
      amount: amountInHalalas,
      description: paymentDescription,
    );

    final paymentCompleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (pageContext) => Scaffold(
          appBar: AppBar(
            title: const Text('Payment'),
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          backgroundColor: Colors.white,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: kIsWeb
                ? WebMoyasarCardForm(
                    config: paymentConfig,
                    onPaymentResult: (result) async {
                      if (result is PaymentResponse &&
                          result.status == PaymentStatus.paid) {
                        try {
                          await _verifyPayment(
                            result.id,
                            milestoneIndex: targetMilestone != null
                                ? resolvedMilestoneIndex
                                : null,
                          );

                          if (pageContext.mounted) {
                            Navigator.of(pageContext).pop(true);
                          }
                        } catch (error, stackTrace) {
                          _logCaughtError(
                            'Verify payment error',
                            error,
                            stackTrace,
                          );
                          if (pageContext.mounted) {
                            await _showErrorDialog(_friendlyErrorMessage(error));
                          }
                        }
                      } else {
                        await _showErrorDialog('Payment failed');
                      }
                    },
                    onInitiated: (result) async {
                      final source = result.source;
                      final transactionUrl =
                          source is CardPaymentResponseSource
                              ? (source.transactionUrl ?? '')
                              : '';
                      if (transactionUrl.isEmpty) {
                        await _showErrorDialog('Payment failed');
                        return;
                      }

                      await launchUrl(
                        Uri.parse(transactionUrl),
                        webOnlyWindowName: '_blank',
                      );

                      if (!pageContext.mounted) return;

                      final confirmed = await showDialog<bool>(
                        context: pageContext,
                        barrierDismissible: false,
                        builder: (_) => PaymentConfirmationDialog(
                          verify: () => _verifyPayment(
                            result.id,
                            milestoneIndex: targetMilestone != null
                                ? resolvedMilestoneIndex
                                : null,
                          ),
                        ),
                      );

                      if (confirmed == true) {
                        if (pageContext.mounted) {
                          Navigator.of(pageContext).pop(true);
                        }
                      } else if (pageContext.mounted) {
                        await _showErrorDialog(
                          'Payment was not confirmed. Please try again.',
                        );
                      }
                    },
                  )
                : CreditCard(
                    config: paymentConfig,
                    onPaymentResult: (result) async {
                      if (result is PaymentResponse &&
                          result.status == PaymentStatus.paid) {
                        try {
                          await _verifyPayment(
                            result.id,
                            milestoneIndex: targetMilestone != null
                                ? resolvedMilestoneIndex
                                : null,
                          );

                          if (pageContext.mounted) {
                            Navigator.of(pageContext).pop(true);
                          }
                        } catch (error, stackTrace) {
                          _logCaughtError('Verify payment error', error, stackTrace);
                          if (pageContext.mounted) {
                            await _showErrorDialog(_friendlyErrorMessage(error));
                          }
                        }
                      } else {
                        await _showErrorDialog('Payment failed');
                      }
                    },
                  ),
          ),
        ),
      ),
    );

    if (paymentCompleted == true) {
      await _runNonBlockingSecondaryAction(
        'Payment success contract refresh',
        _refreshContractDataFromSource,
      );
      if (!mounted) return;
      _showSuccessSnackBar('Payment completed successfully.');
    }
  }

  Future<void> _openTerminationCompensationPayment() async {
    if (await _showBlockedActionAndStopIfNeeded()) return;

    final compensationAmount = _terminationCompensationAmount();
    if (compensationAmount == null || compensationAmount <= 0) {
      await _showErrorDialog('Invalid compensation amount');
      return;
    }

    final amountInHalalas = (compensationAmount * 100).round();
    final paymentConfig = PaymentConfig(
      publishableApiKey: moyasarPublishableKey,
      amount: amountInHalalas,
      description: 'Termination Compensation (20%)',
    );

    final paymentCompleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (pageContext) => Scaffold(
          appBar: AppBar(
            title: const Text('Termination Payment'),
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          backgroundColor: Colors.white,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFD54F)),
                  ),
                  child: Text(
                    'Termination with 20% compensation: ${_terminationCompensationText()}',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: kIsWeb
                      ? WebMoyasarCardForm(
                          config: paymentConfig,
                          onPaymentResult: (result) async {
                            if (result is PaymentResponse &&
                                result.status == PaymentStatus.paid) {
                              try {
                                await _verifyTerminationCompensationPayment(
                                  result.id,
                                );

                                if (pageContext.mounted) {
                                  Navigator.of(pageContext).pop(true);
                                }
                              } catch (error, stackTrace) {
                                _logCaughtError(
                                  'Verify termination payment error',
                                  error,
                                  stackTrace,
                                );
                                if (pageContext.mounted) {
                                  await _showErrorDialog(
                                    _friendlyErrorMessage(error),
                                  );
                                }
                              }
                            } else {
                              await _showErrorDialog('Payment failed');
                            }
                          },
                          onInitiated: (result) async {
                            final source = result.source;
                            final transactionUrl =
                                source is CardPaymentResponseSource
                                    ? (source.transactionUrl ?? '')
                                    : '';
                            if (transactionUrl.isEmpty) {
                              await _showErrorDialog('Payment failed');
                              return;
                            }

                            await launchUrl(
                              Uri.parse(transactionUrl),
                              webOnlyWindowName: '_blank',
                            );

                            if (!pageContext.mounted) return;

                            final confirmed = await showDialog<bool>(
                              context: pageContext,
                              barrierDismissible: false,
                              builder: (_) => PaymentConfirmationDialog(
                                verify: () =>
                                    _verifyTerminationCompensationPayment(
                                  result.id,
                                ),
                              ),
                            );

                            if (confirmed == true) {
                              if (pageContext.mounted) {
                                Navigator.of(pageContext).pop(true);
                              }
                            } else if (pageContext.mounted) {
                              await _showErrorDialog(
                                'Payment was not confirmed. Please try again.',
                              );
                            }
                          },
                        )
                      : CreditCard(
                          config: paymentConfig,
                          onPaymentResult: (result) async {
                            if (result is PaymentResponse &&
                                result.status == PaymentStatus.paid) {
                              try {
                                await _verifyTerminationCompensationPayment(
                                  result.id,
                                );

                                if (pageContext.mounted) {
                                  Navigator.of(pageContext).pop(true);
                                }
                              } catch (error, stackTrace) {
                                _logCaughtError(
                                  'Verify termination payment error',
                                  error,
                                  stackTrace,
                                );
                                if (pageContext.mounted) {
                                  await _showErrorDialog(
                                    _friendlyErrorMessage(error),
                                  );
                                }
                              }
                            } else {
                              await _showErrorDialog('Payment failed');
                            }
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (paymentCompleted == true) {
      await _runNonBlockingSecondaryAction(
        'Termination payment success contract refresh',
        _refreshContractDataFromSource,
      );
      if (!mounted) return;
      _showSuccessSnackBar('Termination payment completed successfully.');
    }
  }

  Future<void> _verifyPayment(String paymentId, {int? milestoneIndex}) async {
    await _accountAccessService.ensureCurrentUserNotBlocked();

    final chatDoc = await FirebaseFirestore.instance
        .collection('chat')
        .doc(widget.chatId)
        .get();

    final chatData = chatDoc.data();
    final requestId = _extractRequestId(chatData);

    debugPrint('Verify payment paymentId: $paymentId');
    debugPrint('Verify payment requestId: $requestId');
    debugPrint('Verify payment milestoneIndex: $milestoneIndex');

    final response = await _postContractApi(
      endpointPath: 'verify-payment',
      body: {
        'paymentId': paymentId,
        'requestId': requestId,
        'paidBy': _currentUserRole(),
        if (milestoneIndex != null) 'milestoneIndex': milestoneIndex,
      },
      logLabel: 'Verify payment',
    );

    final decoded = _tryDecodeResponseBodyAsMap(
      response,
      actionLabel: 'Verify payment',
    );

    if (!_isSuccessfulStatusCode(response.statusCode)) {
      final errorMessage = _responseErrorMessage(decoded, response.statusCode);
      throw Exception(errorMessage);
    }

    final responseReportedFailure =
        decoded['success'] is bool && decoded['success'] == false;
    if (responseReportedFailure) {
      final errorMessage = _responseErrorMessage(decoded, response.statusCode);
      throw Exception(errorMessage);
    }

    Map<String, dynamic>? normalizedContractData;
    if (decoded.isNotEmpty) {
      normalizedContractData = await _resolveContractDataForUiSync(
        actionLabel: 'Verify payment',
        responseData: decoded,
      );
    }

    if (normalizedContractData != null && mounted) {
      setState(() {
        _contractData = normalizedContractData;
      });
    }

    await _runNonBlockingSecondaryAction(
      'Verify payment notification',
      () => _createContractNotification(
        type: 'contract_payment_completed',
        actionText: 'The client completed the payment successfully',
        requestId: requestId,
        chatData: chatData,
        contractData: normalizedContractData,
      ),
    );

    await _runNonBlockingSecondaryAction(
      'Verify payment contract refresh',
      _refreshContractDataFromSource,
    );
  }

  Future<void> _verifyTerminationCompensationPayment(String paymentId) async {
    await _accountAccessService.ensureCurrentUserNotBlocked();

    final chatDoc = await FirebaseFirestore.instance
        .collection('chat')
        .doc(widget.chatId)
        .get();

    final chatData = chatDoc.data();
    final requestId = _extractRequestId(chatData);

    final response = await _postContractApi(
      endpointPath: 'verify-termination-payment',
      body: {
        'paymentId': paymentId,
        'requestId': requestId,
        'paidBy': _currentUserRole(),
      },
      logLabel: 'Verify termination payment',
    );

    final decoded = _tryDecodeResponseBodyAsMap(
      response,
      actionLabel: 'Verify termination payment',
    );

    if (!_isSuccessfulStatusCode(response.statusCode)) {
      final errorMessage = _responseErrorMessage(decoded, response.statusCode);
      throw Exception(errorMessage);
    }

    final responseReportedFailure =
        decoded['success'] is bool && decoded['success'] == false;
    if (responseReportedFailure) {
      final errorMessage = _responseErrorMessage(decoded, response.statusCode);
      throw Exception(errorMessage);
    }

    Map<String, dynamic>? normalizedContractData;
    if (decoded.isNotEmpty) {
      normalizedContractData = await _resolveContractDataForUiSync(
        actionLabel: 'Verify termination payment',
        responseData: decoded,
      );
    }

    if (normalizedContractData != null && mounted) {
      setState(() {
        _contractData = normalizedContractData;
      });
    }

    await _runNonBlockingSecondaryAction(
      'Verify termination payment notification',
      () => _createContractNotification(
        type: 'contract_terminated',
        actionText: 'terminated the contract with 20% compensation',
        requestId: requestId,
        chatData: chatData,
        contractData: normalizedContractData,
      ),
    );

    await _runNonBlockingSecondaryAction(
      'Verify termination payment contract refresh',
      _refreshContractDataFromSource,
    );
  }

  Widget _buildDeliverySection(String contractStatus) {
    final contractData = _contractData;
    if (contractData == null) return const SizedBox.shrink();
    if (contractStatus != 'approved' && contractStatus != 'completed') {
      return const SizedBox.shrink();
    }

    // Milestone-schedule contracts: milestone 1 ("on signing") has no
    // deliverable at all — it's a payment-only gate — so there is nothing
    // to render in a "Submitted Work" card for it.
    final currentMilestone = _currentMilestoneOrNull(contractData);
    if (currentMilestone != null && currentMilestone['deliveryRequired'] == false) {
      return _buildChatPanelContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (currentMilestone['label'] ?? 'Milestone 1').toString(),
              style: _chatPanelTitleStyle.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'This milestone has no deliverable — it is due on contract signing. Payment unlocks the next milestone.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    final deliveryData = _currentDeliveryData(contractData);
    final progressData = _asMap(contractData['progressData']);
    final currentStage = _normalizeContractProgressStage(progressData['stage']);
    final deliveryStatus = _normalizeDeliveryStatus(deliveryData['status']);
    final imageItems = _deliveryImageItems(deliveryData);
    final fileItems = _deliveryFileItems(deliveryData);
    final linkUrls = _deliveryLinkUrls(deliveryData);
    final notes = _deliveryNotes(deliveryData);
    final isClient = _currentUserRole() == 'client';
    final isFreelancer = _currentUserRole() == 'freelancer';
    final canSubmit = _canFreelancerSubmitWork(contractStatus);
    final hasSubmittedWork = _hasSubmittedWorkContent(deliveryData);
    final isApproved = _isDeliveryApproved(deliveryStatus);
    final canAccessFinalDelivery = _currentUserCanAccessFinalDelivery(
      contractData,
    );
    final restrictSubmittedWork = _shouldRestrictSubmittedWork(contractData);
    final submitButtonLabel = deliveryStatus == 'submitted'
        ? 'Update Submission'
        : deliveryStatus == 'changes_requested'
        ? 'Update Submission'
        : 'Submit Work';

    return _buildChatPanelContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Submitted Work',
            style: _chatPanelTitleStyle.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 10),
          if (!hasSubmittedWork) ...[
            const Text(
              'No work has been submitted yet.',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (isFreelancer &&
              !canSubmit &&
              (deliveryStatus == 'not_submitted' ||
                  deliveryStatus == 'changes_requested')) ...[
            Text(
              currentStage == 'completed'
                  ? 'Submission is locked right now.'
                  : 'Work delivery will be enabled when progress reaches Completed.',
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: primary.withOpacity(0.35),
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(submitButtonLabel),
              ),
            ),
          ],
          if (canSubmit) ...[
            Text(
              deliveryStatus == 'submitted'
                  ? 'You can update the submitted work while it is awaiting client review.'
                  : currentStage == 'completed'
                  ? 'You can now submit the completed work for client review.'
                  : 'You can submit the work now. This will also mark progress as Completed for client review.',
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSavingContract ? null : _submitDeliveryWork,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(submitButtonLabel),
              ),
            ),
          ],
          if (imageItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: imageItems.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final imageItem = imageItems[index];

                  return GestureDetector(
                    onTap: !imageItem.hasAccessibleUrl
                        ? null
                        : () => _openDeliveryImageItem(
                            imageItem,
                            previewOnly: restrictSubmittedWork,
                          ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _buildDeliveryImageThumbnail(
                            imageItem,
                            previewOnly: restrictSubmittedWork,
                          ),
                        ),
                        if (restrictSubmittedWork)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.68),
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(12),
                                  bottomRight: Radius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Preview only - Payment required - Saneea',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          if (restrictSubmittedWork && hasSubmittedWork) ...[
            const SizedBox(height: 10),
            const Text(
              'Preview only. Complete payment to download the final work.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ] else if (isClient &&
              hasSubmittedWork &&
              canAccessFinalDelivery) ...[
            const SizedBox(height: 10),
            const Text(
              'Payment completed. You can now download the final work.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          if (fileItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...fileItems.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildChatPanelSurface(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.insert_drive_file_outlined,
                        color: primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: !item.hasAccessibleUrl
                            ? null
                            : () => _openDeliveryFileItem(
                                item,
                                previewOnly: restrictSubmittedWork,
                              ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          side: BorderSide(color: primary.withOpacity(0.24)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          restrictSubmittedWork
                              ? (item.hasAccessibleUrl ? 'Preview' : 'Locked')
                              : 'Open Final Work',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
          if (linkUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...linkUrls.map((linkUrl) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildChatPanelSurface(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.link_rounded, color: primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          restrictSubmittedWork
                              ? 'Protected link available after payment'
                              : linkUrl,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: restrictSubmittedWork
                            ? null
                            : () => _openDeliveryUrl(linkUrl),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          side: BorderSide(color: primary.withOpacity(0.24)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          restrictSubmittedWork ? 'Locked' : 'Open Final Work',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildChatPanelSurface(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notes',
                    style: _chatPanelTitleStyle.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    notes,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (deliveryStatus == 'submitted' && isClient) ...[
            const SizedBox(height: 12),
            const Text(
              'Review the submitted work to continue.',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSavingContract
                        ? null
                        : _requestDeliveryChanges,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primary,
                      side: BorderSide(color: primary.withOpacity(0.24)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Request Changes'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSavingContract
                        ? null
                        : _approveDeliveryForPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Approve Work'),
                  ),
                ),
              ],
            ),
          ],
          if (deliveryStatus == 'submitted' && !isClient) ...[
            const SizedBox(height: 12),
            const Text(
              'Waiting for the client to review the submitted work.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSavingContract
                    ? null
                    : _withdrawDeliverySubmission,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFC75A5A),
                  side: const BorderSide(color: Color(0xFFC75A5A), width: 1),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Withdraw Submission'),
              ),
            ),
          ],
          if (deliveryStatus == 'changes_requested') ...[
            const SizedBox(height: 12),
            const Text(
              'The client requested changes. Please review the chat and resubmit when ready.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
          if (isApproved) ...[
            const SizedBox(height: 12),
            Text(
              isClient
                  ? 'The submitted work was approved and remains available below.'
                  : 'The client approved the submitted work. Your submitted files remain available below.',
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChatHeaderAdminReviewAction({
    EdgeInsetsGeometry padding = const EdgeInsets.only(right: 8),
  }) {
    return ReportFlagButton(
      padding: padding,
      onPressed: () {
        unawaited(
          showReportIssueDialog(
            context: context,
            source: 'chat',
            reportedUserId: widget.otherUserId,
            reportedUserName: widget.otherUserName,
            reportedUserRole: widget.otherUserRole,
            chatId: widget.chatId,
          ),
        );
      },
    );
  }

  Widget _buildAdminReviewSection(String contractStatus) {
    final contractData = _contractData;
    if (contractData == null) return const SizedBox.shrink();
    if (contractStatus != 'approved') return const SizedBox.shrink();

    final deliveryData = _asMap(contractData['deliveryData']);
    final deliveryStatus = _normalizeDeliveryStatus(deliveryData['status']);
    final adminReview = _asMap(contractData['adminReview']);
    final adminReviewStatus = _normalizeAdminReviewStatus(
      adminReview['status'],
    );
    final adminReviewReason = _adminReviewReasonLabel(
      (adminReview['reasonType'] ?? '').toString(),
    );
    final adminReviewRequestedBy = (adminReview['requestedBy'] ?? '')
        .toString()
        .trim();
    final canWithdrawAdminReview =
        adminReviewStatus != 'resolved' &&
        adminReviewRequestedBy == _currentUserRole();

    return _buildChatPanelContainer(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Admin Review',
            style: _chatPanelTitleStyle.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 10),
          if (adminReviewStatus != 'none') ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD54F)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Under Admin Review',
                    style: TextStyle(
                      color: Color(0xFF8D6E00),
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Reason: $adminReviewReason',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 12.5,
                    ),
                  ),
                  if (adminReviewRequestedBy.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Requested by: $adminReviewRequestedBy',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (canWithdrawAdminReview) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _isSavingContract
                            ? null
                            : _withdrawAdminReview,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          backgroundColor: Colors.transparent,
                          side: BorderSide(color: primary.withOpacity(0.32)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 20,
                          ),
                        ),
                        child: const Text(
                          'Withdraw Complaint',
                          textAlign: TextAlign.center,
                          style: TextStyle(height: 1.3),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (deliveryStatus != 'paid_delivered') ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSavingContract ? null : _requestAdminReview,
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(color: primary.withOpacity(0.24)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Request Admin Review'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPinnedContractMetaChip({
    required IconData icon,
    required String label,
    required String value,
    bool expand = false,
  }) {
    return Container(
      width: expand ? double.infinity : null,
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _chatPanelDecoration(
        backgroundColor: _chatPanelSurface,
        borderColor: _chatPanelBorder,
        radius: 14,
        showShadow: false,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: primary.withOpacity(0.82)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovedPanelContentCard({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final normalizedSubtitle = (subtitle ?? '').trim();

    return _buildChatPanelContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChatPanelHeader(title: title, subtitle: normalizedSubtitle),
          if (children.isNotEmpty) ...[const SizedBox(height: 12), ...children],
        ],
      ),
    );
  }

  Widget _buildApprovedPanelTabs() {
    const tabs = <String>['Contract', 'Deliverables', 'Review & Rate'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = _selectedApprovedPanelTab == index;

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: index == 0 ? 0 : 2,
                right: index == tabs.length - 1 ? 0 : 2,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    if (_selectedApprovedPanelTab == index) return;
                    setState(() {
                      _selectedApprovedPanelTab = index;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tabs[index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isSelected ? Colors.white : primary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildApprovedPanelTabContent({
    required double expandedBodyMaxHeight,
  }) {
    switch (_selectedApprovedPanelTab) {
      case 0:
        return _buildApprovedContractTab(
          expandedBodyMaxHeight: expandedBodyMaxHeight,
        );
      case 1:
        return _buildApprovedWorkProgressTab();
      case 2:
        return _buildApprovedReviewTab();
      default:
        return _buildApprovedContractTab(
          expandedBodyMaxHeight: expandedBodyMaxHeight,
        );
    }
  }

  Widget _buildApprovedContractTab({required double expandedBodyMaxHeight}) {
    final contractData = _contractData;
    if (contractData == null) return const SizedBox.shrink();

    final service = _asMap(contractData['service']);
    final payment = _asMap(contractData['payment']);
    final timeline = _asMap(contractData['timeline']);
    final description = (service['description'] ?? '').toString().trim();
    final amount = (payment['amount'] ?? '').toString().trim();
    final deadline = (timeline['deadline'] ?? '').toString().trim();
    final terminationSection = _buildContractTerminationSection();
    final hasTerminationSection = terminationSection is! SizedBox;

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : expandedBodyMaxHeight;

        return _buildContractScrollShell(
          controller: _approvedContractPanelScrollController,
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          maxHeight: contentHeight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildChatPanelContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      contractDisplayTitle,
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        description,
                        style: const TextStyle(
                          color: Colors.black87,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (amount.isNotEmpty || deadline.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, metaConstraints) {
                          final showInlineCards =
                              amount.isNotEmpty &&
                              deadline.isNotEmpty &&
                              metaConstraints.maxWidth >= 300;

                          if (showInlineCards) {
                            return Row(
                              children: [
                                Expanded(
                                  child: _buildPinnedContractMetaChip(
                                    icon: Icons.payments_outlined,
                                    label: 'Amount',
                                    value: '$amount SAR',
                                    expand: true,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildPinnedContractMetaChip(
                                    icon: Icons.event_outlined,
                                    label: 'Deadline',
                                    value: deadline,
                                    expand: true,
                                  ),
                                ),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              if (amount.isNotEmpty)
                                _buildPinnedContractMetaChip(
                                  icon: Icons.payments_outlined,
                                  label: 'Amount',
                                  value: '$amount SAR',
                                  expand: true,
                                ),
                              if (amount.isNotEmpty && deadline.isNotEmpty)
                                const SizedBox(height: 10),
                              if (deadline.isNotEmpty)
                                _buildPinnedContractMetaChip(
                                  icon: Icons.event_outlined,
                                  label: 'Deadline',
                                  value: deadline,
                                  expand: true,
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _downloadCurrentContract,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primary,
                          side: BorderSide(
                            color: primary.withOpacity(0.22),
                            width: 1,
                          ),
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download Contract'),
                      ),
                    ),
                  ],
                ),
              ),

              if (hasTerminationSection) ...[
                const SizedBox(height: 14),
                _buildChatPanelContainer(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contract Termination',
                        style: _chatPanelTitleStyle.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      terminationSection,
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildContractTerminationSection() {
    final contractData = _contractData;
    if (contractData == null) return const SizedBox.shrink();

    final approval = _asMap(contractData['approval']);
    final contractStatus = (approval['contractStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final termination =
        (approval['termination'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final paymentData = _currentPaymentData(contractData);
    final deliveryData = _currentDeliveryData(contractData);
    final paymentStatus = (paymentData['paymentStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final deliveryStatus = _normalizeDeliveryStatus(deliveryData['status']);
    final isPaidDelivered =
        deliveryStatus == 'paid_delivered' ||
        _isCompletedPaymentStatus(paymentStatus);
    final isCompleted = contractStatus == 'completed' || isPaidDelivered;
    final showTerminateButton = !isCompleted;
    final terminationGraceData = _terminationGracePeriodData();
    final terminationRequested = termination['requested'] == true;
    final terminationRequestedBy = (termination['requestedBy'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final terminationRejected = termination['rejected'] == true;
    final terminationRejectedBy = (termination['rejectedBy'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final terminationMode = (termination['mode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final currentUserRole = _currentUserRole();
    final otherPartyLabel = currentUserRole == 'client'
        ? 'freelancer'
        : 'client';
    final requesterLabel = terminationRequestedBy == 'client'
        ? 'client'
        : terminationRequestedBy == 'freelancer'
        ? 'freelancer'
        : 'other party';
    final currentUserRequestedTermination =
        terminationRequestedBy == currentUserRole;
    final currentUserMutualRequestRejected =
        contractStatus == 'approved' &&
        terminationRejected &&
        terminationMode == 'mutual_rejected' &&
        terminationRequestedBy == currentUserRole &&
        terminationRejectedBy.isNotEmpty &&
        terminationRejectedBy != currentUserRole;
    final showApproveTerminationButton =
        contractStatus == 'termination_pending' &&
        terminationRequested &&
        !currentUserRequestedTermination;
    final showRejectTerminationButton =
        contractStatus == 'termination_pending' &&
        terminationRequested &&
        !currentUserRequestedTermination;
    final showCancelTerminationButton =
        contractStatus == 'termination_pending' &&
        terminationRequested &&
        currentUserRequestedTermination;
    final terminationIndicatorColor =
        (terminationGraceData?['indicatorColor'] as Color?) ??
        const Color(0xFF43A047);
    final isTerminationGraceExpired =
        (terminationGraceData?['isExpired'] as bool?) ?? false;
    final terminationCountdownLabel = (terminationGraceData?['label'] ?? '')
        .toString();
    final terminationGraceSubtitle =
        (terminationGraceData?['subtitle'] ??
                'Direct termination is available during this period.')
            .toString();
    Future<void> handleAdminReviewOptionTap() async {
      await _openContractTerminationAdminReviewSheet();
    }

    Widget buildTerminationOptionSheetTile({
      required IconData icon,
      required String title,
      required String subtitle,
      required Future<void> Function()? onTap,
      bool enabled = true,
      Color accentColor = const Color(0xFFC75A5A),
    }) {
      final action = onTap;
      final canTap = enabled && action != null;

      return ListTile(
        enabled: canTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: accentColor, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: canTap ? Colors.black87 : Colors.black45,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            subtitle,
            style: TextStyle(
              color: canTap ? Colors.black54 : Colors.black38,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: accentColor.withOpacity(canTap ? 0.9 : 0.4),
          size: 22,
        ),
        onTap: canTap
            ? () {
                unawaited(action!());
              }
            : null,
      );
    }

    Future<void> openTerminationOptionsSheet() {
      final canOpenPaymentOption =
          !_isTerminatingContract && !_isSavingContract;
      final canOpenMutualOption = !_isTerminatingContract && !_isSavingContract;
      final canOpenAdminReviewOption = !_isSavingContract;

      return showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          Future<void> runSheetAction(Future<void> Function() action) async {
            Navigator.of(sheetContext).pop();
            await action();
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD8D3E5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Termination Options',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose how you want to proceed with this contract.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  buildTerminationOptionSheetTile(
                    icon: Icons.payments_outlined,
                    title: 'Terminate with Payment',
                    subtitle: 'Pay the required fee to end the contract.',
                    onTap: canOpenPaymentOption
                        ? () => runSheetAction(
                            _openTerminationCompensationPayment,
                          )
                        : null,
                  ),
                  Divider(height: 1, color: primary.withOpacity(0.08)),
                  buildTerminationOptionSheetTile(
                    icon: Icons.handshake_outlined,
                    title: 'Mutual Agreement',
                    subtitle:
                        'Send a termination request for the other party to approve.',
                    onTap: canOpenMutualOption
                        ? () => runSheetAction(
                            () => _requestTermination(forcePaidMode: 'mutual'),
                          )
                        : null,
                    accentColor: const Color(0xFFB86A4A),
                  ),
                  Divider(height: 1, color: primary.withOpacity(0.08)),
                  buildTerminationOptionSheetTile(
                    icon: Icons.support_agent_outlined,
                    title: 'Request Admin Review',
                    subtitle: 'Ask the admin to review the contract issue.',
                    onTap: canOpenAdminReviewOption
                        ? () => runSheetAction(handleAdminReviewOptionTap)
                        : null,
                    accentColor: const Color(0xFFB45A4F),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    Widget buildTerminateActionTrigger() {
      final isEnabled = !_isTerminatingContract;

      return Tooltip(
        message: 'Terminate Contract',
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 2),
        waitDuration: Duration.zero,
        preferBelow: false,
        child: Opacity(
          opacity: isEnabled ? 1 : 0.58,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isEnabled ? _requestTermination : null,
              customBorder: const CircleBorder(),
              child: Ink(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFC75A5A).withOpacity(0.10),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFC75A5A).withOpacity(0.22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFC75A5A).withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFFC75A5A),
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget buildExpiredTerminationUi() {
      return Column(
        key: const ValueKey('termination_expired_ui'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Free Window Ended',
                style: TextStyle(
                  color: Color(0xFFC75A5A),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(
                    255,
                    223,
                    41,
                    16,
                  ).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color.fromARGB(
                      255,
                      223,
                      41,
                      16,
                    ).withOpacity(0.22),
                  ),
                ),
                child: const Text(
                  'Fee Required',
                  style: TextStyle(
                    color: Color.fromARGB(255, 223, 41, 16),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'The free termination period has ended.',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          if (showTerminateButton) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: (_isTerminatingContract || _isSavingContract)
                  ? null
                  : () {
                      unawaited(openTerminationOptionsSheet());
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFC75A5A),
                backgroundColor: Colors.transparent,
                side: BorderSide(
                  color: const Color(0xFFC75A5A).withOpacity(0.24),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                minimumSize: const Size(0, 38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              label: const Text('Choose termination option'),
            ),
          ],
        ],
      );
    }

    Widget buildActiveTerminationUi() {
      return Column(
        key: const ValueKey('termination_active_ui'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Free Termination Window',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: terminationIndicatorColor,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: terminationIndicatorColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: terminationIndicatorColor.withOpacity(0.26),
              ),
              boxShadow: [
                BoxShadow(
                  color: terminationIndicatorColor.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    color: terminationIndicatorColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 1,
                    color: terminationIndicatorColor.withOpacity(0.20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    terminationCountdownLabel,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  if (terminationCountdownLabel.trim().toLowerCase() !=
                      'expired') ...[
                    const SizedBox(width: 8),
                    Text(
                      'left',
                      style: TextStyle(
                        color: terminationIndicatorColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            terminationGraceSubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          if (showTerminateButton) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: buildTerminateActionTrigger(),
            ),
          ],
        ],
      );
    }

    Widget buildTerminationGraceCard() {
      if (isTerminationGraceExpired) {
        return Container(
          key: const ValueKey('termination_expired_card'),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF6F6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFC75A5A).withOpacity(0.18),
            ),
            boxShadow: _chatPanelShadow,
          ),
          child: buildExpiredTerminationUi(),
        );
      }

      return Container(
        key: const ValueKey('termination_active_card'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF6FBF7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: terminationIndicatorColor.withOpacity(0.32),
          ),
          boxShadow: _chatPanelShadow,
        ),
        child: buildActiveTerminationUi(),
      );
    }

    final hasTerminationUi =
        terminationGraceData != null ||
        showTerminateButton ||
        currentUserMutualRequestRejected ||
        showApproveTerminationButton ||
        showCancelTerminationButton;

    if (!hasTerminationUi) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (terminationGraceData != null) ...[buildTerminationGraceCard()],
        if (showTerminateButton && terminationGraceData == null) ...[
          Align(
            alignment: Alignment.centerRight,
            child: buildTerminateActionTrigger(),
          ),
        ],
        if (currentUserMutualRequestRejected) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFD54F)),
            ),
            child: Text(
              'The $otherPartyLabel rejected your mutual termination request. You can continue with paid termination (20%).',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!isTerminationGraceExpired) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isTerminatingContract
                    ? null
                    : _openTerminationCompensationPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC75A5A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Terminate with 20%'),
              ),
            ),
          ],
        ],
        if (showApproveTerminationButton) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFD54F)),
            ),
            child: Text(
              'The $requesterLabel requested termination for this contract. You can approve or reject this request.',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        if (showCancelTerminationButton) ...[
          const SizedBox(height: 12),
          _buildChatPanelSurface(
            padding: const EdgeInsets.all(12),
            borderColor: primary.withOpacity(0.16),
            child: Text(
              'You requested termination for this contract. Please wait for the $otherPartyLabel to respond.',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        if (showApproveTerminationButton) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isTerminatingContract
                      ? null
                      : _approveTermination,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC75A5A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Approve Termination'),
                ),
              ),
              if (showRejectTerminationButton) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isTerminatingContract
                        ? null
                        : _rejectTermination,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Reject'),
                  ),
                ),
              ],
            ],
          ),
        ],
        if (showCancelTerminationButton) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isTerminatingContract ? null : _cancelTermination,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Cancel Termination'),
            ),
          ),
        ],
      ],
    );
  }

  /// One "stage card" for a single milestone in the 30/40/30 schedule —
  /// used by `_buildApprovedWorkProgressTab` when the contract has a
  /// `milestones` array. Reuses `_buildApprovedPanelContentCard` so it
  /// looks consistent with the rest of the workspace UI.
  Widget _buildMilestoneStatusCard({
    required int index,
    required List<Map<String, dynamic>> milestones,
    required bool isClientView,
  }) {
    final milestone = milestones[index];
    final status = (milestone['status'] ?? '').toString().trim().toLowerCase();
    final label = (milestone['label'] ?? 'Milestone ${index + 1}').toString();
    final deliveryRequired = milestone['deliveryRequired'] == true;

    if (status == 'locked') {
      return _buildApprovedPanelContentCard(
        title: label,
        subtitle: 'Locked',
        children: [
          Text(
            'Unlocks after Milestone $index is paid.',
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
      );
    }

    if (status == 'paid') {
      return _buildApprovedPanelContentCard(
        title: label,
        subtitle: 'Paid',
        children: [
          Row(
            children: const [
              Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF2E7D32),
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Payment completed',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      );
    }

    // Current/active milestone — either pending payment (milestone 1, no
    // deliverable) or somewhere in its own submit/approve delivery cycle.
    final deliveryData = _asMap(milestone['deliveryData']);
    final deliveryStatus = _normalizeDeliveryStatus(deliveryData['status']);
    final hasSubmittedWork = _hasSubmittedWorkContent(deliveryData);
    final canPay = deliveryRequired
        ? _isDeliveryApproved(deliveryStatus)
        : status == 'pending';
    final previousPaid =
        index == 0 ||
        (milestones[index - 1]['status'] ?? '').toString().trim().toLowerCase() ==
            'paid';

    final subtitle = deliveryRequired
        ? _deliveryStatusLabel(deliveryStatus)
        : 'Awaiting Payment';
    final message = deliveryRequired
        ? _deliveryStatusPaymentMessage(
            status: deliveryStatus,
            isClientView: isClientView,
          )
        : (isClientView
              ? 'Pay this milestone to let the freelancer start working.'
              : 'Waiting for the client to pay this milestone before work can start.');

    return _buildApprovedPanelContentCard(
      title: label,
      subtitle: subtitle,
      children: [
        Text(
          message,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
        if (isClientView) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSavingContract || !canPay || !previousPaid
                  ? null
                  : () => _openMoyasarPayment(milestoneIndex: index),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: primary.withOpacity(0.35),
                disabledForegroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.payments_outlined),
              label: Text(
                canPay
                    ? 'Pay Now'
                    : deliveryRequired && hasSubmittedWork
                    ? 'Approve Work to Pay'
                    : deliveryRequired
                    ? 'Waiting for Submitted Work'
                    : 'Not Ready Yet',
              ),
            ),
          ),
        ] else if (canPay) ...[
          const SizedBox(height: 12),
          const Text(
            'Payment will be available to the client after approval.',
            style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.35),
          ),
        ],
      ],
    );
  }

  Widget _buildApprovedWorkProgressTab() {
    final contractData = _contractData;
    if (contractData == null) return const SizedBox.shrink();

    final approval = _asMap(contractData['approval']);
    final contractStatus = (approval['contractStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final deliveryData = _currentDeliveryData(contractData);
    final paymentData = _currentPaymentData(contractData);
    final deliveryStatus = _normalizeDeliveryStatus(deliveryData['status']);
    final paymentStatus = (paymentData['paymentStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final hasSubmittedWork = _hasSubmittedWorkContent(deliveryData);
    final isApproved = _isDeliveryApproved(deliveryStatus);
    final isPaid =
        _isCompletedPaymentStatus(paymentStatus) ||
        deliveryStatus == 'paid_delivered';
    final isClientView = _currentUserRole() == 'client';
    final shouldShowWorkProgress = _shouldShowWorkProgressAction();
    final milestones = _milestones(contractData);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 320.0;

        return _buildContractScrollShell(
          controller: _approvedContractPanelScrollController,
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          maxHeight: contentHeight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: !shouldShowWorkProgress
                ? [
                    _buildApprovedPanelContentCard(
                      title: 'Work Delivery',
                      children: [
                        const Text(
                          'No work has been submitted yet.',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ]
                : milestones.isNotEmpty
                ? [
                    // Milestone-schedule contract: one active "Submitted
                    // Work" surface for the current milestone, then a
                    // stage card per milestone (paid / locked / current).
                    _buildDeliverySection(contractStatus),
                    const SizedBox(height: 14),
                    for (var i = 0; i < milestones.length; i++) ...[
                      _buildMilestoneStatusCard(
                        index: i,
                        milestones: milestones,
                        isClientView: isClientView,
                      ),
                      if (i != milestones.length - 1)
                        const SizedBox(height: 14),
                    ],
                  ]
                : [
                    // Legacy contract with no milestone schedule — exact
                    // original single lump-sum flow, unchanged.
                    _buildDeliverySection(contractStatus),
                    const SizedBox(height: 14),
                    _buildApprovedPanelContentCard(
                      title: 'Payment / Delivery Status',
                      subtitle: isPaid
                          ? 'Payment Completed'
                          : _deliveryStatusLabel(deliveryStatus),
                      children: [
                        Text(
                          _deliveryStatusPaymentMessage(
                            status: deliveryStatus,
                            isClientView: isClientView,
                          ),
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                        if (isPaid) ...[
                          const SizedBox(height: 12),
                          _buildChatPanelSurface(
                            padding: const EdgeInsets.all(12),
                            backgroundColor: const Color(0xFFF4EFFB),
                            borderColor: primary.withOpacity(0.18),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF2E7D32),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Payment Completed',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (isClientView) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isSavingContract || !isApproved
                                  ? null
                                  : () {
                                      debugPrint('PAY NOW CLICKED');
                                      _openMoyasarPayment();
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primary,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: primary.withOpacity(
                                  0.35,
                                ),
                                disabledForegroundColor: Colors.white70,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.payments_outlined),
                              label: Text(
                                isApproved
                                    ? 'Pay Now'
                                    : hasSubmittedWork
                                    ? 'Approve Work to Pay'
                                    : 'Waiting for Submitted Work',
                              ),
                            ),
                          ),
                        ],
                        if (!isClientView && isApproved && !isPaid) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Payment will be available to the client after approval.',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
          ),
        );
      },
    );
  }

  Widget _buildApprovedReviewTab() {
    final contractData = _contractData;
    if (contractData == null) return const SizedBox.shrink();

    final reviewAvailable = _isContractCompletedForReview(_contractData);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 320.0;

        return _buildContractScrollShell(
          controller: _approvedContractPanelScrollController,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          maxHeight: contentHeight,
          child: reviewAvailable
              ? _buildReviewActionSection()
              : _buildChatPanelContainer(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: _chatPanelBackground,
                  child: const Text(
                    'Review will be available after the service is completed.',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildVisibleContractScrollbar({
    required ScrollController controller,
    required Widget child,
  }) {
    return RawScrollbar(
      controller: controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      thickness: 5,
      radius: const Radius.circular(999),
      thumbColor: primary.withOpacity(0.55),
      trackColor: primary.withOpacity(0.10),
      trackBorderColor: Colors.transparent,
      child: child,
    );
  }

  Widget _buildSelectedNavIcon(IconData icon, {double size = 28}) {
    return Icon(icon, color: primary, size: size);
  }

  Widget _buildUnselectedNavIcon(IconData icon, {double size = 27}) {
    return Icon(icon, color: const Color(0xFF9A92B8), size: size);
  }

  Widget _buildContractScrollShell({
    required ScrollController controller,
    required EdgeInsetsGeometry padding,
    required Widget child,
    double maxHeight = 250,
  }) {
    return SizedBox(
      height: maxHeight,
      child: _buildContractScrollArea(
        controller: controller,
        child: SizedBox.expand(
          child: SingleChildScrollView(
            controller: controller,
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildContractScrollArea({
    required ScrollController controller,
    required Widget child,
  }) {
    return Stack(
      children: [
        _buildVisibleContractScrollbar(controller: controller, child: child),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: 26,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _chatPanelShellBackground.withOpacity(0.0),
                    _chatPanelShellBackground.withOpacity(0.92),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _downloadCurrentContract() async {
    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .get();
      final requestId = _extractRequestId(chatDoc.data());
      await downloadContract(requestId);
    } catch (e) {
      if (!mounted) return;
      debugPrint('Resolve contract download error: $e');
      unawaited(_showErrorDialog(_friendlyErrorMessage(e)));
    }
  }

  Future<List<_DeliveryLocalFile>> _pickDeliveryDocumentFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty)
      return const <_DeliveryLocalFile>[];

    final files = <_DeliveryLocalFile>[];
    for (final item in result.files) {
      final bytes = item.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      files.add(
        _DeliveryLocalFile(
          bytes: bytes,
          name: item.name.trim().isEmpty ? 'attachment' : item.name.trim(),
        ),
      );
    }

    return files;
  }

  Future<_DeliverySubmissionDraft?> _showDeliverySubmissionDialog(
    Map<String, dynamic> deliveryData, {
    required bool isUpdate,
  }) async {
    final linkController = TextEditingController(
      text: _deliveryLinkUrls(deliveryData).join('\n'),
    );
    final notesController = TextEditingController(
      text: _deliveryNotes(deliveryData),
    );

    try {
      return await showDialog<_DeliverySubmissionDraft>(
        context: context,
        builder: (dialogContext) {
          final existingImageUrls = List<String>.from(
            _deliveryImageUrls(deliveryData),
          );
          final existingFileItems = List<_DeliveryRemoteFile>.from(
            _deliveryFileItems(deliveryData),
          );
          final newImageFiles = <PickedImageData>[];
          final newDocumentFiles = <_DeliveryLocalFile>[];
          String validationMessage = '';

          Future<void> addImages(StateSetter setDialogState) async {
            final pickedFiles = await _picker.pickMultiImage(imageQuality: 85);
            if (pickedFiles.isEmpty) return;

            final images = await Future.wait(
              pickedFiles.map(
                (item) async => (
                  bytes: await item.readAsBytes(),
                  mimeType: item.mimeType ?? 'image/jpeg',
                ),
              ),
            );

            setDialogState(() {
              newImageFiles.addAll(images);
            });
          }

          Future<void> addFiles(StateSetter setDialogState) async {
            final pickedFiles = await _pickDeliveryDocumentFiles();
            if (pickedFiles.isEmpty) return;

            setDialogState(() {
              newDocumentFiles.addAll(pickedFiles);
            });
          }

          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(isUpdate ? 'Update Submission' : 'Submit Work'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Add images, files, links, and optional notes for the final delivery.',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => addImages(setDialogState),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primary,
                                  side: BorderSide(
                                    color: primary.withOpacity(0.24),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('Add Images'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => addFiles(setDialogState),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primary,
                                  side: BorderSide(
                                    color: primary.withOpacity(0.24),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.attach_file_rounded),
                                label: const Text('Add Files'),
                              ),
                            ),
                          ],
                        ),
                        if (existingImageUrls.isNotEmpty ||
                            newImageFiles.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Text(
                            'Images',
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 88,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                ...existingImageUrls.asMap().entries.map((
                                  entry,
                                ) {
                                  final index = entry.key;
                                  final imageUrl = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Image.network(
                                            imageUrl,
                                            width: 88,
                                            height: 88,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: GestureDetector(
                                            onTap: () {
                                              setDialogState(() {
                                                existingImageUrls.removeAt(
                                                  index,
                                                );
                                              });
                                            },
                                            child: const CircleAvatar(
                                              radius: 11,
                                              backgroundColor: Colors.black54,
                                              child: Icon(
                                                Icons.close,
                                                size: 13,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                ...newImageFiles.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final imageFile = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Image.memory(
                                            imageFile.bytes,
                                            width: 88,
                                            height: 88,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: GestureDetector(
                                            onTap: () {
                                              setDialogState(() {
                                                newImageFiles.removeAt(index);
                                              });
                                            },
                                            child: const CircleAvatar(
                                              radius: 11,
                                              backgroundColor: Colors.black54,
                                              child: Icon(
                                                Icons.close,
                                                size: 13,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                        if (existingFileItems.isNotEmpty ||
                            newDocumentFiles.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Text(
                            'Files',
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...existingFileItems.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildChatPanelSurface(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.insert_drive_file_outlined,
                                      color: primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        setDialogState(() {
                                          existingFileItems.removeAt(index);
                                        });
                                      },
                                      icon: const Icon(Icons.close, size: 18),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          ...newDocumentFiles.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildChatPanelSurface(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.attach_file_rounded,
                                      color: primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        setDialogState(() {
                                          newDocumentFiles.removeAt(index);
                                        });
                                      },
                                      icon: const Icon(Icons.close, size: 18),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                        const SizedBox(height: 8),
                        TextField(
                          controller: linkController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Links',
                            hintText: 'Add one link per line',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: notesController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: 'Notes (Optional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        if (validationMessage.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            validationMessage,
                            style: const TextStyle(
                              color: Color(0xFFC75A5A),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  OutlinedButton(
                    onPressed: () {
                      FocusScope.of(dialogContext).unfocus();
                      Navigator.of(dialogContext).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFC75A5A),
                      side: const BorderSide(color: Color(0xFFC75A5A)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final linkUrls = _dedupeStrings(
                        linkController.text
                            .split(RegExp(r'[\r\n]+'))
                            .map(_normalizeDeliveryLink)
                            .where((item) => item.isNotEmpty),
                      );
                      final draft = _DeliverySubmissionDraft(
                        keepImageUrls: List<String>.from(existingImageUrls),
                        keepFileItems: List<_DeliveryRemoteFile>.from(
                          existingFileItems,
                        ),
                        newImageFiles: List<PickedImageData>.from(
                          newImageFiles,
                        ),
                        newDocumentFiles: List<_DeliveryLocalFile>.from(
                          newDocumentFiles,
                        ),
                        linkUrls: linkUrls,
                        notes: notesController.text.trim(),
                      );

                      if (!draft.hasContent) {
                        setDialogState(() {
                          validationMessage =
                              'Add at least one image, file, or link before submitting.';
                        });
                        return;
                      }

                      FocusScope.of(dialogContext).unfocus();
                      Navigator.of(dialogContext).pop(draft);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(isUpdate ? 'Save Update' : 'Submit Work'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 350), () {
          linkController.dispose();
          notesController.dispose();
        }),
      );
    }
  }

  String _contractNotificationSnippet(Map<String, dynamic>? contractData) {
    final normalizedContractData = contractData ?? _contractData;
    final service = _asMap(normalizedContractData?['service']);
    final meta = _asMap(normalizedContractData?['meta']);

    final snippet = _singleLineSnippet(
      _firstFilled([
        service['description'],
        meta['title'],
        'Contract Agreement',
      ]),
    );

    return snippet.isEmpty ? 'Contract Agreement' : snippet;
  }

  String _contractNotificationId({
    required Map<String, dynamic>? contractData,
    required String requestId,
  }) {
    final normalizedContractData = contractData ?? _contractData;
    final meta = _asMap(normalizedContractData?['meta']);

    return _firstFilled([
      normalizedContractData?['contractId'],
      meta['contractId'],
      requestId,
    ]);
  }

  Future<void> _createContractNotification({
    required String type,
    required String actionText,
    required String requestId,
    required Map<String, dynamic>? chatData,
    required Map<String, dynamic>? contractData,
    bool notifyBothUsers = false,
  }) async {
    try {
      final normalizedChatData = chatData ?? <String, dynamic>{};
      final clientId = (normalizedChatData['clientId'] ?? '').toString().trim();
      final freelancerId = (normalizedChatData['freelancerId'] ?? '')
          .toString()
          .trim();
      final currentUserRole = _currentUserRole();
      final normalizedType = type.trim();
      final normalizedActionText = actionText.trim();
      final normalizedRequestId = requestId.trim();
      final senderId = currentUserRole == 'client' ? clientId : freelancerId;
      final receiverIds =
          (notifyBothUsers
                  ? <String>{clientId, freelancerId}
                  : <String>{
                      currentUserRole == 'client' ? freelancerId : clientId,
                    })
              .where((id) => id.trim().isNotEmpty)
              .toSet();

      if (senderId.isEmpty ||
          normalizedType.isEmpty ||
          normalizedActionText.isEmpty ||
          receiverIds.isEmpty) {
        return;
      }

      final senderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(senderId)
          .get();
      final senderData = senderDoc.data() ?? <String, dynamic>{};
      final senderName = _displayName(
        senderData,
        currentUserRole == 'client' ? 'Client' : 'Freelancer',
      );
      final senderProfileUrl = _firstFilled([
        senderData['photoUrl'],
        senderData['profile'],
      ]);
      final contractId = _contractNotificationId(
        contractData: contractData,
        requestId: requestId,
      );
      final snippet = _contractNotificationSnippet(contractData);

      for (final receiverId in receiverIds) {
        if (receiverId.trim().isEmpty) continue;

        await FirebaseFirestore.instance
            .collection('users')
            .doc(receiverId)
            .collection('notifications')
            .add({
              'type': normalizedType,
              'senderId': senderId,
              'senderName': senderName,
              'senderProfileUrl': senderProfileUrl,
              'receiverId': receiverId,
              'actionText': normalizedActionText,
              'snippet': snippet,
              'requestId': normalizedRequestId,
              'contractId': contractId,
              'chatId': widget.chatId,
              'isRead': false,
              'createdAt': FieldValue.serverTimestamp(),
            });

        await _sendNotificationPush(
          receiverId: receiverId,
          title: senderName.isEmpty ? 'Contract Update' : senderName,
          body: normalizedActionText,
          data: {
            'type': normalizedType,
            'senderId': senderId,
            'receiverId': receiverId,
            'requestId': normalizedRequestId,
            'contractId': contractId,
            'chatId': widget.chatId,
            'notificationOrigin': 'firestore_contract_notification',
          },
        );
      }
    } on FirebaseException catch (error, stackTrace) {
      _logCaughtError('Create contract notification error', error, stackTrace);
    } on TimeoutException catch (error, stackTrace) {
      _logCaughtError('Create contract notification error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      _logCaughtError('Create contract notification error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      _logCaughtError('Create contract notification error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      _logCaughtError('Create contract notification error', error, stackTrace);
    } catch (error, stackTrace) {
      _logCaughtError('Create contract notification error', error, stackTrace);
    }
  }

  Future<void> _sendNotificationPush({
    required String receiverId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await _postContractApi(
        endpointPath: 'send-notification-push',
        body: {
          'receiverId': receiverId,
          'title': title,
          'body': body,
          'data': data,
        },
        logLabel: 'Send notification push',
      );

      final responseData = _decodeResponseBodyAsMap(
        response,
        actionLabel: 'Send notification push',
      );

      if (!_didApiResponseSucceed(response, responseData)) {
        debugPrint(
          'Send notification push failed: '
          'status=${response.statusCode}, body=${response.body}',
        );
      }
    } on TimeoutException catch (error, stackTrace) {
      _logCaughtError('Send notification push error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      _logCaughtError('Send notification push error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      _logCaughtError('Send notification push error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      _logCaughtError('Send notification push error', error, stackTrace);
    } catch (error, stackTrace) {
      _logCaughtError('Send notification push error', error, stackTrace);
    }
  }

  bool _approvalFlag(Map<String, dynamic> approval, List<String> keys) {
    for (final key in keys) {
      final normalizedKey = key.toLowerCase();
      final keyLooksApproved =
          normalizedKey.contains('approved') ||
          normalizedKey.contains('approval') ||
          normalizedKey.contains('signed') ||
          normalizedKey.contains('accepted');
      final value = approval[key];
      if (value == true && keyLooksApproved) return true;

      final text = value?.toString().trim().toLowerCase() ?? '';
      if ((text == 'true' && keyLooksApproved) ||
          text == 'approved' ||
          text == 'accepted' ||
          text == 'signed') {
        return true;
      }
    }

    return false;
  }

  bool _rejectionFlag(Map<String, dynamic> approval, List<String> keys) {
    for (final key in keys) {
      final normalizedKey = key.toLowerCase();
      final keyLooksRejected =
          normalizedKey.contains('reject') ||
          normalizedKey.contains('disapprove') ||
          normalizedKey.contains('decline');
      final value = approval[key];
      if (value == true && keyLooksRejected) return true;

      final text = value?.toString().trim().toLowerCase() ?? '';
      if ((text == 'true' && keyLooksRejected) ||
          text == 'rejected' ||
          text == 'disapproved' ||
          text == 'declined') {
        return true;
      }
    }

    return false;
  }

  Future<void> _openSignatureAndApprove() async {
    final contractData = _contractData;
    if (contractData == null) return;
    if (await _showBlockedActionAndStopIfNeeded()) return;

    final signatureData = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (_) => const _SignatureSheet(primary: primary),
    );

    if (!mounted || signatureData == null || signatureData.isEmpty) return;

    await _approveContract(signatureData);
  }

  Future<void> _approveContract(String signatureData) async {
    final contractData = _contractData;
    if (contractData == null) return;

    setState(() {
      _isApprovingContract = true;
    });

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .get();

      final chatData = chatDoc.data();
      final requestId = _extractRequestId(chatData);
      final proposalId = (chatData?['proposalId'] ?? '').toString().trim();

      final response = await _postContractApi(
        endpointPath: 'approve-contract',
        body: {
          'requestId': requestId,
          if (proposalId.isNotEmpty) 'proposalId': proposalId,
          'role': _currentUserRole(),
          'signatureData': signatureData,
        },
        logLabel: 'Approve contract',
      );

      final data = _decodeResponseBodyAsMap(
        response,
        actionLabel: 'Approve contract',
      );

      if (!_didApiResponseSucceed(response, data)) {
        await _showApiFailure(
          actionLabel: 'Approve contract',
          response: response,
          responseData: data,
        );
        return;
      }

      final normalizedContractData = await _resolveContractDataForUiSync(
        actionLabel: 'Approve contract',
        responseData: data,
      );

      if (!mounted) return;

      setState(() {
        if (normalizedContractData != null) {
          _contractData = normalizedContractData;
        }
      });

      await _runNonBlockingSecondaryAction(
        'Approve contract notification',
        () => _createContractNotification(
          type: 'contract_approved',
          actionText: 'approved your contract',
          requestId: requestId,
          chatData: chatData,
          contractData: normalizedContractData,
        ),
      );

      _showSuccessSnackBar('Contract approved successfully');
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError('Approve contract error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError('Approve contract error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError('Approve contract error', error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError('Approve contract error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError('Approve contract error', error, stackTrace);
    } catch (error, stackTrace) {
      await _showLoggedError('Approve contract error', error, stackTrace);
    } finally {
      if (!mounted) return;

      setState(() {
        _isApprovingContract = false;
      });
    }
  }

  Future<void> _requestTermination({String? forcePaidMode}) async {
    String? terminationMode = forcePaidMode;

    if ((terminationMode ?? '').isEmpty && _isWithinTerminationGracePeriod()) {
      final shouldTerminate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Terminate Contract'),
            content: const Text(
              'Are you sure you want to terminate this contract?',
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primary,
                  side: BorderSide(color: primary.withOpacity(0.22)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC75A5A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Terminate'),
              ),
            ],
          );
        },
      );

      if (shouldTerminate != true || !mounted) return;
    } else if ((terminationMode ?? '').isEmpty) {
      terminationMode = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          final compensationText = _terminationCompensationText();
          return AlertDialog(
            title: const Text('Terminate Contract'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose how you want to terminate this contract.\n\n'
                  'Direct termination with compensation: you pay $compensationText to the other party.\n\n'
                  'Mutual termination: the other party must approve, with no payment required.',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop('mutual'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primary,
                      side: BorderSide(color: primary.withOpacity(0.22)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Mutual Termination'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop('paid'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFC75A5A),
                      backgroundColor: Colors.transparent,
                      side: const BorderSide(
                        color: Color(0xFFC75A5A),
                        width: 1,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Terminate with 20%'),
                  ),
                ),
              ],
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFC75A5A),
                  backgroundColor: Colors.transparent,
                  side: const BorderSide(color: Color(0xFFC75A5A)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );

      if ((terminationMode ?? '').isEmpty || !mounted) return;
    }

    if ((terminationMode ?? '').trim().toLowerCase() == 'paid' &&
        !_isWithinTerminationGracePeriod()) {
      await _openTerminationCompensationPayment();
      return;
    }

    setState(() {
      _isTerminatingContract = true;
    });

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .get();

      final chatData = chatDoc.data();
      final requestId = _extractRequestId(chatData);
      final proposalId = (chatData?['proposalId'] ?? '').toString().trim();

      final response = await _postContractApi(
        endpointPath: 'request-termination',
        body: {
          'requestId': requestId,
          if (proposalId.isNotEmpty) 'proposalId': proposalId,
          'role': _currentUserRole(),
          if ((terminationMode ?? '').isNotEmpty)
            'terminationMode': terminationMode,
        },
        logLabel: 'Request termination',
      );

      final data = _decodeResponseBodyAsMap(
        response,
        actionLabel: 'Request termination',
      );

      if (!_didApiResponseSucceed(response, data)) {
        await _showApiFailure(
          actionLabel: 'Request termination',
          response: response,
          responseData: data,
        );
        return;
      }

      final selfTerminated = data['selfTerminated'] == true;
      final terminationModeResponse = (data['terminationMode'] ?? '')
          .toString()
          .trim();
      final normalizedContractData = await _resolveContractDataForUiSync(
        actionLabel: 'Request termination',
        responseData: data,
      );

      if (!mounted) return;

      setState(() {
        if (normalizedContractData != null) {
          _contractData = normalizedContractData;
        }
      });

      await _runNonBlockingSecondaryAction(
        'Request termination notification',
        () => _createContractNotification(
          type: selfTerminated
              ? 'contract_terminated'
              : 'contract_termination_requested',
          actionText: selfTerminated
              ? terminationModeResponse == 'paid_compensation'
                    ? 'terminated the contract with 20% compensation'
                    : 'terminated the contract'
              : 'requested to terminate the contract',
          requestId: requestId,
          chatData: chatData,
          contractData: normalizedContractData,
        ),
      );

      _showSuccessSnackBar(
        selfTerminated
            ? terminationModeResponse == 'paid_compensation'
                  ? 'Contract terminated successfully with 20% compensation'
                  : 'Contract terminated successfully'
            : 'Termination requested',
      );
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError('Request termination error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError('Request termination error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError('Request termination error', error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError('Request termination error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError('Request termination error', error, stackTrace);
    } catch (error, stackTrace) {
      await _showLoggedError('Request termination error', error, stackTrace);
    } finally {
      if (!mounted) return;
      setState(() {
        _isTerminatingContract = false;
      });
    }
  }

  Future<void> _approveTermination() async {
    setState(() {
      _isTerminatingContract = true;
    });

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .get();

      final chatData = chatDoc.data();
      final requestId = _extractRequestId(chatData);
      final proposalId = (chatData?['proposalId'] ?? '').toString().trim();

      final response = await _postContractApi(
        endpointPath: 'approve-termination',
        body: {
          'requestId': requestId,
          if (proposalId.isNotEmpty) 'proposalId': proposalId,
          'role': _currentUserRole(),
        },
        logLabel: 'Approve termination',
      );

      final data = _decodeResponseBodyAsMap(
        response,
        actionLabel: 'Approve termination',
      );

      if (!_didApiResponseSucceed(response, data)) {
        await _showApiFailure(
          actionLabel: 'Approve termination',
          response: response,
          responseData: data,
        );
        return;
      }

      final normalizedContractData = await _resolveContractDataForUiSync(
        actionLabel: 'Approve termination',
        responseData: data,
      );

      if (!mounted) return;

      setState(() {
        if (normalizedContractData != null) {
          _contractData = normalizedContractData;
        }
      });

      await _runNonBlockingSecondaryAction(
        'Approve termination notification',
        () => _createContractNotification(
          type: 'contract_termination_approved',
          actionText: 'approved your termination request',
          requestId: requestId,
          chatData: chatData,
          contractData: normalizedContractData,
        ),
      );

      _showSuccessSnackBar('Contract terminated successfully');
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError('Approve termination error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError('Approve termination error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError('Approve termination error', error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError('Approve termination error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError('Approve termination error', error, stackTrace);
    } catch (error, stackTrace) {
      await _showLoggedError('Approve termination error', error, stackTrace);
    } finally {
      if (!mounted) return;
      setState(() {
        _isTerminatingContract = false;
      });
    }
  }

  Future<void> _rejectTermination() async {
    setState(() {
      _isTerminatingContract = true;
    });

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .get();

      final chatData = chatDoc.data();
      final requestId = _extractRequestId(chatData);
      final proposalId = (chatData?['proposalId'] ?? '').toString().trim();

      final response = await _postContractApi(
        endpointPath: 'reject-termination',
        body: {
          'requestId': requestId,
          if (proposalId.isNotEmpty) 'proposalId': proposalId,
          'role': _currentUserRole(),
        },
        logLabel: 'Reject termination',
      );

      final data = _decodeResponseBodyAsMap(
        response,
        actionLabel: 'Reject termination',
      );

      if (!_didApiResponseSucceed(response, data)) {
        await _showApiFailure(
          actionLabel: 'Reject termination',
          response: response,
          responseData: data,
        );
        return;
      }

      final normalizedContractData = await _resolveContractDataForUiSync(
        actionLabel: 'Reject termination',
        responseData: data,
      );

      if (!mounted) return;

      setState(() {
        if (normalizedContractData != null) {
          _contractData = normalizedContractData;
        }
      });

      await _runNonBlockingSecondaryAction(
        'Reject termination notification',
        () => _createContractNotification(
          type: 'contract_termination_rejected',
          actionText: 'rejected your termination request',
          requestId: requestId,
          chatData: chatData,
          contractData: normalizedContractData,
        ),
      );

      _showSuccessSnackBar('Termination request rejected');
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError('Reject termination error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError('Reject termination error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError('Reject termination error', error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError('Reject termination error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError('Reject termination error', error, stackTrace);
    } catch (error, stackTrace) {
      await _showLoggedError('Reject termination error', error, stackTrace);
    } finally {
      if (!mounted) return;
      setState(() {
        _isTerminatingContract = false;
      });
    }
  }

  Future<void> _cancelTermination() async {
    setState(() {
      _isTerminatingContract = true;
    });

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .get();

      final chatData = chatDoc.data();
      final requestId = _extractRequestId(chatData);
      final proposalId = (chatData?['proposalId'] ?? '').toString().trim();

      final response = await _postContractApi(
        endpointPath: 'cancel-termination',
        body: {
          'requestId': requestId,
          if (proposalId.isNotEmpty) 'proposalId': proposalId,
          'role': _currentUserRole(),
        },
        logLabel: 'Cancel termination',
      );

      final data = _decodeResponseBodyAsMap(
        response,
        actionLabel: 'Cancel termination',
      );

      if (!_didApiResponseSucceed(response, data)) {
        await _showApiFailure(
          actionLabel: 'Cancel termination',
          response: response,
          responseData: data,
        );
        return;
      }

      final normalizedContractData = await _resolveContractDataForUiSync(
        actionLabel: 'Cancel termination',
        responseData: data,
      );

      if (!mounted) return;

      setState(() {
        if (normalizedContractData != null) {
          _contractData = normalizedContractData;
        }
      });

      _showSuccessSnackBar('Termination cancelled');
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError('Cancel termination error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError('Cancel termination error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError('Cancel termination error', error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError('Cancel termination error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError('Cancel termination error', error, stackTrace);
    } catch (error, stackTrace) {
      await _showLoggedError('Cancel termination error', error, stackTrace);
    } finally {
      if (!mounted) return;
      setState(() {
        _isTerminatingContract = false;
      });
    }
  }

  Future<void> downloadContract(String requestId) async {
    try {
      // requestId alone only resolves contracts from the direct-request
      // flow. Contracts created via an accepted announcement proposal live
      // under the proposal instead, so — same as every other contract
      // action in this file — the chat doc's proposalId has to be sent
      // too, or the backend can't find the contract and downloading fails.
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .get();
      final proposalId = (chatDoc.data()?['proposalId'] ?? '')
          .toString()
          .trim();

      final url = _backendUri(
        'download-contract-pdf',
        queryParameters: {
          'requestId': requestId,
          if (proposalId.isNotEmpty) 'proposalId': proposalId,
        },
      );
      debugPrint('Download contract URL: $url');

      final opened = await launchUrl(url);

      if (!opened) {
        if (!mounted) return;
        unawaited(
          _showErrorDialog(_friendlyErrorMessage('Could not open PDF')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Download contract error: $e');
      unawaited(_showErrorDialog(_friendlyErrorMessage(e)));
    }
  }

  Future<void> _callCancelApproval() async {
    final contractData = _contractData;
    if (contractData == null) return;

    setState(() {
      _isApprovingContract = true;
    });

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .get();

      final chatData = chatDoc.data();
      final requestId = _extractRequestId(chatData);
      final proposalId = (chatData?['proposalId'] ?? '').toString().trim();

      final response = await _postContractApi(
        endpointPath: 'cancel-approval',
        body: {
          'requestId': requestId,
          if (proposalId.isNotEmpty) 'proposalId': proposalId,
          'role': _currentUserRole(),
        },
        logLabel: 'Cancel approval',
      );

      final data = _decodeResponseBodyAsMap(
        response,
        actionLabel: 'Cancel approval',
      );

      if (!_didApiResponseSucceed(response, data)) {
        await _showApiFailure(
          actionLabel: 'Cancel approval',
          response: response,
          responseData: data,
        );
        return;
      }

      final normalizedContractData = await _resolveContractDataForUiSync(
        actionLabel: 'Cancel approval',
        responseData: data,
      );

      if (!mounted) return;

      setState(() {
        if (normalizedContractData != null) {
          _contractData = normalizedContractData;
        }
      });

      _showSuccessSnackBar('Approval cancelled');
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError('Cancel approval error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError('Cancel approval error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError('Cancel approval error', error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError('Cancel approval error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError('Cancel approval error', error, stackTrace);
    } catch (error, stackTrace) {
      await _showLoggedError('Cancel approval error', error, stackTrace);
    } finally {
      if (!mounted) return;

      setState(() {
        _isApprovingContract = false;
      });
    }
  }

  Future<void> _disapproveContract() async {
    final contractData = _contractData;
    if (contractData == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Disapprove Contract'),
          content: const Text('Are you sure you want to reject this contract?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .get();

      final chatData = chatDoc.data();
      final requestId = _extractRequestId(chatData);
      final proposalId = (chatData?['proposalId'] ?? '').toString().trim();

      final response = await _postContractApi(
        endpointPath: 'disapprove-contract',
        body: {
          'requestId': requestId,
          if (proposalId.isNotEmpty) 'proposalId': proposalId,
          'role': _currentUserRole(),
        },
        logLabel: 'Disapprove contract',
      );

      final data = _decodeResponseBodyAsMap(
        response,
        actionLabel: 'Disapprove contract',
      );

      if (!_didApiResponseSucceed(response, data)) {
        await _showApiFailure(
          actionLabel: 'Disapprove contract',
          response: response,
          responseData: data,
        );
        return;
      }

      final normalizedContractData = await _resolveContractDataForUiSync(
        actionLabel: 'Disapprove contract',
        responseData: data,
      );

      if (!mounted) return;

      setState(() {
        if (normalizedContractData != null) {
          _contractData = normalizedContractData;
        }
      });

      await _runNonBlockingSecondaryAction(
        'Disapprove contract notification',
        () => _createContractNotification(
          type: 'contract_disapproved',
          actionText: 'rejected your contract',
          requestId: requestId,
          chatData: chatData,
          contractData: normalizedContractData,
        ),
      );

      _showSuccessSnackBar('Contract rejected');
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError('Reject contract error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError('Reject contract error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError('Reject contract error', error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError('Reject contract error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError('Reject contract error', error, stackTrace);
    } catch (error, stackTrace) {
      await _showLoggedError('Reject contract error', error, stackTrace);
    }
  }

  Future<void> _deleteContract() async {
    await _removeGeneratedContract(
      endpointPath: 'delete-contract',
      dialogTitle: 'Delete Contract',
      dialogMessage: 'Are you sure you want to delete this contract?',
      dismissLabel: 'Cancel',
      confirmLabel: 'Delete',
      successMessage: 'Contract deleted',
      logLabel: 'Delete contract',
      clearContractData: true,
    );
  }

  Future<void> _cancelContract() async {
    await _removeGeneratedContract(
      endpointPath: 'cancel-contract',
      dialogTitle: 'Cancel Contract',
      dialogMessage: 'Are you sure you want to cancel this contract?',
      dismissLabel: 'No',
      confirmLabel: 'Yes, Cancel',
      successMessage: 'Contract cancelled',
      logLabel: 'Cancel contract',
      clearContractData: false,
      includeRole: true,
    );
  }

  Future<void> _removeGeneratedContract({
    required String endpointPath,
    required String dialogTitle,
    required String dialogMessage,
    required String dismissLabel,
    required String confirmLabel,
    required String successMessage,
    required String logLabel,
    required bool clearContractData,
    bool includeRole = false,
  }) async {
    final contractData = _contractData;
    if (contractData == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(dialogTitle),
          content: Text(dialogMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dismissLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isSavingContract = true;
    });

    try {
      final chatDoc = await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .get();

      final chatData = chatDoc.data();
      final requestId = _extractRequestId(chatData);
      final proposalId = (chatData?['proposalId'] ?? '').toString().trim();
      final body = <String, dynamic>{'requestId': requestId};
      if (proposalId.isNotEmpty) {
        body['proposalId'] = proposalId;
      }
      if (includeRole) {
        body['role'] = _currentUserRole();
      }

      final response = await _postContractApi(
        endpointPath: endpointPath,
        body: body,
        logLabel: logLabel,
      );

      final data = _decodeResponseBodyAsMap(response, actionLabel: logLabel);

      if (!_didApiResponseSucceed(response, data)) {
        await _showApiFailure(
          actionLabel: logLabel,
          response: response,
          responseData: data,
        );
        return;
      }

      final normalizedContractData = clearContractData
          ? null
          : await _resolveContractDataForUiSync(
              actionLabel: logLabel,
              responseData: data,
            );

      if (!mounted) return;

      setState(() {
        _contractData = clearContractData ? null : normalizedContractData;
        _isEditingContract = false;
        _isAddingClause = false;
        _isApprovingContract = false;
        _isTerminatingContract = false;
        _pendingCustomClauses = [];
        _contractError = null;
      });

      _showSuccessSnackBar(successMessage);
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError('$logLabel error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError('$logLabel error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError('$logLabel error', error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError('$logLabel error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError('$logLabel error', error, stackTrace);
    } catch (error, stackTrace) {
      await _showLoggedError('$logLabel error', error, stackTrace);
    } finally {
      if (!mounted) return;

      setState(() {
        _isSavingContract = false;
      });
    }
  }

  void _handleAddClause() {
    if (_isSavingContract) return;

    final contractData = _contractData;
    if (contractData == null) return;

    final existingClauses =
        (contractData['customClauses'] as List?)?.toList() ?? [];
    final existingUserClauses = existingClauses.where((clause) {
      if (clause is! Map) return false;

      final source = (clause['source'] ?? '').toString().trim().toLowerCase();
      return source == 'user';
    }).length;
    final totalClauses = existingUserClauses + _pendingCustomClauses.length;

    if (totalClauses >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 5 clauses allowed')),
      );
      return;
    }

    setState(() {
      _isAddingClause = true;
      _pendingCustomClauses.add({'title': '', 'content': ''});
    });
  }

  Future<void> _deleteClause(int index) async {
    if (_isSavingContract) return;

    final contractData = _contractData;
    if (contractData == null) return;

    final updatedContractData = Map<String, dynamic>.from(contractData);
    final currentClauses =
        (updatedContractData['customClauses'] as List?)?.toList() ?? [];

    if (index < 0 || index >= currentClauses.length) return;

    currentClauses.removeAt(index);
    updatedContractData['customClauses'] = currentClauses;

    setState(() {
      _contractData = updatedContractData;
      _isSavingContract = true;
    });

    try {
      await _saveWorkflowContractData(
        updatedContractData,
        logLabel: 'Delete clause update',
      );

      if (!mounted) return;

      _showSuccessSnackBar('Contract updated successfully');
    } on TimeoutException catch (error, stackTrace) {
      await _showLoggedError('Delete clause update error', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      await _showLoggedError('Delete clause update error', error, stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      await _showLoggedError('Delete clause update error', error, stackTrace);
    } on FirebaseException catch (error, stackTrace) {
      await _showLoggedError('Delete clause update error', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      await _showLoggedError('Delete clause update error', error, stackTrace);
    } catch (error, stackTrace) {
      await _showLoggedError('Delete clause update error', error, stackTrace);
    } finally {
      if (!mounted) return;

      setState(() {
        _isSavingContract = false;
      });
    }
  }

  Widget _buildContractPreview() {
    final contractData = _contractData;
    if (contractData == null) return const SizedBox.shrink();

    final mediaQuery = MediaQuery.of(context);
    final keyboardOpen = mediaQuery.viewInsets.bottom > 0;
    final maxPreviewHeight = keyboardOpen
        ? mediaQuery.size.height * 0.38
        : mediaQuery.size.height * 0.55;

    final parties =
        (contractData['parties'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final service =
        (contractData['service'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final payment =
        (contractData['payment'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final timeline =
        (contractData['timeline'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    final approval =
        (contractData['approval'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    final contractStatus = (approval['contractStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (contractStatus == 'approved' ||
        contractStatus == 'completed' ||
        contractStatus == 'terminated' ||
        contractStatus == 'admin_terminated' ||
        contractStatus == 'cancelled' ||
        contractStatus == 'canceled') {
      return const SizedBox.shrink();
    }

    final termination =
        (approval['termination'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    final terminationRequested = termination['requested'] == true;
    final terminationRequestedBy = (termination['requestedBy'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final terminationRejected = termination['rejected'] == true;
    final terminationRejectedBy = (termination['rejectedBy'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final terminationMode = (termination['mode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    final currentUserRole = _currentUserRole();
    final otherPartyLabel = currentUserRole == 'client'
        ? 'freelancer'
        : 'client';
    final requesterLabel = terminationRequestedBy == 'client'
        ? 'client'
        : terminationRequestedBy == 'freelancer'
        ? 'freelancer'
        : 'other party';
    final currentUserRequestedTermination =
        terminationRequestedBy == currentUserRole;
    final currentUserMutualRequestRejected =
        contractStatus == 'approved' &&
        terminationRejected &&
        terminationMode == 'mutual_rejected' &&
        terminationRequestedBy == currentUserRole &&
        terminationRejectedBy.isNotEmpty &&
        terminationRejectedBy != currentUserRole;

    final showApproveTerminationButton =
        contractStatus == 'termination_pending' &&
        terminationRequested &&
        !currentUserRequestedTermination;

    final showRejectTerminationButton =
        contractStatus == 'termination_pending' &&
        terminationRequested &&
        !currentUserRequestedTermination;

    final showCancelTerminationButton =
        contractStatus == 'termination_pending' &&
        terminationRequested &&
        currentUserRequestedTermination;

    final customClauses = (contractData['customClauses'] as List?) ?? const [];
    final userCustomClauseEntries = customClauses.asMap().entries.where((
      entry,
    ) {
      final clause = entry.value;
      if (clause is! Map) return false;

      final source = (clause['source'] ?? '').toString().trim().toLowerCase();
      return source == 'user';
    }).toList();

    final meta =
        (contractData['meta'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    final List<dynamic> summary = const [];

    final clientApproved = _approvalFlag(approval, const [
      'clientApproved',
      'clientApproval',
      'clientApprovalStatus',
      'clientDecision',
      'clientStatus',
      'clientSigned',
    ]);

    final freelancerApproved = _approvalFlag(approval, const [
      'freelancerApproved',
      'freelancerApproval',
      'freelancerApprovalStatus',
      'freelancerDecision',
      'freelancerStatus',
      'freelancerSigned',
    ]);

    final bothPartiesApproved = clientApproved && freelancerApproved;

    final clientRejected = _rejectionFlag(approval, const [
      'clientRejected',
      'clientRejection',
      'clientRejectionStatus',
      'clientDisapproved',
      'clientDecision',
      'clientStatus',
    ]);

    final freelancerRejected = _rejectionFlag(approval, const [
      'freelancerRejected',
      'freelancerRejection',
      'freelancerRejectionStatus',
      'freelancerDisapproved',
      'freelancerDecision',
      'freelancerStatus',
    ]);

    final bothPartiesRejected =
        (clientRejected && freelancerRejected) || contractStatus == 'rejected';

    final hasPendingDecisionStatus =
        contractStatus.isEmpty ||
        contractStatus == 'draft' ||
        contractStatus == 'edited' ||
        contractStatus == 'pending_approval';

    final hasPendingPartyDecision = !clientApproved || !freelancerApproved;

    final contractNeedsDecision =
        !bothPartiesApproved &&
        !bothPartiesRejected &&
        !terminationRequested &&
        hasPendingDecisionStatus &&
        hasPendingPartyDecision;

    final currentUserApproved = currentUserRole == 'client'
        ? clientApproved
        : freelancerApproved;

    final otherPartyApproved = currentUserRole == 'client'
        ? freelancerApproved
        : clientApproved;

    final showApproveActions =
        !_isEditingContract &&
        !currentUserApproved &&
        contractStatus != 'approved' &&
        contractStatus != 'rejected' &&
        contractStatus != 'termination_pending' &&
        contractStatus != 'terminated';

    final showWaitingForOtherPartySignature =
        !_isEditingContract &&
        currentUserApproved &&
        !otherPartyApproved &&
        contractStatus == 'pending_approval';

    final showCancelApproval =
        !_isEditingContract &&
        currentUserApproved &&
        !otherPartyApproved &&
        contractStatus == 'pending_approval';

    final showCancelContractButton =
        !_isEditingContract && contractNeedsDecision;

    final canEditContract =
        contractStatus == 'draft' ||
        contractStatus == 'edited' ||
        (contractStatus == 'pending_approval' &&
            !currentUserApproved &&
            otherPartyApproved);

    final statusChipText = contractStatus == 'approved'
        ? 'Approved'
        : contractStatus == 'rejected'
        ? 'Rejected'
        : contractStatus == 'edited'
        ? 'Edited'
        : contractStatus == 'pending_approval'
        ? 'Waiting'
        : contractStatus == 'termination_pending'
        ? 'Termination Pending'
        : contractStatus == 'terminated'
        ? 'Terminated'
        : contractStatus == 'admin_terminated'
        ? 'Terminated'
        : 'Draft';

    final statusChipBackgroundColor = contractStatus == 'approved'
        ? const Color(0xFFE8F5E9)
        : contractStatus == 'rejected'
        ? const Color(0xFFFFEBEE)
        : contractStatus == 'edited'
        ? const Color(0xFFEEE8FB)
        : contractStatus == 'pending_approval'
        ? const Color(0xFFFFF4E5)
        : contractStatus == 'termination_pending'
        ? const Color(0xFFFFF4E5)
        : contractStatus == 'terminated'
        ? const Color(0xFFF3E5F5)
        : contractStatus == 'admin_terminated'
        ? const Color(0xFFF3E5F5)
        : const Color(0xFFF1F3F4);

    final statusChipTextColor = contractStatus == 'approved'
        ? const Color(0xFF2E7D32)
        : contractStatus == 'rejected'
        ? Colors.redAccent
        : contractStatus == 'edited'
        ? primary
        : contractStatus == 'pending_approval'
        ? const Color(0xFFEF6C00)
        : contractStatus == 'termination_pending'
        ? const Color(0xFFEF6C00)
        : contractStatus == 'terminated'
        ? const Color(0xFF6A1B9A)
        : contractStatus == 'admin_terminated'
        ? const Color(0xFF6A1B9A)
        : Colors.black54;

    final statusChipIcon = contractStatus == 'approved'
        ? Icons.check_circle_rounded
        : contractStatus == 'rejected'
        ? Icons.cancel_rounded
        : contractStatus == 'edited'
        ? Icons.edit_note_rounded
        : contractStatus == 'pending_approval'
        ? Icons.hourglass_top_rounded
        : contractStatus == 'termination_pending'
        ? Icons.warning_amber_rounded
        : contractStatus == 'terminated'
        ? Icons.block_rounded
        : contractStatus == 'admin_terminated'
        ? Icons.block_rounded
        : Icons.description_outlined;

    final amount = (payment['amount'] ?? '').toString().trim();
    final paymentText = amount.isEmpty ? '-' : '$amount SAR';
    final header = Row(
      children: [
        Expanded(
          child: const Text(
            contractDisplayTitle,
            style: TextStyle(
              color: primary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        Material(
          color: const Color(0xFFF4F1FA),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              setState(() {
                _isContractPreviewExpanded = !_isContractPreviewExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                _isContractPreviewExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: primary,
                size: 20,
              ),
            ),
          ),
        ),
        if (canEditContract && contractStatus != 'draft') ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusChipBackgroundColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusChipIcon, size: 14, color: statusChipTextColor),
                const SizedBox(width: 6),
                Text(
                  statusChipText,
                  style: TextStyle(
                    color: statusChipTextColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (canEditContract) ...[
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: (_isSavingContract || _isApprovingContract)
                ? null
                : _toggleContractEdit,
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(_isEditingContract ? Icons.check : Icons.edit),
            label: Text(_isEditingContract ? 'Save' : 'Edit'),
          ),
        ],
        if (!canEditContract) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusChipBackgroundColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusChipIcon, size: 14, color: statusChipTextColor),
                const SizedBox(width: 6),
                Text(
                  statusChipText,
                  style: TextStyle(
                    color: statusChipTextColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (!_isContractPreviewExpanded) {
      return _buildChatPanelContainer(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        backgroundColor: _chatPanelSurface,
        borderColor: _chatPanelBorder,
        showShadow: false,
        child: header,
      );
    }

    return _buildChatPanelContainer(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      backgroundColor: _chatPanelSurface,
      borderColor: _chatPanelBorder,
      showShadow: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxPreviewHeight),
        child: Scrollbar(
          controller: _contractPreviewScrollController,
          thumbVisibility: true,
          thickness: 2.5,
          radius: const Radius.circular(999),
          child: SingleChildScrollView(
            controller: _contractPreviewScrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                if (contractStatus == 'edited') ...[
                  const SizedBox(height: 8),
                  const Text(
                    'This contract was edited and requires fresh approval from both parties.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _buildContractSection(
                  title: 'Client name',
                  children: [
                    Text(
                      (parties['clientName'] ?? '').toString(),
                      style: const TextStyle(
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildContractSection(
                  title: 'Freelancer name',
                  children: [
                    Text(
                      (parties['freelancerName'] ?? '').toString(),
                      style: const TextStyle(
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildContractSection(
                  title: 'Service description',
                  children: [
                    _isEditingContract
                        ? _buildContractInput(
                            initialValue: _editableServiceDescription,
                            maxLength: 150,
                            maxLines: 3,
                            validator: _validateContractDescription,
                            onChanged: (value) {
                              _editableServiceDescription = value;
                            },
                          )
                        : Text(
                            (service['description'] ?? '')
                                    .toString()
                                    .trim()
                                    .isEmpty
                                ? '-'
                                : (service['description'] ?? '').toString(),
                            style: const TextStyle(
                              color: Colors.black87,
                              height: 1.4,
                            ),
                          ),
                  ],
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildContractSection(
                    title: 'Summary',
                    children: [
                      ...summary.map<Widget>((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            "• ${item.toString()}",
                            style: const TextStyle(
                              color: Colors.black87,
                              height: 1.4,
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                _buildContractSection(
                  title: 'Amount',
                  children: [
                    _isEditingContract
                        ? Row(
                            children: [
                              Expanded(
                                child: _buildContractInput(
                                  initialValue: _editableAmount,
                                  maxLength: 10,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.]'),
                                    ),
                                    TextInputFormatter.withFunction((
                                      oldValue,
                                      newValue,
                                    ) {
                                      final text = newValue.text;
                                      if (text.isEmpty) {
                                        return newValue;
                                      }

                                      if (!RegExp(
                                        r'^\d*\.?\d{0,2}$',
                                      ).hasMatch(text)) {
                                        return oldValue;
                                      }

                                      return newValue;
                                    }),
                                  ],
                                  onChanged: (value) {
                                    _editableAmount = value;
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'SAR',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            paymentText,
                            style: const TextStyle(
                              color: Colors.black87,
                              height: 1.4,
                            ),
                          ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildContractSection(
                  title: 'Deadline',
                  children: [
                    _isEditingContract
                        ? GestureDetector(
                            onTap: _pickContractDeadline,
                            child: AbsorbPointer(
                              child: _buildContractInput(
                                initialValue: _editableDeadline,
                                readOnly: true,
                                suffixIcon: const Icon(
                                  Icons.calendar_today_outlined,
                                ),
                                onChanged: (value) {
                                  _editableDeadline = value;
                                },
                              ),
                            ),
                          )
                        : Text(
                            (timeline['deadline'] ?? '')
                                    .toString()
                                    .trim()
                                    .isEmpty
                                ? '-'
                                : (timeline['deadline'] ?? '').toString(),
                            style: const TextStyle(
                              color: Colors.black87,
                              height: 1.4,
                            ),
                          ),
                  ],
                ),
                if (_isEditingContract) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _handleAddClause,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Clause'),
                    ),
                  ),
                ],
                if (_isEditingContract && _pendingCustomClauses.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ..._pendingCustomClauses.asMap().entries.map((entry) {
                    final index = entry.key;
                    final clause = entry.value;

                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: primary.withOpacity(0.12)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            initialValue: clause['title'] ?? '',
                            maxLength: 20,
                            maxLines: 1,
                            onChanged: (value) {
                              _pendingCustomClauses[index]['title'] = value;
                            },
                            decoration: InputDecoration(
                              hintText: 'Clause title',
                              counterText: '',
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFF8F6FC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: primary.withOpacity(0.12),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: primary.withOpacity(0.12),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: primary),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: clause['content'] ?? '',
                            maxLength: 100,
                            minLines: 2,
                            maxLines: 4,
                            onChanged: (value) {
                              _pendingCustomClauses[index]['content'] = value;
                            },
                            decoration: InputDecoration(
                              hintText: 'Clause content',
                              counterText: '',
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFF8F6FC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: primary.withOpacity(0.12),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: primary.withOpacity(0.12),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: primary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
                if (userCustomClauseEntries.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...userCustomClauseEntries.map((entry) {
                    final index = entry.key;
                    final clause = entry.value as Map;

                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: primary.withOpacity(0.12)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (clause['title'] ?? '').toString().trim().isEmpty
                                ? 'Clause'
                                : (clause['title'] ?? '').toString(),
                            style: const TextStyle(
                              color: primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (clause['content'] ?? '').toString().trim().isEmpty
                                ? '-'
                                : (clause['content'] ?? '').toString(),
                            style: const TextStyle(
                              color: Colors.black87,
                              height: 1.4,
                            ),
                          ),
                          if (_isEditingContract) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _deleteClause(index),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Delete'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ],
                if (showApproveActions) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isApprovingContract
                              ? null
                              : _openSignatureAndApprove,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Approve'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isApprovingContract
                              ? null
                              : _disapproveContract,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Disapprove'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (showWaitingForOtherPartySignature) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Waiting for the other party approval.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
                if (showCancelApproval) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isApprovingContract
                          ? null
                          : _callCancelApproval,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text('Cancel Approval'),
                    ),
                  ),
                ],
                if (showCancelContractButton) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isSavingContract ? null : _cancelContract,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Cancel Contract'),
                    ),
                  ),
                ],
                if (currentUserMutualRequestRejected) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFD54F)),
                    ),
                    child: Text(
                      'The $otherPartyLabel rejected your mutual termination request. You can continue with paid termination (20%).',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isTerminatingContract
                          ? null
                          : _openTerminationCompensationPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC75A5A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Terminate with 20%'),
                    ),
                  ),
                ],
                if (showApproveTerminationButton) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFD54F)),
                    ),
                    child: Text(
                      'The $requesterLabel requested termination for this contract. You can approve or reject this request.',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (showCancelTerminationButton) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E5F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primary.withOpacity(0.22)),
                    ),
                    child: Text(
                      'You requested termination for this contract. Please wait for the $otherPartyLabel to respond.',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (showApproveTerminationButton) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isTerminatingContract
                              ? null
                              : _approveTermination,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFC75A5A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Approve Termination'),
                        ),
                      ),
                      if (showRejectTerminationButton) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isTerminatingContract
                                ? null
                                : _rejectTermination,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Reject'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                if (showCancelTerminationButton) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isTerminatingContract
                          ? null
                          : _cancelTermination,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text('Cancel Termination'),
                    ),
                  ),
                ],
                if (contractStatus == 'rejected') ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isSavingContract ? null : _deleteContract,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete Contract'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.adminReadOnlyMode) {
      return _buildAdminReadOnlyScaffold();
    }

    final previewContractStatus =
        ((_contractData?['approval']
                    as Map<String, dynamic>?)?['contractStatus']
                as Object?)
            ?.toString()
            .trim()
            .toLowerCase() ??
        '';
    final showGenerateContractButton =
        !_isLoadingContractData &&
        (_contractData == null ||
            previewContractStatus == 'terminated' ||
            previewContractStatus == 'admin_terminated' ||
            previewContractStatus == 'cancelled' ||
            previewContractStatus == 'canceled');
    final showPinnedApprovedContract =
        previewContractStatus == 'approved' ||
        previewContractStatus == 'completed';
    final showWorkProgressAction = _shouldShowWorkProgressAction();
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final workProgressContractStatus =
        ((_contractData?['approval']
                    as Map<String, dynamic>?)?['contractStatus']
                as Object?)
            ?.toString()
            .trim()
            .toLowerCase() ??
        '';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: primary,
        elevation: 0,
        leading: const BackButton(),
        titleSpacing: 0,
        actions: [
          if (showWorkProgressAction)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Material(
                  color: _isWorkProgressSheetOpen
                      ? primary.withOpacity(0.16)
                      : const Color(0xFFF6F2FB),
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: _isSwitchingPanels ? null : _openWorkProgressSheet,
                    customBorder: const CircleBorder(),
                    splashColor: primary.withOpacity(0.12),
                    highlightColor: primary.withOpacity(0.08),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isWorkProgressSheetOpen
                              ? primary.withOpacity(0.28)
                              : primary.withOpacity(0.10),
                        ),
                      ),
                      child: Icon(
                        Icons.timeline_rounded,
                        color: _isWorkProgressSheetOpen
                            ? primary
                            : primary.withOpacity(0.92),
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          _buildChatHeaderAdminReviewAction(
            padding: const EdgeInsets.only(right: 12),
          ),
        ],
        title: GestureDetector(
          onTap: _openOtherUserProfile,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFF6F2FB),
                onBackgroundImageError:
                    _otherUserPhotoUrl != null && _otherUserPhotoUrl!.isNotEmpty
                    ? (error, stackTrace) {
                        debugPrint(
                          'Failed to load chat avatar from Firebase Storage: $error',
                        );
                        if (!mounted) return;
                        setState(() {
                          _otherUserPhotoUrl = null;
                        });
                      }
                    : null,
                backgroundImage:
                    _otherUserPhotoUrl != null && _otherUserPhotoUrl!.isNotEmpty
                    ? NetworkImage(_otherUserPhotoUrl!)
                    : null,
                child:
                    (_otherUserPhotoUrl == null || _otherUserPhotoUrl!.isEmpty)
                    ? const Icon(Icons.person, color: primary, size: 20)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.otherUserName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child:
                (!isKeyboardOpen &&
                    showWorkProgressAction &&
                    _isWorkProgressSheetOpen)
                ? Container(
                    key: const ValueKey('work_progress_inline_panel'),
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Material(
                          color: Colors.white,
                          elevation: 2,
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F2FB),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: primary.withOpacity(0.12),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInlineWorkProgressHeader(),
                                const SizedBox(height: 12),
                                _buildContractProgressSection(
                                  contractStatus: workProgressContractStatus,
                                  currentUserRole: _currentUserRole(),
                                  showSectionTitle: false,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('work_progress_hidden')),
          ),
          Expanded(
            child: Stack(
              children: [
                StreamBuilder<List<MessageModel>>(
                  stream: _controller.getMessages(widget.chatId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Failed to load messages: ${snapshot.error}',
                        ),
                      );
                    }

                    final messages = snapshot.data ?? [];
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _scrollToBottom(jump: true);
                    });

                    if (messages.isEmpty) {
                      return const Center(
                        child: Text(
                          'No messages yet.',
                          style: TextStyle(fontSize: 15),
                        ),
                      );
                    }

                    return Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          return _buildMessageBubble(messages[index]);
                        },
                      ),
                    );
                  },
                ),
                if (!isKeyboardOpen &&
                    showPinnedApprovedContract &&
                    _isApprovedContractPanelExpanded)
                  _buildPinnedApprovedContractScrollable(
                    overlayExpandedPanel: true,
                  ),
              ],
            ),
          ),
          if (!isKeyboardOpen &&
              showPinnedApprovedContract &&
              !_isApprovedContractPanelExpanded)
            _buildPinnedApprovedContractScrollable(),

          SafeArea(
            top: false,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              // The Scaffold already shifts content for the keyboard via
              // resizeToAvoidBottomInset, so adding viewInsets here causes the
              // bottom area to be pushed twice on real devices.
              padding: const EdgeInsets.only(bottom: 0),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_selectedImages.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F2FB),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: primary.withOpacity(0.20),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.image_outlined,
                                    color: primary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${_selectedImages.length} image(s) selected',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 90,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _selectedImages.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    return Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Image.memory(
                                            _selectedImages[index].bytes,
                                            width: 90,
                                            height: 90,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _selectedImages.removeAt(index);
                                              });
                                            },
                                            child: const CircleAvatar(
                                              radius: 11,
                                              backgroundColor: Colors.black54,
                                              child: Icon(
                                                Icons.close,
                                                size: 13,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'You can send these images with or without text.',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_isGeneratingContract)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: primary,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Generating contract.',
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_isSavingContract)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: primary,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Saving contract.',
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_contractError != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _contractError!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),

                      _buildContractPreview(),

                      if (showGenerateContractButton)
                        _buildGenerateContractSection(),

                      Row(
                        children: [
                          IconButton(
                            onPressed: _isSending ? null : _pickImages,
                            icon: const Icon(
                              Icons.image_outlined,
                              color: primary,
                            ),
                            tooltip: 'Send image',
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              minLines: 1,
                              maxLines: 4,
                              decoration: InputDecoration(
                                hintText: 'Write a message.',
                                filled: true,
                                fillColor: const Color(0xFFF6F2FB),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: primary,
                            child: _isSending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : IconButton(
                                    onPressed: _sendMessage,
                                    icon: const Icon(
                                      Icons.send,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignatureSheet extends StatefulWidget {
  final Color primary;

  const _SignatureSheet({required this.primary});

  @override
  State<_SignatureSheet> createState() => _SignatureSheetState();
}

class _SignatureSheetState extends State<_SignatureSheet> {
  final GlobalKey _signatureKey = GlobalKey();
  final List<Offset?> _points = [];
  bool _isConfirming = false;

  bool get _hasSignature => _points.any((point) => point != null);

  Future<void> _showErrorDialog(String message) {
    return _showErrorDialogForContext(context, message);
  }

  void _clearSignature() {
    setState(() {
      _points.clear();
    });
  }

  Future<void> _confirmSignature() async {
    if (!_hasSignature || _isConfirming) return;

    setState(() {
      _isConfirming = true;
    });

    try {
      final boundary =
          _signatureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;

      if (boundary == null) {
        throw Exception('Signature pad is not ready');
      }

      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('Failed to convert signature to image');
      }

      if (!mounted) return;

      Navigator.of(context).pop(base64Encode(byteData.buffer.asUint8List()));
    } catch (e) {
      if (!mounted) return;
      debugPrint('Signature capture error: $e');
      unawaited(_showErrorDialog(_friendlyErrorMessage(e)));
      setState(() {
        _isConfirming = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sign Contract',
                        style: TextStyle(
                          color: widget.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isConfirming
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Draw your signature below, then confirm to approve the contract.',
                  style: TextStyle(color: Colors.black54, height: 1.4),
                ),
                const SizedBox(height: 16),
                RepaintBoundary(
                  key: _signatureKey,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      setState(() {
                        _points.add(details.localPosition);
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        _points.add(details.localPosition);
                      });
                    },
                    onPanEnd: (_) {
                      setState(() {
                        _points.add(null);
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      height: 220,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: widget.primary.withOpacity(0.2),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CustomPaint(
                          painter: _SignaturePainter(points: _points),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: (_isConfirming || !_hasSignature)
                            ? null
                            : _clearSignature,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.primary,
                          side: BorderSide(
                            color: widget.primary.withOpacity(0.22),
                          ),
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_isConfirming || !_hasSignature)
                            ? null
                            : _confirmSignature,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isConfirming
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Confirm'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewEditorSheet extends StatefulWidget {
  final Color primary;
  final bool isEditing;
  final int initialRating;
  final String initialText;
  final String reviewedUserName;
  final Future<bool> Function(int rating, String reviewText) onSubmit;

  const _ReviewEditorSheet({
    required this.primary,
    required this.isEditing,
    required this.initialRating,
    required this.initialText,
    required this.reviewedUserName,
    required this.onSubmit,
  });

  @override
  State<_ReviewEditorSheet> createState() => _ReviewEditorSheetState();
}

class _ReviewEditorSheetState extends State<_ReviewEditorSheet> {
  late final TextEditingController _textController;
  late int _rating;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating.clamp(0, 5);
    _textController = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reviewText = _textController.text.trim();

    if (_rating < 1 || _rating > 5) {
      await _showErrorDialogForContext(context, 'Please select a rating');
      return;
    }

    if (reviewText.isEmpty) {
      await _showErrorDialogForContext(context, 'Please enter your review');
      return;
    }

    if (reviewText.length > 100) {
      await _showErrorDialogForContext(
        context,
        'Review must be 100 characters or less',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final success = await widget.onSubmit(_rating, reviewText);
      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      await _showErrorDialogForContext(context, _friendlyErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.isEditing ? 'Edit Review' : 'Rate & Review',
                        style: TextStyle(
                          color: widget.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  'Review for ${widget.reviewedUserName}',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your rating',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (index) {
                    final starValue = index + 1;
                    return IconButton(
                      onPressed: _isSubmitting
                          ? null
                          : () {
                              setState(() {
                                _rating = starValue;
                              });
                            },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      icon: Icon(
                        starValue <= _rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 30,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your review',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _textController,
                  minLines: 4,
                  maxLines: 6,
                  maxLength: 100,
                  textInputAction: TextInputAction.newline,
                  inputFormatters: [LengthLimitingTextInputFormatter(100)],
                  decoration: InputDecoration(
                    hintText:
                        'Share your experience with this completed service.',
                    filled: true,
                    fillColor: const Color(0xFFF6F2FB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      widget.isEditing ? 'Save Review' : 'Submit Review',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;

  const _SignaturePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < points.length; i++) {
      final current = points[i];
      final next = i + 1 < points.length ? points[i + 1] : null;

      if (current == null) continue;

      if (next != null) {
        canvas.drawLine(current, next, paint);
      } else {
        canvas.drawCircle(
          current,
          paint.strokeWidth / 2,
          Paint()..color = paint.color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) {
    return true;
  }
}

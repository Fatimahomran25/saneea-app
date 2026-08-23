import 'package:cloud_firestore/cloud_firestore.dart';

enum ContractStatusGroup { ongoing, terminated, past }

class GeneratedContract {
  final String contractId;
  final String requestId;
  final String? chatId;
  final String userRole;
  final String clientId;
  final String freelancerId;
  final String clientName;
  final String freelancerName;
  final String otherUserId;
  final String otherUserRole;
  final String otherUserName;
  final String otherUserPhotoUrl;
  final String title;
  final String description;
  final String amount;
  final String currency;
  final String deadlineText;
  final DateTime? deadlineDate;
  final String requestStatus;
  final String contractStatus;
  final String createdAtText;
  final DateTime? sortDate;
  final bool clientApproved;
  final bool freelancerApproved;
  final String fullContractText;
  final bool terminationRequested;
  final bool terminationApproved;
  final String terminationRequestedBy;
  final String terminationApprovedBy;
  final String terminationRequestedAt;
  final String terminationApprovedAt;
  final List<String> deletedBy;
  final List<String> summary;
  final int milestonesPaidCount;
  final int milestonesTotalCount;
  final bool clientHasSignature;
  final bool freelancerHasSignature;
  final String signedAtText;

  const GeneratedContract({
    required this.contractId,
    required this.requestId,
    required this.chatId,
    required this.userRole,
    required this.clientId,
    required this.freelancerId,
    required this.clientName,
    required this.freelancerName,
    required this.otherUserId,
    required this.otherUserRole,
    required this.otherUserName,
    required this.otherUserPhotoUrl,
    required this.title,
    required this.description,
    required this.amount,
    required this.currency,
    required this.deadlineText,
    required this.deadlineDate,
    required this.requestStatus,
    required this.contractStatus,
    required this.createdAtText,
    required this.sortDate,
    required this.clientApproved,
    required this.freelancerApproved,
    required this.fullContractText,
    required this.terminationRequested,
    required this.terminationApproved,
    required this.terminationRequestedBy,
    required this.terminationApprovedBy,
    required this.terminationRequestedAt,
    required this.terminationApprovedAt,
    required this.deletedBy,
    required this.summary,
    this.milestonesPaidCount = 0,
    this.milestonesTotalCount = 0,
    this.clientHasSignature = false,
    this.freelancerHasSignature = false,
    this.signedAtText = '',
  });

  factory GeneratedContract.fromRequest({
    required String requestId,
    required Map<String, dynamic> requestData,
    required String userRole,
    Map<String, dynamic>? otherUserData,
  }) {
    final normalizedRole = userRole.trim().toLowerCase();
    final contractData = _asMap(requestData['contractData']);
    final parties = _asMap(contractData['parties']);
    final meta = _asMap(contractData['meta']);
    final service = _asMap(contractData['service']);
    final payment = _asMap(contractData['payment']);
    final timeline = _asMap(contractData['timeline']);
    final approval = _asMap(contractData['approval']);
    final termination = _asMap(approval['termination']);
    final deletedBy = {
      ..._stringList(requestData['contractDeletedBy']),
      ..._stringList(contractData['deletedBy']),
    }.toList();

    final clientId = _stringValue(requestData['clientId']);
    final freelancerId = _stringValue(requestData['freelancerId']);

    final clientName = _firstFilled([
      parties['clientName'],
      requestData['clientName'],
      'Client',
    ]);
    final freelancerName = _firstFilled([
      parties['freelancerName'],
      requestData['freelancerName'],
      'Freelancer',
    ]);

    final otherUserId = normalizedRole == 'client' ? freelancerId : clientId;
    final otherUserRole = normalizedRole == 'client' ? 'freelancer' : 'client';
    final fallbackOtherName = normalizedRole == 'client'
        ? freelancerName
        : clientName;

    final otherUserName = _nameFromUserData(otherUserData, fallbackOtherName);
    final otherUserPhotoUrl = _firstFilled([
      otherUserData?['photoUrl'],
      otherUserData?['profile'],
    ]);

    final deadlineText = _firstFilled([
      timeline['deadline'],
      requestData['deadline'],
    ]);
    final createdAtText = _firstFilled([
      meta['createdAt'],
      _formatDate(_timestampToDate(requestData['createdAt'])),
    ]);
    final sortDate =
        _timestampToDate(requestData['updatedAt']) ??
        _timestampToDate(requestData['createdAt']) ??
        _parseDate(createdAtText);

    final rawSummary = meta['summary'];
    final summary = rawSummary is List
        ? rawSummary
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : <String>[];

    final description = _firstFilled([
      service['description'],
      requestData['description'],
    ]);

    final signatures = _asMap(contractData['signatures']);
    final clientHasSignature = _stringValue(
      signatures['clientSignature'],
    ).trim().isNotEmpty;
    final freelancerHasSignature = _stringValue(
      signatures['freelancerSignature'],
    ).trim().isNotEmpty;
    final signedAtText = _formatReadableDateTime(
      _stringValue(meta['approvedAt']),
    );

    final rawMilestones = contractData['milestones'];
    final milestonesTotalCount = rawMilestones is List
        ? rawMilestones.length
        : 0;
    final milestonesPaidCount = rawMilestones is List
        ? rawMilestones
              .where(
                (item) =>
                    _asMap(item)['status'].toString().trim().toLowerCase() ==
                    'paid',
              )
              .length
        : 0;

    return GeneratedContract(
      contractId: _firstFilled([
        contractData['contractId'],
        meta['contractId'],
        requestData['contractId'],
        requestId,
      ]),
      requestId: requestId,
      chatId: _stringValue(requestData['chatId']).trim().isEmpty
          ? null
          : _stringValue(requestData['chatId']),
      userRole: normalizedRole,
      clientId: clientId,
      freelancerId: freelancerId,
      clientName: clientName,
      freelancerName: freelancerName,
      otherUserId: otherUserId,
      otherUserRole: otherUserRole,
      otherUserName: otherUserName,
      otherUserPhotoUrl: otherUserPhotoUrl,
      title: _firstFilled([meta['title'], 'Contract Agreement']),
      description: description,
      amount: _firstFilled([payment['amount'], requestData['budget']]),
      currency: _firstFilled([
        payment['currency'],
        requestData['currency'],
        'SAR',
      ]),
      deadlineText: deadlineText,
      deadlineDate: _parseDate(deadlineText),
      requestStatus: _stringValue(requestData['status']).toLowerCase(),
      contractStatus: _stringValue(
        approval['contractStatus'],
        fallback: 'draft',
      ).toLowerCase(),
      createdAtText: createdAtText,
      sortDate: sortDate,
      clientApproved: approval['clientApproved'] == true,
      freelancerApproved: approval['freelancerApproved'] == true,
      fullContractText: _firstFilled([
        service['aiText'],
        contractData['contractText'],
        meta['contractText'],
      ]),
      terminationRequested: termination['requested'] == true,
      terminationApproved: termination['approved'] == true,
      terminationRequestedBy: _stringValue(termination['requestedBy']),
      terminationApprovedBy: _stringValue(termination['approvedBy']),
      terminationRequestedAt: _formatReadableDateTime(
        _stringValue(termination['requestedAt']),
      ),
      terminationApprovedAt: _formatReadableDateTime(
        _stringValue(termination['approvedAt']),
      ),
      deletedBy: deletedBy,
      summary: summary,
      milestonesPaidCount: milestonesPaidCount,
      milestonesTotalCount: milestonesTotalCount,
      clientHasSignature: clientHasSignature,
      freelancerHasSignature: freelancerHasSignature,
      signedAtText: signedAtText,
    );
  }

  ContractStatusGroup get group {
    if (isTerminated) {
      return ContractStatusGroup.terminated;
    }

    if (isPast) {
      return ContractStatusGroup.past;
    }

    if (isOngoingStatus && !hasDeadlinePassed) {
      return ContractStatusGroup.ongoing;
    }

    return ContractStatusGroup.ongoing;
  }

  bool get isTerminated =>
      contractStatus == 'terminated' || contractStatus == 'admin_terminated';

  bool get isPast {
    return contractStatus == 'past' || isCompleted || hasDeadlinePassed;
  }

  bool get canDelete {
    final status = contractStatus.trim().toLowerCase();

    if (hasDeadlinePassed) return true;

    return status == 'terminated' ||
        status == 'admin_terminated' ||
        status == 'rejected' ||
        status == 'cancelled' ||
        status == 'canceled';
  }

  bool isDeletedFor(String uid) {
    return deletedBy.contains(uid);
  }

  bool get isCompleted {
    return contractStatus == 'completed' || requestStatus == 'completed';
  }

  bool get isOngoingStatus {
    return contractStatus == 'ongoing' ||
        contractStatus == 'approved' ||
        contractStatus == 'pending_approval' ||
        contractStatus == 'draft' ||
        contractStatus == 'edited' ||
        contractStatus == 'termination_pending';
  }

  bool get hasDeadlinePassed {
    final deadline = deadlineDate;
    if (deadline == null) return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final normalizedDeadline = DateTime(
      deadline.year,
      deadline.month,
      deadline.day,
    );

    return today.isAfter(normalizedDeadline);
  }

  String get statusLabel {
    switch (contractStatus) {
      case 'approved':
        return 'Approved';
      case 'ongoing':
        return 'Ongoing';
      case 'completed':
        return 'Completed';
      case 'past':
        return 'Past';
      case 'pending_approval':
        return 'Waiting';
      case 'termination_pending':
        return 'Termination Pending';
      case 'terminated':
        return 'Terminated';
      case 'admin_terminated':
        return 'Terminated';
      case 'rejected':
        return 'Rejected';
      case 'edited':
        return 'Edited';
      case 'draft':
        return 'Draft';
      default:
        return contractStatus.isEmpty ? 'Draft' : _titleCase(contractStatus);
    }
  }

  String get otherPartyLabel {
    final role = otherUserRole == 'freelancer' ? 'Freelancer' : 'Client';
    return '$role: $otherUserName';
  }

  String get amountLabel {
    if (amount.isEmpty) return '-';
    if (currency.isEmpty) return amount;
    return '$amount $currency';
  }

  /// "2 of 3 milestones paid" for contracts on the 30/40/30 payment
  /// schedule, or '' for contracts generated before that schedule shipped
  /// (no `milestones` array at all) — those keep the single lump-sum flow
  /// and have nothing milestone-related to show here.
  String get milestoneProgressLabel {
    if (milestonesTotalCount == 0) return '';
    return '$milestonesPaidCount of $milestonesTotalCount milestones paid';
  }

  String get approvalStatusLabel {
    final clientStatus = clientApproved ? 'approved' : 'pending';
    final freelancerStatus = freelancerApproved ? 'approved' : 'pending';
    return 'Client $clientStatus, Freelancer $freelancerStatus';
  }

  String get terminationStatusLabel {
    if (contractStatus == 'terminated' ||
        contractStatus == 'admin_terminated') {
      final approvedBy = _roleLabel(terminationApprovedBy);
      final approvedAt = terminationApprovedAt.isEmpty
          ? ''
          : ' on $terminationApprovedAt';

      if (approvedBy.isNotEmpty) {
        return 'Terminated after approval by $approvedBy$approvedAt';
      }

      return 'Terminated';
    }

    if (contractStatus == 'termination_pending' || terminationRequested) {
      final requestedBy = _roleLabel(terminationRequestedBy);
      final requestedAt = terminationRequestedAt.isEmpty
          ? ''
          : ' on $terminationRequestedAt';

      if (requestedBy.isNotEmpty) {
        return 'Termination requested by $requestedBy$requestedAt';
      }

      return 'Termination requested';
    }

    return '';
  }

  String get previewText {
    if (summary.isNotEmpty) return summary.first;
    if (description.isNotEmpty) return description;
    return 'No contract description available.';
  }

  static bool hasContractData(Map<String, dynamic> requestData) {
    final contractData = requestData['contractData'];
    return contractData is Map && contractData.isNotEmpty;
  }

  static bool isDeletedForUser(Map<String, dynamic> requestData, String uid) {
    final contractData = _asMap(requestData['contractData']);
    return _stringList(requestData['contractDeletedBy']).contains(uid) ||
        _stringList(contractData['deletedBy']).contains(uid);
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<String> _stringList(dynamic value) {
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    return const <String>[];
  }

  static DateTime? _timestampToDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static String _formatDate(DateTime? value) {
    if (value == null) return '';
    return '${value.day}/${value.month}/${value.year}';
  }

  static String _formatReadableDateTime(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) return '';

    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;

    return _formatDate(parsed);
  }

  static String _firstFilled(List<dynamic> values) {
    for (final value in values) {
      final text = _stringValue(value).trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _stringValue(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static String _nameFromUserData(
    Map<String, dynamic>? userData,
    String fallback,
  ) {
    if (userData == null) return fallback.isEmpty ? 'User' : fallback;

    final firstName = _stringValue(userData['firstName']);
    final lastName = _stringValue(userData['lastName']);
    final fullName = '$firstName $lastName'.trim();
    final displayName = _firstFilled([userData['name'], fullName, fallback]);

    return displayName.isEmpty ? 'User' : displayName;
  }

  static DateTime? _parseDate(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return null;

    final isoDate = DateTime.tryParse(raw);
    if (isoDate != null) {
      return DateTime(isoDate.year, isoDate.month, isoDate.day);
    }

    final normalized = raw.replaceAll('-', '/').replaceAll('.', '/');
    final parts = normalized
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

  static String _titleCase(String value) {
    final words = value.replaceAll('_', ' ').split(' ');
    return words
        .where((word) => word.trim().isNotEmpty)
        .map((word) {
          final trimmed = word.trim().toLowerCase();
          return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
        })
        .join(' ');
  }

  static String _roleLabel(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized == 'client') return 'Client';
    if (normalized == 'freelancer') return 'Freelancer';
    return '';
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/contract_model.dart';

enum ContractSection { requiresAction, inProgress, history }

class ContractsController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<GeneratedContract>> _contractsFromDocs({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required String normalizedRole,
    required String currentUid,
  }) async {
    final contractDocs = docs.where((doc) {
      final data = doc.data();
      return GeneratedContract.hasContractData(data) &&
          !GeneratedContract.isDeletedForUser(data, currentUid);
    }).toList();

    return Future.wait(
      contractDocs.map((doc) async {
        final data = doc.data();
        final otherUserId = normalizedRole == 'client'
            ? (data['freelancerId'] ?? '').toString()
            : (data['clientId'] ?? '').toString();

        Map<String, dynamic>? otherUserData;
        if (otherUserId.trim().isNotEmpty) {
          final otherUserDoc = await _firestore
              .collection('users')
              .doc(otherUserId)
              .get();
          otherUserData = otherUserDoc.data();
        }

        return GeneratedContract.fromRequest(
          requestId: doc.id,
          requestData: data,
          userRole: normalizedRole,
          otherUserData: otherUserData,
        );
      }),
    );
  }

  // Contracts can come from two different hiring flows that live in two
  // different collections: direct requests ("requests") and accepted
  // announcement proposals ("announcement_requests"). Only reading
  // "requests" hid every contract created via the announcement/proposal
  // flow from this screen, so both sources are combined here the same way
  // the backend's contract endpoints already look in both places.
  Stream<List<GeneratedContract>> getGeneratedContracts({
    String? userRole,
    ContractStatusGroup? group,
  }) {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(const <GeneratedContract>[]);
    }

    final controller = StreamController<List<GeneratedContract>>.broadcast();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? requestsSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
    announcementSub;
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? latestRequestDocs;
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? latestAnnouncementDocs;

    Future<void> emitCombined(String normalizedRole) async {
      if (latestRequestDocs == null || latestAnnouncementDocs == null) {
        return;
      }
      if (controller.isClosed) return;

      try {
        final contracts = [
          ...await _contractsFromDocs(
            docs: latestRequestDocs!,
            normalizedRole: normalizedRole,
            currentUid: user.uid,
          ),
          ...await _contractsFromDocs(
            docs: latestAnnouncementDocs!,
            normalizedRole: normalizedRole,
            currentUid: user.uid,
          ),
        ];

          final filteredContracts = group == null
              ? contracts
              : filterContracts(contracts: contracts, group: group);

          filteredContracts.sort((a, b) {
            final aDate = a.sortDate;
            final bDate = b.sortDate;

            if (aDate == null && bDate == null) {
              return a.title.compareTo(b.title);
            }
            if (aDate == null) return 1;
            if (bDate == null) return -1;

            return bDate.compareTo(aDate);
          });

          final requiresActionContracts = <GeneratedContract>[];
          final inProgressContracts = <GeneratedContract>[];
          final historyContracts = <GeneratedContract>[];

          for (final contract in filteredContracts) {
            switch (getContractSection(contract)) {
              case ContractSection.requiresAction:
                requiresActionContracts.add(contract);
                break;
              case ContractSection.inProgress:
                inProgressContracts.add(contract);
                break;
              case ContractSection.history:
                historyContracts.add(contract);
                break;
            }
          }

          int compareByRecentActivity(
            GeneratedContract a,
            GeneratedContract b,
          ) {
            final aDate = a.sortDate;
            final bDate = b.sortDate;

            if (aDate == null && bDate == null) {
              return a.title.compareTo(b.title);
            }
            if (aDate == null) return 1;
            if (bDate == null) return -1;

            return bDate.compareTo(aDate);
          }

        requiresActionContracts.sort(compareByRecentActivity);
        inProgressContracts.sort(compareByRecentActivity);
        historyContracts.sort(compareByRecentActivity);

        controller.add([
          ...requiresActionContracts,
          ...inProgressContracts,
          ...historyContracts,
        ]);
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    _resolveUserRole(uid: user.uid, providedRole: userRole)
        .then((normalizedRole) {
          if (controller.isClosed) return;
          final participantField = normalizedRole == 'client'
              ? 'clientId'
              : 'freelancerId';

          requestsSub = _firestore
              .collection('requests')
              .where(participantField, isEqualTo: user.uid)
              .snapshots()
              .listen(
                (snapshot) {
                  latestRequestDocs = snapshot.docs;
                  unawaited(emitCombined(normalizedRole));
                },
                onError: controller.addError,
              );

          announcementSub = _firestore
              .collection('announcement_requests')
              .where(participantField, isEqualTo: user.uid)
              .snapshots()
              .listen(
                (snapshot) {
                  latestAnnouncementDocs = snapshot.docs;
                  unawaited(emitCombined(normalizedRole));
                },
                onError: controller.addError,
              );
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!controller.isClosed) {
            controller.addError(error, stackTrace);
          }
        });

    controller.onCancel = () async {
      await requestsSub?.cancel();
      await announcementSub?.cancel();
    };

    return controller.stream;
  }

  List<GeneratedContract> filterContracts({
    required List<GeneratedContract> contracts,
    required ContractStatusGroup group,
  }) {
    return contracts.where((contract) => contract.group == group).toList();
  }

  ContractSection getContractSection(GeneratedContract contract) {
    final status = contract.contractStatus.trim().toLowerCase();
    final currentUserApproved = contract.userRole == 'client'
        ? contract.clientApproved
        : contract.freelancerApproved;
    final terminationNeedsUserAction =
        status == 'termination_pending' &&
        contract.terminationRequested &&
        contract.terminationRequestedBy.trim().toLowerCase() !=
            contract.userRole.trim().toLowerCase();

    if ((!currentUserApproved &&
            (status == 'draft' ||
                status == 'edited' ||
                status == 'pending_approval')) ||
        terminationNeedsUserAction) {
      return ContractSection.requiresAction;
    }

    if (status == 'rejected' ||
        status == 'admin_terminated' ||
        status == 'terminated' ||
        status == 'admin_terminated' ||
        status == 'cancelled' ||
        status == 'canceled' ||
        contract.hasDeadlinePassed) {
      return ContractSection.history;
    }

    if (status == 'approved' && !contract.hasDeadlinePassed) {
      return ContractSection.inProgress;
    }

    return ContractSection.history;
  }

  Future<void> deleteContract(GeneratedContract contract) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No logged in user found.');
    }

    final contractId = contract.contractId.trim();
    if (contractId.isEmpty) {
      throw Exception('Contract ID is missing.');
    }

    if (!contract.canDelete) {
      throw Exception('Ongoing contracts cannot be deleted.');
    }

    final requestRef = await _findRequestRefByContractId(
      contractId: contractId,
      fallbackRequestId: contract.requestId,
    );
    if (requestRef == null) {
      throw Exception('Contract not found.');
    }

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(requestRef);
      final contractRef = _firestore.collection('contracts').doc(contractId);
      final contractSnapshot = await transaction.get(contractRef);
      final data = snapshot.data();

      if (data == null || !GeneratedContract.hasContractData(data)) {
        throw Exception('Contract not found.');
      }

      final latestClientId = (data['clientId'] ?? '').toString();
      final latestFreelancerId = (data['freelancerId'] ?? '').toString();
      final isParticipant =
          user.uid == latestClientId || user.uid == latestFreelancerId;
      if (!isParticipant) {
        throw Exception('You are not allowed to delete this contract.');
      }

      final latestContract = GeneratedContract.fromRequest(
        requestId: snapshot.id,
        requestData: data,
        userRole: contract.userRole,
      );

      if (latestContract.contractId != contractId) {
        throw Exception('Contract not found.');
      }

      if (!latestContract.canDelete) {
        throw Exception('Ongoing contracts cannot be deleted.');
      }

      transaction.set(requestRef, {
        'contractDeletedBy': FieldValue.arrayUnion([user.uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (contractSnapshot.exists) {
        transaction.set(contractRef, {
          'deletedBy': FieldValue.arrayUnion([user.uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  Future<DocumentReference<Map<String, dynamic>>?> _findRequestRefByContractId({
    required String contractId,
    required String fallbackRequestId,
  }) async {
    // Contracts live in either "requests" (direct hires) or
    // "announcement_requests" (accepted announcement proposals) — both are
    // checked so deleting a contract works regardless of which flow
    // created it, same as the read side above.
    final collections = [
      _firestore.collection('requests'),
      _firestore.collection('announcement_requests'),
    ];
    final checkedIds = <String>{};

    for (final collection in collections) {
      for (final id in [contractId, fallbackRequestId]) {
        final trimmedId = id.trim();
        final dedupeKey = '${collection.path}/$trimmedId';
        if (trimmedId.isEmpty || checkedIds.contains(dedupeKey)) continue;
        checkedIds.add(dedupeKey);

        final doc = await collection.doc(trimmedId).get();
        final data = doc.data();
        if (data == null || !GeneratedContract.hasContractData(data)) {
          continue;
        }

        final foundContract = GeneratedContract.fromRequest(
          requestId: doc.id,
          requestData: data,
          userRole: '',
        );

        if (foundContract.contractId == contractId) {
          return doc.reference;
        }
      }
    }

    final queryFields = [
      'contractId',
      'contractData.contractId',
      'contractData.meta.contractId',
    ];

    for (final collection in collections) {
      for (final field in queryFields) {
        final snapshot = await collection
            .where(field, isEqualTo: contractId)
            .limit(1)
            .get();

        if (snapshot.docs.isNotEmpty) {
          return snapshot.docs.first.reference;
        }
      }
    }

    return null;
  }

  Future<String> _resolveUserRole({
    required String uid,
    required String? providedRole,
  }) async {
    final normalizedProvidedRole = (providedRole ?? '').trim().toLowerCase();
    if (normalizedProvidedRole == 'client' ||
        normalizedProvidedRole == 'freelancer') {
      return normalizedProvidedRole;
    }

    final userDoc = await _firestore.collection('users').doc(uid).get();
    final accountType = (userDoc.data()?['accountType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (accountType == 'client' || accountType == 'freelancer') {
      return accountType;
    }

    throw Exception('Unsupported user role');
  }
}

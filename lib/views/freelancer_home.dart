import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'freelancer_profile.dart';
import 'freelancer_incoming_requests_view.dart';
import 'browse_announcements_view.dart';
import 'my_announcement_requests_view.dart';
import '../controlles/freelancer_profile_controller.dart';
import 'chat_list_view.dart';
import 'contracts_list_screen.dart';
import '../controlles/chat_controller.dart';
import '../controlles/notification_navigation_service.dart';
import '../controlles/request_notifications_controller.dart';
import 'request_notifications_sheet.dart';
import 'favorites_list_view.dart';

class FreelancerHomeView extends StatefulWidget {
  const FreelancerHomeView({super.key});

  @override
  State<FreelancerHomeView> createState() => _FreelancerHomeViewState();
}

class _FreelancerHomeViewState extends State<FreelancerHomeView> {
  static const primary = Color(0xFF5A3E9E);
  static const Color _inactiveNav = Color(0xFF9A92B8);

  final TextEditingController _searchController = TextEditingController();
  final FreelancerProfileController _profileController =
      FreelancerProfileController();
  final RequestNotificationsController _notificationsController =
      RequestNotificationsController();

  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FreelancerProfileView()),
    );

    await _profileController.init();
  }

  void _openIncomingRequests() {
    if (!_profileController.hasRequiredProfileData) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FreelancerIncomingRequestsView()),
    );
  }

  void _openBrowseAnnouncements() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BrowseAnnouncementsView()),
    );
  }

  void _openMyAnnouncementRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyAnnouncementRequestsView()),
    );
  }

  void _openContracts() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ContractsListScreen()),
    );
  }

  void _openFavorites() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FavoritesListView()),
    );
  }

  void _comingSoon(String title) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$title coming soon')));
  }

  Future<void> _openNotificationTarget(RequestNotificationItem item) async {
    if (!mounted) return;
    Navigator.pop(context);

    await handleNotificationTap(context: context, notification: item);
  }

  void _openNotificationsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.8,
        child: RequestNotificationsSheet(
          controller: _notificationsController,
          onOpen: _openNotificationTarget,
        ),
      ),
    );
  }

  Widget _buildNotificationBell() {
    return StreamBuilder<int>(
      stream: _notificationsController.unreadCountStream(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: _openNotificationsSheet,
              icon: const Icon(
                Icons.notifications_none,
                color: primary,
                size: 26,
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 16,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _filterChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _profileController.init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _profileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: _FreelancerBottomNavigationBar(
        primary: primary,
        onChatsTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ChatListView()),
          );
        },
        onHomeTap: () {},
        onContractsTap: _openContracts,
        onFavoritesTap: _openFavorites,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final contentMaxWidth = w > 700 ? 560.0 : w;
            final padding = w > 700 ? 24.0 : 16.0;

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(padding, 0, padding, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// Top bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: _openProfile,
                                child:
                                    StreamBuilder<
                                      DocumentSnapshot<Map<String, dynamic>>
                                    >(
                                      stream: user == null
                                          ? const Stream.empty()
                                          : FirebaseFirestore.instance
                                                .collection('users')
                                                .doc(user.uid)
                                                .snapshots(),
                                      builder: (context, snapshot) {
                                        final data = snapshot.data?.data();
                                        final profileUrl =
                                            (data?['profile'] ?? '').toString();

                                        final name = (data?['firstName'] ?? '')
                                            .toString();

                                        return Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 20,
                                              backgroundColor: primary
                                                  .withOpacity(0.12),
                                              backgroundImage:
                                                  profileUrl.isNotEmpty
                                                  ? NetworkImage(profileUrl)
                                                  : null,
                                              child: profileUrl.isEmpty
                                                  ? const Icon(
                                                      Icons.person_outline,
                                                      color: primary,
                                                      size: 22,
                                                    )
                                                  : null,
                                            ),

                                            const SizedBox(width: 10),

                                            Text(
                                              'Welcome, $name!',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: primary,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                              ),
                            ],
                          ),

                          _buildNotificationBell(),
                        ],
                      ),

                      const SizedBox(height: 20),

                      const SizedBox(height: 18),

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Find Opportunities",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: primary,
                            ),
                          ),

                          const SizedBox(height: 6),

                          const Text(
                            "Browse client requests or track your submitted proposals",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                            ),
                          ),

                          const SizedBox(height: 14),
                        ],
                      ),
                      Column(
                        children: [
                          // Browse
                          InkWell(
                            onTap: _openBrowseAnnouncements,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE9E0FA),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: const [
                                  Icon(Icons.search, color: primary, size: 20),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      "Browse Client Requests",
                                      style: TextStyle(
                                        color: primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: Colors.black45,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // My Requests
                          InkWell(
                            onTap: _openMyAnnouncementRequests,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: primary.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: const [
                                  Icon(
                                    Icons.assignment_outlined,
                                    color: primary,
                                    size: 20,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      "My Sent Proposals",
                                      style: TextStyle(
                                        color: primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: Colors.black45,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 22),

                      /// Incoming Requests + See all
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Incoming Requests",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: primary,
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _profileController,
                            builder: (context, _) {
                              final enabled =
                                  _profileController.hasRequiredProfileData;

                              return TextButton(
                                onPressed: enabled
                                    ? _openIncomingRequests
                                    : null,
                                child: Text(
                                  "See all",
                                  style: TextStyle(
                                    color: enabled
                                        ? Colors.black54
                                        : Colors.grey[400],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      AnimatedBuilder(
                        animation: _profileController,
                        builder: (context, _) {
                          if (_profileController.isLoading) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          final isReady =
                              _profileController.hasRequiredProfileData;

                          if (!isReady) {
                            final missing =
                                _profileController.missingRequiredFields;

                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFDF7),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.notifications,
                                    color: Color(0xFFFFC107),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Complete the required profile details to become visible to clients:',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        ...missing.map(
                                          (item) => Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            child: Text(
                                              '• $item',
                                              style: const TextStyle(
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFFFFE082,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          onPressed: _openProfile,
                                          child: const Text('Complete Profile'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>
                          >(
                            stream: user == null
                                ? const Stream.empty()
                                : FirebaseFirestore.instance
                                      .collection('requests')
                                      .where(
                                        'freelancerId',
                                        isEqualTo: user.uid,
                                      )
                                      .where('status', isEqualTo: 'pending')
                                      .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              if (snapshot.hasError) {
                                return const Text('Something went wrong');
                              }

                              final docs = snapshot.data?.docs ?? [];

                              if (docs.isEmpty) {
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF6F2FB),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Text(
                                    'No incoming requests yet.',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                );
                              }

                              final previewDocs = docs.take(3).toList();

                              return Column(
                                children: previewDocs.map((doc) {
                                  final data = doc.data();

                                  final clientName =
                                      (data['clientName'] ?? 'Client')
                                          .toString();
                                  final description =
                                      (data['description'] ?? '').toString();
                                  final clientId = (data['clientId'] ?? '')
                                      .toString();

                                  return GestureDetector(
                                    onTap: _openIncomingRequests,
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF6F2FB),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child:
                                          StreamBuilder<
                                            DocumentSnapshot<
                                              Map<String, dynamic>
                                            >
                                          >(
                                            stream: FirebaseFirestore.instance
                                                .collection('users')
                                                .doc(clientId)
                                                .snapshots(),
                                            builder: (context, snapshot) {
                                              final userData = snapshot.data
                                                  ?.data();

                                              final firstName =
                                                  (userData?['firstName'] ?? '')
                                                      .toString()
                                                      .trim();
                                              final lastName =
                                                  (userData?['lastName'] ?? '')
                                                      .toString()
                                                      .trim();

                                              final latestName =
                                                  ('$firstName $lastName')
                                                      .trim()
                                                      .isEmpty
                                                  ? clientName
                                                  : ('$firstName $lastName')
                                                        .trim();

                                              final imageUrl =
                                                  (userData?['photoUrl'] ??
                                                          userData?['profile'] ??
                                                          '')
                                                      .toString()
                                                      .trim();

                                              return Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 22,
                                                    backgroundColor: primary
                                                        .withOpacity(0.12),
                                                    backgroundImage:
                                                        imageUrl.isNotEmpty
                                                        ? NetworkImage(imageUrl)
                                                        : null,
                                                    child: imageUrl.isEmpty
                                                        ? const Icon(
                                                            Icons
                                                                .person_outline,
                                                            color: primary,
                                                            size: 22,
                                                          )
                                                        : null,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          latestName,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Colors
                                                                    .black87,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          description.isEmpty
                                                              ? '-'
                                                              : description,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                                color: Colors
                                                                    .black54,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const Icon(
                                                    Icons
                                                        .arrow_forward_ios_rounded,
                                                    size: 18,
                                                    color: Colors.black54,
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 30),
                    ],
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

class _FreelancerBottomNavigationBar extends StatelessWidget {
  final Color primary;
  final VoidCallback onChatsTap;
  final VoidCallback onHomeTap;
  final VoidCallback onContractsTap;
  final VoidCallback onFavoritesTap;

  const _FreelancerBottomNavigationBar({
    required this.primary,
    required this.onChatsTap,
    required this.onHomeTap,
    required this.onContractsTap,
    required this.onFavoritesTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 14, 30, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          StreamBuilder<int>(
            stream: ChatController().getTotalUnreadCount(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;

              return GestureDetector(
                onTap: onChatsTap,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      color: _FreelancerHomeViewState._inactiveNav,
                      size: 28,
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: -8,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : unreadCount.toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          GestureDetector(
            onTap: onHomeTap,
            // نفس شكل ولون باقي أيقونات الشريط تماماً (بدون دائرة
            // بنفسجية خلفها).
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Icon(
                  Icons.home_outlined,
                  color: _FreelancerHomeViewState._inactiveNav,
                  size: 28,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: onContractsTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Icon(
                  Icons.description_outlined,
                  color: _FreelancerHomeViewState._inactiveNav,
                  size: 27,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: onFavoritesTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Icon(
                  Icons.favorite_border_rounded,
                  color: _FreelancerHomeViewState._inactiveNav,
                  size: 27,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

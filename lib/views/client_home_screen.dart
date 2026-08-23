//تمت
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:saneea_app/views/client_profile.dart';

import 'announcement_requests_view.dart';
import 'request_action_button.dart';
import 'freelancer_profile.dart';
import 'my_requests_view.dart';
import 'recommendation_view.dart';
import 'anouncment_view.dart';
import 'contracts_list_screen.dart';
import '../controlles/chat_controller.dart';
import 'chat_list_view.dart';
import '../controlles/notification_navigation_service.dart';
import '../controlles/request_notifications_controller.dart';
import 'request_notifications_sheet.dart';
import 'favorites_list_view.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  static const Color _primary = Color(0xFF5A3E9E);
  static const Color _inactiveNav = Color(0xFF9A92B8);

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _categoryScrollController = ScrollController();
  final RequestNotificationsController _notificationsController =
      RequestNotificationsController();

  // Owns the horizontal category-row scroll indicator on its own so that
  // scrolling the category chips doesn't setState() the whole screen —
  // it used to, which tore down and recreated the Top Rated / Service
  // Requests StreamBuilders below on every scroll frame (see the cached
  // stream fields below for the other half of that fix).
  final ValueNotifier<double> _categoryScrollProgress = ValueNotifier<double>(
    0.0,
  );

  // Cached once instead of re-created on every build() — these used to be
  // methods called inline from build(), which opened a brand new Firestore
  // listener (and reset the StreamBuilder to its loading state) on every
  // single rebuild, including the frequent rebuilds the category-row
  // scroll listener used to trigger.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>
  _clientProfileStream = _buildClientProfileStream();
  late final Stream<QuerySnapshot<Map<String, dynamic>>>
  _myAnnouncementsStream = _buildMyAnnouncementsStream();
  late final Stream<QuerySnapshot<Map<String, dynamic>>>
  _allFreelancersStream = _buildAllFreelancersStream();

  final List<_CategoryModel> _categories = const [
    _CategoryModel(
      title: "Graphic\nDesigners",
      icon: Icons.brush_outlined,
      serviceField: "Graphic Designers",
    ),
    _CategoryModel(
      title: "Marketing",
      icon: Icons.campaign_outlined,
      serviceField: "Marketing",
    ),
    _CategoryModel(
      title: "Software\nDevelopers",
      icon: Icons.code_outlined,
      serviceField: "Software Developers",
    ),
    _CategoryModel(
      title: "Accounting",
      icon: Icons.account_balance_wallet_outlined,
      serviceField: "Accounting",
    ),
    _CategoryModel(
      title: "Tutoring",
      icon: Icons.school_outlined,
      serviceField: "Tutoring",
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _categoryScrollController.dispose();
    _categoryScrollProgress.dispose();
    super.dispose();
  }

  double _clamp(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  double _parseRating(dynamic value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _buildClientProfileStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>
  _buildMyAnnouncementsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _buildAllFreelancersStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .where('accountType', isEqualTo: 'freelancer')
        .snapshots();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applySearchFilter(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return docs;

    return docs.where((doc) {
      final data = doc.data();
      final firstName = (data['firstName'] ?? '').toString().toLowerCase();
      final lastName = (data['lastName'] ?? '').toString().toLowerCase();
      final serviceField = (data['serviceField'] ?? '')
          .toString()
          .toLowerCase();
      final fullName = '$firstName $lastName'.trim();
      final combined = '$fullName $serviceField';

      return combined.contains(query);
    }).toList();
  }

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    if (result.every((r) => r == ConnectivityResult.none)) return false;

    // على الويب: navigator.onLine (اللي يعتمد عليه connectivity_plus)
    // كافي، وأي طلب خارجي إضافي (زي gstatic) يرفضه المتصفح بسبب CORS
    // حتى لو السيرفر رد فعلياً، فيرجع "لا يوجد اتصال" بشكل خاطئ.
    if (kIsWeb) return true;

    try {
      final response = await http
          .get(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void _openAllServiceRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AllServiceRequestsView()),
    );
  }

  void _openAnnouncement() async {
    try {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const AnnouncementView()),
      );

      if (!mounted) return;

      if (result == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Published successfully ✅')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error opening page: $e')));
    }
  }

  void _openRecommendationPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecommendationView()),
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

  void _openCategoryPage(_CategoryModel category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FreelancersByCategoryPage(
          title: category.title.replaceAll('\n', ' '),
          serviceField: category.serviceField,
        ),
      ),
    );
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
                color: _primary,
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

  Widget _buildCategoryScrollIndicator() {
    const double trackWidth = 140;
    const double indicatorWidth = 42;

    return SizedBox(
      width: trackWidth,
      height: 4,
      child: Stack(
        children: [
          Container(
            width: trackWidth,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: _categoryScrollProgress,
            builder: (context, progress, _) {
              return Positioned(
                left: progress * (trackWidth - indicatorWidth),
                child: Container(
                  width: indicatorWidth,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAnnouncement(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Service Request?'),
        content: const Text('This action cannot be undone.'),
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

    if (confirm != true) return;

    final online = await _hasInternet();
    if (!online) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Please try again.'),
        ),
      );
      return;
    }

    try {
      await doc.reference.delete();

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Deleted successfully ✅')));
    } on FirebaseException catch (e) {
      if (!context.mounted) return;

      final isNetworkError =
          e.code == 'unavailable' || e.code == 'network-request-failed';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNetworkError
                ? 'No internet connection. Please try again.'
                : 'Something went wrong. Please try again.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  Widget _buildProfileAvatar() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _clientProfileStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final photoUrl = (data?['photoUrl'] ?? data?['profile'] ?? '')
            .toString();

        return CircleAvatar(
          radius: 20,
          backgroundColor: _primary.withOpacity(0.12),
          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: photoUrl.isEmpty
              ? const Icon(Icons.person_outline, color: _primary, size: 22)
              : null,
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, double width) {
    return Text(
      title,
      style: TextStyle(
        fontSize: _clamp(width * 0.055, 20, 24),
        fontWeight: FontWeight.w700,
        color: _primary,
      ),
    );
  }

  Widget _buildSearchResults() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _allFreelancersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Text('Error loading search results: ${snapshot.error}');
        }

        final allDocs = snapshot.data?.docs ?? [];
        final docs = _applySearchFilter(allDocs);

        if (docs.isEmpty) {
          return const Text('No matching freelancers found.');
        }

        return Column(
          children: docs.map((doc) {
            final data = doc.data();
            final firstName = (data['firstName'] ?? '').toString();
            final lastName = (data['lastName'] ?? '').toString();
            final fullName = '$firstName $lastName'.trim().isEmpty
                ? 'No Name'
                : '$firstName $lastName'.trim();
            final serviceField = (data['serviceField'] ?? '').toString();
            final rating = _parseRating(data['rating']);
            final photoUrl = (data['photoUrl'] ?? data['profile'] ?? '')
                .toString();

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F2FB),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: FreelancerCardSimple(
                  name: fullName,
                  role: serviceField,
                  rating: rating,
                  photoUrl: photoUrl,
                  imageRadius: 20,
                  nameFontSize: 13,
                  roleFontSize: 12,
                  starSize: 14,
                  linkFontSize: 10.5,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FreelancerProfileView(userId: doc.id),
                      ),
                    );
                  },
                  requestAction: SendRequestButton(
                    freelancerId: doc.id,
                    freelancerName: fullName,
                    iconOnly: true,
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildTopRated() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _allFreelancersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Text('Error loading top rated: ${snapshot.error}');
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Text('No top rated freelancers');
        }

        final docs = snapshot.data!.docs.where((doc) {
          final rating = _parseRating(doc.data()['rating']);
          return rating >= 4.5;
        }).toList();

        docs.sort((a, b) {
          final ratingA = _parseRating(a.data()['rating']);
          final ratingB = _parseRating(b.data()['rating']);
          return ratingB.compareTo(ratingA);
        });

        if (docs.isEmpty) {
          return const Text('No top rated freelancers');
        }

        final top4 = docs.take(4).toList();

        return Column(
          children: top4.map((doc) {
            final data = doc.data();
            final firstName = (data['firstName'] ?? '').toString();
            final lastName = (data['lastName'] ?? '').toString();
            final fullName = '$firstName $lastName'.trim().isEmpty
                ? 'No Name'
                : '$firstName $lastName'.trim();
            final serviceField = (data['serviceField'] ?? '').toString();
            final rating = _parseRating(data['rating']);
            final photoUrl = (data['photoUrl'] ?? data['profile'] ?? '')
                .toString();

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F2FB),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: FreelancerCardSimple(
                  name: fullName,
                  role: serviceField,
                  rating: rating,
                  photoUrl: photoUrl,
                  imageRadius: 20,
                  nameFontSize: 13,
                  roleFontSize: 12,
                  starSize: 14,
                  linkFontSize: 10.5,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FreelancerProfileView(userId: doc.id),
                      ),
                    );
                  },
                  requestAction: SendRequestButton(
                    freelancerId: doc.id,
                    freelancerName: fullName,
                    iconOnly: true,
                    showGoToRequests: false,
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildMyServiceRequests({bool previewOnly = false}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _myAnnouncementsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }

        final allDocs = snapshot.data?.docs ?? [];
        final docs = previewOnly ? allDocs.take(3).toList() : allDocs;

        if (allDocs.isEmpty) {
          return const Text('No service requests yet.');
        }

        return Column(
          children: docs.map((doc) {
            final data = doc.data();
            final description = (data['description'] ?? '').toString();
            final budget = data['budget'];
            final deadline = (data['deadline'] ?? '').toString();

            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: ListTile(
                title: Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Text('Budget: ${budget ?? '-'} SAR'),
                    Text('Deadline: ${deadline.isEmpty ? '-' : deadline}'),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 34,
                      width: 190,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AnnouncementRequestsView(
                                announcementId: doc.id,
                                announcementDescription: description,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'View freelancer requests',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((data['status'] ?? 'pending') == 'pending')
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AnnouncementView(
                                announcementId: doc.id,
                                initialDescription: data['description'],
                                initialBudget: data['budget'],
                                initialDeadline: data['deadline'],
                              ),
                            ),
                          );
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteAnnouncement(context, doc),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: _BottomNavigationBar(
        primary: _primary,
        onCenterTap: _openAnnouncement,
        onContractsTap: _openContracts,
        onFavoritesTap: _openFavorites,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final contentMaxWidth = width > 700 ? 560.0 : width;
            final padding = _clamp(width * 0.06, 16, 28);
            final isSearching = _searchController.text.trim().isNotEmpty;

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(padding, 6, padding, padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const ClientProfile(),
                                    ),
                                  );
                                },
                                child: _buildProfileAvatar(),
                              ),
                              const SizedBox(width: 10),
                              StreamBuilder<
                                DocumentSnapshot<Map<String, dynamic>>
                              >(
                                stream: _clientProfileStream,
                                builder: (context, snapshot) {
                                  final data = snapshot.data?.data();
                                  final name = (data?['firstName'] ?? '')
                                      .toString();

                                  return Text(
                                    'Welcome, $name!',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color.fromARGB(255, 53, 21, 126),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          _buildNotificationBell(),
                        ],
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 46,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.search,
                                    color: Colors.grey.shade500,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      onChanged: (_) => setState(() {}),
                                      decoration: InputDecoration(
                                        hintText: "Search....",
                                        hintStyle: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 14,
                                        ),
                                        border: InputBorder.none,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _openRecommendationPage,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Color(0xFF4F378A),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.auto_awesome,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      SizedBox(
                        height: 120,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification.metrics.axis == Axis.horizontal) {
                              final maxScroll =
                                  notification.metrics.maxScrollExtent;

                              // ValueNotifier, not setState() — this fires on
                              // every scroll frame, and setState() here used
                              // to rebuild the entire screen (including the
                              // Top Rated / Service Requests sections below)
                              // on every one of those frames.
                              _categoryScrollProgress.value = maxScroll > 0
                                  ? (notification.metrics.pixels / maxScroll)
                                        .clamp(0.0, 1.0)
                                  : 0.0;
                            }
                            return false;
                          },
                          child: ListView.separated(
                            controller: _categoryScrollController,
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.zero,
                            itemCount: _categories.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 14),
                            itemBuilder: (context, index) {
                              final category = _categories[index];
                              return SizedBox(
                                width: 100,
                                child: GestureDetector(
                                  onTap: () => _openCategoryPage(category),
                                  child: _CategoryItem(
                                    title: category.title,
                                    icon: category.icon,
                                    primary: _primary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(child: _buildCategoryScrollIndicator()),
                      const SizedBox(height: 10),

                      if (isSearching) ...[
                        _buildSectionTitle("Search Results", width),
                        const SizedBox(height: 12),
                        _buildSearchResults(),
                        const SizedBox(height: 18),
                      ] else ...[
                        _buildSectionTitle("Top rated", width),
                        const SizedBox(height: 12),
                        _buildTopRated(),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Service Requests",
                              style: TextStyle(
                                fontSize: _clamp(width * 0.05, 18, 22),
                                fontWeight: FontWeight.w700,
                                color: _primary,
                              ),
                            ),
                            TextButton(
                              onPressed: _openAllServiceRequests,
                              child: const Text(
                                "See all",
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildMyServiceRequests(previewOnly: true),
                        const SizedBox(height: 30),
                      ],
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

class AllServiceRequestsView extends StatelessWidget {
  const AllServiceRequestsView({super.key});

  static const Color _primary = Color(0xFF5A3E9E);

  Stream<QuerySnapshot<Map<String, dynamic>>> _myAnnouncementsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    if (result.every((r) => r == ConnectivityResult.none)) return false;

    // على الويب: navigator.onLine (اللي يعتمد عليه connectivity_plus)
    // كافي، وأي طلب خارجي إضافي (زي gstatic) يرفضه المتصفح بسبب CORS
    // حتى لو السيرفر رد فعلياً، فيرجع "لا يوجد اتصال" بشكل خاطئ.
    if (kIsWeb) return true;

    try {
      final response = await http
          .get(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteAnnouncement(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Service Request?'),
        content: const Text('This action cannot be undone.'),
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

    if (confirm != true) return;

    final online = await _hasInternet();
    if (!online) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Please try again.'),
        ),
      );
      return;
    }

    try {
      await doc.reference.delete();

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Deleted successfully ✅')));
    } on FirebaseException catch (e) {
      if (!context.mounted) return;

      final isNetworkError =
          e.code == 'unavailable' || e.code == 'network-request-failed';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNetworkError
                ? 'No internet connection. Please try again.'
                : 'Something went wrong. Please try again.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Requests'),
        backgroundColor: Colors.white,
        foregroundColor: _primary,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _myAnnouncementsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(child: Text('No service requests yet.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final description = (data['description'] ?? '').toString();
              final budget = data['budget'];
              final deadline = (data['deadline'] ?? '').toString();

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    title: Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        Text('Budget: ${budget ?? '-'} SAR'),
                        Text('Deadline: ${deadline.isEmpty ? '-' : deadline}'),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 34,
                          width: 190,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AnnouncementRequestsView(
                                    announcementId: doc.id,
                                    announcementDescription: description,
                                    fromSeeAll: true,
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'View freelancer requests',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if ((data['status'] ?? 'pending') == 'pending')
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AnnouncementView(
                                    announcementId: doc.id,
                                    initialDescription: data['description'],
                                    initialBudget: data['budget'],
                                    initialDeadline: data['deadline'],
                                  ),
                                ),
                              );
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteAnnouncement(context, doc),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CategoryModel {
  final String title;
  final IconData icon;
  final String serviceField;

  const _CategoryModel({
    required this.title,
    required this.icon,
    required this.serviceField,
  });
}

class _CategoryItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color primary;

  const _CategoryItem({
    required this.title,
    required this.icon,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: Colors.grey.shade200,
          child: Icon(icon, color: primary, size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, height: 1.1),
        ),
      ],
    );
  }
}

class _BottomNavigationBar extends StatelessWidget {
  final Color primary;
  final VoidCallback onCenterTap;
  final VoidCallback onContractsTap;
  final VoidCallback onFavoritesTap;

  const _BottomNavigationBar({
    required this.primary,
    required this.onCenterTap,
    required this.onContractsTap,
    required this.onFavoritesTap,
  });

  Widget _filledCircle({
    required Color color,
    required IconData icon,
    required double iconSize,
    required double dimension,
  }) {
    return Container(
      width: dimension,
      height: dimension,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
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
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ChatListView()),
                  );
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      color: const Color.fromARGB(255, 96, 63, 214),
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
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyRequestsView()),
              );
            },
            child: Icon(
              Icons.inbox_outlined,
              color: const Color.fromARGB(255, 96, 63, 214),
              size: 28,
            ),
          ),
          GestureDetector(
            onTap: onCenterTap,
            child: _filledCircle(
              color: primary,
              icon: Icons.add_rounded,
              iconSize: 32,
              dimension: 60,
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
                  color: const Color.fromARGB(255, 96, 63, 214),
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
                  color: const Color.fromARGB(255, 96, 63, 214),
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

class FreelancerCardSimple extends StatelessWidget {
  final String name;
  final String role;
  final double rating;
  final String photoUrl;
  final VoidCallback onTap;
  final Widget? requestAction;
  final Widget? trailingTopAction;

  final double imageRadius;
  final double nameFontSize;
  final double roleFontSize;
  final double starSize;
  final double linkFontSize;

  const FreelancerCardSimple({
    super.key,
    required this.name,
    required this.role,
    required this.rating,
    required this.photoUrl,
    required this.onTap,
    this.requestAction,
    this.trailingTopAction,
    this.imageRadius = 24,
    this.nameFontSize = 15,
    this.roleFontSize = 14,
    this.starSize = 16,
    this.linkFontSize = 12,
  });

  Widget _buildStars(double rating) {
    return Row(
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return Icon(Icons.star, color: Colors.amber, size: starSize);
        } else if (index == rating.floor() && rating % 1 != 0) {
          return Icon(Icons.star_half, color: Colors.amber, size: starSize);
        } else {
          return Icon(Icons.star_border, color: Colors.amber, size: starSize);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF5A3E9E);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: imageRadius,
          backgroundColor: Colors.white,
          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: photoUrl.isEmpty
              ? Icon(Icons.person, color: primary, size: imageRadius + 4)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: nameFontSize,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  if (trailingTopAction != null) ...[
                    const SizedBox(width: 6),
                    trailingTopAction!,
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                role,
                style: TextStyle(color: primary, fontSize: roleFontSize),
              ),
              const SizedBox(height: 6),
              _buildStars(rating),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 3),
                child: SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'View Profile',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (requestAction != null) ...[
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [if (requestAction != null) requestAction!],
          ),
        ],
      ],
    );
  }
}

class FreelancersByCategoryPage extends StatefulWidget {
  final String title;
  final String serviceField;

  const FreelancersByCategoryPage({
    super.key,
    required this.title,
    required this.serviceField,
  });

  @override
  State<FreelancersByCategoryPage> createState() =>
      _FreelancersByCategoryPageState();
}

class _FreelancersByCategoryPageState extends State<FreelancersByCategoryPage> {
  String? selectedServiceType;
  String? selectedWorkingMode;
  String? selectedMinRating;

  double _parseRating(dynamic value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final data = doc.data();
      final rating = _parseRating(data['rating']);
      final serviceType = (data['serviceType'] ?? '').toString().trim();
      final workingMode = (data['workingMode'] ?? '').toString().trim();

      if (selectedMinRating != null && selectedMinRating!.isNotEmpty) {
        final minRating = double.tryParse(selectedMinRating!) ?? 0;
        if (rating < minRating) return false;
      }

      if (selectedServiceType != null &&
          selectedServiceType!.isNotEmpty &&
          serviceType != selectedServiceType) {
        return false;
      }

      if (selectedWorkingMode != null &&
          selectedWorkingMode!.isNotEmpty &&
          workingMode != selectedWorkingMode) {
        return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF5A3E9E);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.white,
        foregroundColor: primary,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _RatingFilter(
                        selectedRating: selectedMinRating == null
                            ? null
                            : double.tryParse(selectedMinRating!),
                        onSelected: (value) {
                          setState(() {
                            selectedMinRating = value.toString();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FilterDropdown(
                        hint: 'Service Type',
                        value: selectedServiceType,
                        items: const ['one-time', 'long-term', 'both'],
                        onChanged: (value) {
                          setState(() {
                            selectedServiceType = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _FilterDropdown(
                        hint: 'Working Mode',
                        value: selectedWorkingMode,
                        items: const ['online', 'in-person', 'both'],
                        onChanged: (value) {
                          setState(() {
                            selectedWorkingMode = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              selectedMinRating = null;
                              selectedServiceType = null;
                              selectedWorkingMode = null;
                            });
                          },
                          child: const Text('Clear filters'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('accountType', isEqualTo: 'freelancer')
                  .where('serviceField', isEqualTo: widget.serviceField)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading freelancers: ${snapshot.error}'),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                final filteredDocs = _applyFilters(docs);

                if (filteredDocs.isEmpty) {
                  return const Center(
                    child: Text('No freelancers match these filters'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredDocs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = filteredDocs[index].data();

                    final firstName = (data['firstName'] ?? '').toString();
                    final lastName = (data['lastName'] ?? '').toString();
                    final fullName = '$firstName $lastName'.trim().isEmpty
                        ? 'No Name'
                        : '$firstName $lastName'.trim();
                    final serviceField = (data['serviceField'] ?? '')
                        .toString();
                    final rating = _parseRating(data['rating']);
                    final photoUrl = (data['photoUrl'] ?? data['profile'] ?? '')
                        .toString();

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F2FB),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: FreelancerCardSimple(
                          name: fullName,
                          role: serviceField,
                          rating: rating,
                          photoUrl: photoUrl,
                          imageRadius: 20,
                          nameFontSize: 13,
                          roleFontSize: 12,
                          starSize: 14,
                          linkFontSize: 10.5,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FreelancerProfileView(
                                  userId: filteredDocs[index].id,
                                  fromCategory: true,
                                ),
                              ),
                            );
                          },
                          requestAction: SendRequestButton(
                            freelancerId: filteredDocs[index].id,
                            freelancerName: fullName,
                            iconOnly: true,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String hint;
  final String? value;
  final List<String> items;
  final void Function(String?) onChanged;

  const _FilterDropdown({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF5A3E9E);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F2FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary.withOpacity(0.15)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint),
          isExpanded: true,
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _RatingFilter extends StatelessWidget {
  final double? selectedRating;
  final Function(double) onSelected;

  const _RatingFilter({required this.selectedRating, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF5A3E9E);

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F2FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary.withOpacity(0.15)),
      ),
      child: Row(
        children: List.generate(5, (index) {
          final starValue = index + 1;

          return GestureDetector(
            onTap: () => onSelected(starValue.toDouble()),
            child: Icon(
              Icons.star,
              size: 20,
              color: (selectedRating != null && starValue <= selectedRating!)
                  ? Colors.amber
                  : Colors.grey.shade400,
            ),
          );
        }),
      ),
    );
  }
}

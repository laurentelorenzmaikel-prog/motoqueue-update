import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lorenz_app/admin/users_management_page.dart';
import 'package:lorenz_app/admin/admin_feedback_page.dart';
import 'package:lorenz_app/admin/predictions_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lorenz_app/admin/spare_parts.dart';
import 'package:fl_chart/fl_chart.dart';

class ModernAdminDashboard extends StatefulWidget {
  const ModernAdminDashboard({super.key});

  @override
  State<ModernAdminDashboard> createState() => _ModernAdminDashboardState();
}

class _ModernAdminDashboardState extends State<ModernAdminDashboard> {
  int _selectedIndex = 0;

  int todayCount = 0;
  int monthCount = 0;
  int yearCount = 0;
  int totalUsers = 0;
  int activeUsers = 0;
  int totalFeedback = 0;
  bool isLoading = true;
  String? errorMessage;

  final Map<String, Map<String, String>> _userCache = {};
  final GlobalKey<State> _usersPageKey = GlobalKey<State>();
  final GlobalKey<State> _predictionsPageKey = GlobalKey<State>();
  final GlobalKey<State> _feedbackPageKey = GlobalKey<State>();
  final GlobalKey<State> _sparePartsPageKey = GlobalKey<State>();
  final GlobalKey<State> _analyticsPageKey = GlobalKey<State>();
  final GlobalKey<State> _securityPageKey = GlobalKey<State>();

  // Pagination state for completed/rejected appointments
  int _completedRejectedCurrentPage = 0;
  final int _completedRejectedItemsPerPage = 10;

  // Analytics data for dashboard charts
  Map<String, int> serviceTypeData = {};
  Map<int, int> monthlyCounts = {};
  int totalAppointments = 0;
  int completedAppointments = 0;
  int pendingAppointments = 0;
  int rejectedAppointments = 0;

  final List<String> _canonicalServices = [
    'General Maintenance & Repairs',
    'Engine & Electrical Work',
    'Performance & Customization',
    'Custom Work & Accessories Installation',
  ];

  final Map<String, String> _serviceAliases = {
    'General Maintenance & Repairs': 'General Maintenance & Repairs',
    'General Maintenance &\nRepairs': 'General Maintenance & Repairs',
    'Engine & Electrical Work': 'Engine & Electrical Work',
    'Engine & Electrical\nWork': 'Engine & Electrical Work',
    'Performance & Customization': 'Performance & Customization',
    'Performance &\nCustomization': 'Performance & Customization',
    'Custom Work & Accessories Installation':
        'Custom Work & Accessories Installation',
    'Custom Work &\nAccessories Installation':
        'Custom Work & Accessories Installation',
  };

  bool get isMobile => false;
  bool get isTablet => false;
  bool get isDesktop => true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final now = DateTime.now();

      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month + 1, 1);
      final yearStart = DateTime(now.year, 1, 1);
      final yearEnd = DateTime(now.year + 1, 1, 1);

      final results = await Future.wait([
        firestore.collection('appointments').get(),
        firestore.collection('users').get(),
        firestore.collection('feedback').get(),
      ]);

      final appointments = results[0];
      final users = results[1];
      final feedback = results[2];

      int todayCountVar = 0;
      int monthCountVar = 0;
      int yearCountVar = 0;

      // Analytics variables
      Map<String, int> tempServiceData = {};
      Map<int, int> tempMonthlyCounts = {};
      int completed = 0;
      int pending = 0;
      int rejected = 0;

      // Initialize monthly counts
      for (var i = 1; i <= 12; i++) {
        tempMonthlyCounts[i] = 0;
      }

      for (final doc in appointments.docs) {
        final data = doc.data();

        // Count service types (restricted to 4 canonical types)
        final rawService = (data['service'] as String?)?.trim() ?? '';
        final normalized = _serviceAliases[rawService] ?? '';
        if (normalized.isNotEmpty && _canonicalServices.contains(normalized)) {
          tempServiceData[normalized] = (tempServiceData[normalized] ?? 0) + 1;
        }

        // Count appointment status
        final status = data['status'] as String? ?? 'pending';
        if (status == 'completed') {
          completed++;
        } else if (status == 'rejected') {
          rejected++;
        } else {
          pending++;
        }

        if (data['dateTime'] != null) {
          final dateTime = data['dateTime'] is Timestamp
              ? (data['dateTime'] as Timestamp).toDate()
              : DateTime.tryParse(data['dateTime']?.toString() ?? '') ??
                  DateTime.now();

          // Count monthly appointments for current year
          if (dateTime.year == now.year) {
            tempMonthlyCounts[dateTime.month] =
                (tempMonthlyCounts[dateTime.month] ?? 0) + 1;
          }

          if (!dateTime.isBefore(todayStart) && dateTime.isBefore(todayEnd)) {
            todayCountVar++;
          }
          if (!dateTime.isBefore(monthStart) && dateTime.isBefore(monthEnd)) {
            monthCountVar++;
          }
          if (!dateTime.isBefore(yearStart) && dateTime.isBefore(yearEnd)) {
            yearCountVar++;
          }
        }
      }

      int activeUsersCount = 0;
      for (final doc in users.docs) {
        final data = doc.data();
        if (data['isActive'] == true) {
          activeUsersCount++;
        }
      }

      if (mounted) {
        setState(() {
          todayCount = todayCountVar;
          monthCount = monthCountVar;
          yearCount = yearCountVar;
          totalUsers = users.docs.length;
          activeUsers = activeUsersCount;
          totalFeedback = feedback.docs.length;
          // Analytics data
          serviceTypeData = tempServiceData;
          monthlyCounts = tempMonthlyCounts;
          totalAppointments = appointments.docs.length;
          completedAppointments = completed;
          pendingAppointments = pending;
          rejectedAppointments = rejected;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading dashboard data: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
          errorMessage = 'Failed to load data: ${e.toString()}';
        });
      }
    }
  }

  Future<Map<String, String>> _getUserInfo(String userId) async {
    if (_userCache.containsKey(userId)) {
      return _userCache[userId]!;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data();
        final Map<String, String> info = {
          'name': (userData?['displayName'] ?? userData?['name'] ?? 'Unknown')
              .toString(),
          'email': (userData?['email'] ?? userId).toString(),
        };
        _userCache[userId] = info;
        return info;
      }
    } catch (e) {
      print('Error fetching user info: $e');
    }

    final defaultInfo = {'name': 'Unknown', 'email': userId};
    _userCache[userId] = defaultInfo;
    return defaultInfo;
  }

  Stream<QuerySnapshot> get _appointmentsStream {
    return FirebaseFirestore.instance
        .collection('appointments')
        .orderBy('date', descending: true)
        .orderBy('timeSlot')
        .snapshots();
  }

  // Helper function to decrease stock using a WriteBatch
  Future<void> _updateSparePartStock(
      List<Map<String, dynamic>> partsUsed) async {
    if (partsUsed.isEmpty) return;

    final firestore = FirebaseFirestore.instance;
    WriteBatch batch = firestore.batch();

    for (final part in partsUsed) {
      final partId = part['id'] as String;
      final quantity = (part['quantity'] as num).toInt();

      if (quantity > 0) {
        final partRef = firestore.collection('spare_parts').doc(partId);
        // Use FieldValue.increment to safely decrement stock atomically
        batch.update(partRef, {
          'stock': FieldValue.increment(-quantity),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();
  }

  Future<void> _updateAppointmentStatus(String appointmentId, String newStatus,
      {List<Map<String, dynamic>>? partsUsed, String? rejectionReason}) async {
    try {
      Map<String, dynamic> updateData = {
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (partsUsed != null) {
        updateData['spareParts'] = partsUsed;
      } else if (newStatus == 'rejected') {
        // Clear spare parts for rejected appointments
        updateData['spareParts'] = [];
        // Add rejection reason if provided
        if (rejectionReason != null && rejectionReason.isNotEmpty) {
          updateData['rejectionReason'] = rejectionReason;
        }
      }

      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(appointmentId)
          .update(updateData);

      // If marking as completed with parts used, update stock
      if (newStatus == 'completed' && partsUsed != null) {
        await _updateSparePartStock(partsUsed);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Appointment $newStatus successfully'),
            backgroundColor: newStatus == 'rejected'
                ? const Color(0xFFEF4444)
                : const Color(0xFF10B981),
          ),
        );
        // Reset pagination when status is updated
        setState(() {
          _completedRejectedCurrentPage = 0;
        });
      }
    } catch (e) {
      print('Error updating appointment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update appointment'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Row(
        children: [
          // Sidebar
          _buildSidebar(),
          // Main content
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildMainContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Logo/Header
          Container(
            padding: const EdgeInsets.all(32),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF225FFF), Color(0xFF6366F1)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.dashboard,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Panel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    Text(
                      'Management',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 16),
          // Navigation Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildNavItem(0, Icons.dashboard, 'Dashboard'),
                _buildNavItem(1, Icons.people, 'Users'),
                _buildNavItem(2, Icons.auto_graph, 'Predictions'),
                _buildNavItem(3, Icons.feedback, 'Feedback'),
                _buildNavItem(4, Icons.calendar_month, 'Appointments'),
                _buildNavItem(5, Icons.build, 'Spare Parts'),
              ],
            ),
          ),
          // Logout
          Container(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () async {
                final box = await Hive.openBox('userBox');
                await box.clear();
                if (mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedIndex = index);
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF225FFF).withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: isSelected
                      ? const Color(0xFF225FFF)
                      : const Color(0xFF6B7280),
                  size: 24,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? const Color(0xFF225FFF)
                          : const Color(0xFF4B5563),
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

  Widget _buildTopBar() {
    return Container(
      height: isMobile ? 64 : 80,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _getPageTitle(),
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 24,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A1A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isMobile) ...[
                  const SizedBox(height: 4),
                  Text(
                    _getPageSubtitle(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.refresh,
                    color: const Color(0xFF6B7280), size: isMobile ? 20 : 24),
                onPressed: _refreshCurrentPage,
                tooltip: 'Refresh',
              ),
              if (!isMobile) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF225FFF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.admin_panel_settings,
                          size: 20, color: Color(0xFF225FFF)),
                      SizedBox(width: 8),
                      Text(
                        'Admin',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF225FFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _refreshCurrentPage() {
    switch (_selectedIndex) {
      case 0:
      case 4:
        _loadDashboardData();
        break;
      case 1:
        (_usersPageKey.currentState as dynamic)?.refresh();
        break;
      case 2:
        (_predictionsPageKey.currentState as dynamic)?.refresh();
        break;
      case 3:
        (_feedbackPageKey.currentState as dynamic)?.refresh();
        break;
      case 5:
        (_sparePartsPageKey.currentState as dynamic)?.refresh();
        break;
    }
  }

  String _getPageTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Dashboard Overview';
      case 1:
        return 'Users Management';
      case 2:
        return 'Service Predictions';
      case 3:
        return 'User Feedback';
      case 4:
        return 'Appointments';
      case 5:
        return 'Spare Parts';
      default:
        return 'Dashboard';
    }
  }

  String _getPageSubtitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Monitor key metrics and system performance';
      case 1:
        return 'Manage user accounts and permissions';
      case 2:
        return 'AI-powered service demand forecasting';
      case 3:
        return 'Review and respond to user feedback';
      case 4:
        return 'Manage and track appointments';
      case 5:
        return 'Manage motorcycle parts inventory';
      default:
        return '';
    }
  }

  Widget _buildMainContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardOverview();
      case 1:
        return UsersManagementPage(key: _usersPageKey);
      case 2:
        return PredictionsPage(key: _predictionsPageKey);
      case 3:
        return AdminFeedbackPage(key: _feedbackPageKey);
      case 4:
        return _buildAppointmentsOverview();
      case 5:
        return SparePartsPage(key: _sparePartsPageKey);
      default:
        return _buildDashboardOverview();
    }
  }

  Widget _buildDashboardOverview() {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading dashboard data...',
                style: TextStyle(color: Color(0xFF6B7280))),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Color(0xFFDC2626)),
            const SizedBox(height: 16),
            Text(
              'Error Loading Dashboard',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                errorMessage!,
                style: const TextStyle(color: Color(0xFF6B7280)),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadDashboardData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF225FFF),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 16 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats Cards Grid
            LayoutBuilder(
              builder: (context, constraints) {
                int columns = isMobile ? 1 : (isTablet ? 2 : 4);
                double cardWidth = isMobile
                    ? constraints.maxWidth
                    : ((constraints.maxWidth - (20 * (columns - 1))) / columns);

                return Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _buildStatCard(
                        'Total Users',
                        totalUsers.toString(),
                        Icons.people,
                        const Color(0xFF225FFF),
                        '+12% from last month',
                        false,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _buildStatCard(
                        'Active Users',
                        activeUsers.toString(),
                        Icons.check_circle,
                        const Color(0xFF10B981),
                        '${activeUsers > 0 && totalUsers > 0 ? ((activeUsers / totalUsers) * 100).toStringAsFixed(0) : 0}% active rate',
                        false,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _buildStatCard(
                        'Total Feedback',
                        totalFeedback.toString(),
                        Icons.feedback,
                        const Color(0xFFF59E0B),
                        'Recent submissions',
                        false,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _buildStatCard(
                        'Today\'s Appointments',
                        todayCount.toString(),
                        Icons.event,
                        const Color(0xFF8B5CF6),
                        'Scheduled today',
                        false,
                      ),
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: isMobile ? 24 : 32),

            // Appointments Overview Section
            Text(
              'Appointments Overview',
              style: TextStyle(
                fontSize: isMobile ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 16),

            LayoutBuilder(
              builder: (context, constraints) {
                int columns = isMobile ? 1 : (isTablet ? 2 : 3);
                double cardWidth = isMobile
                    ? constraints.maxWidth
                    : ((constraints.maxWidth - (20 * (columns - 1))) / columns);

                return Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _buildAppointmentCard(
                        'Daily',
                        todayCount.toString(),
                        Icons.today,
                        const Color(0xFF3B82F6),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _buildAppointmentCard(
                        'Monthly',
                        monthCount.toString(),
                        Icons.calendar_month,
                        const Color(0xFFEC4899),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _buildAppointmentCard(
                        'Yearly',
                        yearCount.toString(),
                        Icons.calendar_today,
                        const Color(0xFF06B6D4),
                      ),
                    ),
                  ],
                );
              },
            ),

            // Analytics Charts Section
            const SizedBox(height: 32),

            // Monthly Appointments Bar Chart
            _buildMonthlyAppointmentsChart(),

            const SizedBox(height: 24),

            // Two Pie Charts in a Row
            LayoutBuilder(
              builder: (context, constraints) {
                double chartWidth = isMobile
                    ? constraints.maxWidth
                    : ((constraints.maxWidth - 20) / 2);

                return Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    SizedBox(
                      width: chartWidth,
                      child: _buildServiceTypeChart(),
                    ),
                    SizedBox(
                      width: chartWidth,
                      child: _buildAppointmentStatusChart(),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    String subtitle,
    bool showTrend,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              if (showTrend)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.trending_up,
                        size: 14,
                        color: Color(0xFF10B981),
                      ),
                      SizedBox(width: 4),
                      Text(
                        '+12%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentCard(
      String period, String count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 32),
          const SizedBox(height: 16),
          Text(
            period,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            count,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Appointments',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  // Monthly Appointments Bar Chart
  Widget _buildMonthlyAppointmentsChart() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bar_chart,
                    color: Color(0xFF3B82F6), size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Appointments per Month (This Year)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 250,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final months = [
                        'Jan',
                        'Feb',
                        'Mar',
                        'Apr',
                        'May',
                        'Jun',
                        'Jul',
                        'Aug',
                        'Sep',
                        'Oct',
                        'Nov',
                        'Dec'
                      ];
                      return BarTooltipItem(
                        '${months[group.x.toInt()]}\n${rod.toY.toInt()} appointments',
                        const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final months = [
                          'Jan',
                          'Feb',
                          'Mar',
                          'Apr',
                          'May',
                          'Jun',
                          'Jul',
                          'Aug',
                          'Sep',
                          'Oct',
                          'Nov',
                          'Dec'
                        ];
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            months[value.toInt()],
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF6B7280)),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF6B7280)),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: _buildBarData(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: const Color(0xFFE5E7EB),
                      strokeWidth: 1,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<BarChartGroupData> _buildBarData() {
    return List.generate(12, (i) {
      final month = i + 1;
      final count = monthlyCounts[month] ?? 0;
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: count.toDouble(),
            gradient: const LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            width: 20,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(6),
            ),
          ),
        ],
      );
    });
  }

  // Service Types Distribution Pie Chart
  Widget _buildServiceTypeChart() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.pie_chart,
                    color: Color(0xFF10B981), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Service Types Distribution',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pie Chart
              SizedBox(
                height: 180,
                width: 180,
                child: serviceTypeData.isEmpty
                    ? const Center(
                        child: Text('No data available',
                            style: TextStyle(color: Color(0xFF6B7280))))
                    : PieChart(
                        PieChartData(
                          sections: _buildServicePieChartSections(),
                          centerSpaceRadius: 40,
                          sectionsSpace: 2,
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              // Legend - Vertical
              Expanded(
                child: _buildServiceTypeLegend(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildServicePieChartSections() {
    final colors = [
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
    ];

    final validServices =
        _canonicalServices.where((s) => (serviceTypeData[s] ?? 0) > 0).toList();

    return validServices.asMap().entries.map((entry) {
      final index = entry.key;
      final serviceName = entry.value;
      final count = serviceTypeData[serviceName] ?? 0;
      final percentage =
          totalAppointments > 0 ? (count / totalAppointments * 100) : 0.0;

      return PieChartSectionData(
        value: count.toDouble(),
        title: '${percentage.toStringAsFixed(0)}%',
        color: colors[index % colors.length],
        radius: 50,
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  Widget _buildServiceTypeLegend() {
    final colors = [
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
    ];

    final validServices =
        _canonicalServices.where((s) => (serviceTypeData[s] ?? 0) > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: validServices.asMap().entries.map((entry) {
        final index = entry.key;
        final serviceName = entry.value;
        final count = serviceTypeData[serviceName] ?? 0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colors[index % colors.length],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$serviceName ($count)',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // Appointment Status Pie Chart
  Widget _buildAppointmentStatusChart() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.donut_small,
                    color: Color(0xFF8B5CF6), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Appointment Status',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pie Chart
              SizedBox(
                height: 180,
                width: 180,
                child: totalAppointments == 0
                    ? const Center(
                        child: Text('No data available',
                            style: TextStyle(color: Color(0xFF6B7280))))
                    : PieChart(
                        PieChartData(
                          sections: [
                            PieChartSectionData(
                              value: completedAppointments.toDouble(),
                              title: totalAppointments > 0
                                  ? '${(completedAppointments / totalAppointments * 100).toStringAsFixed(0)}%'
                                  : '0%',
                              color: const Color(0xFF10B981),
                              radius: 50,
                              titleStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            PieChartSectionData(
                              value: pendingAppointments.toDouble(),
                              title: totalAppointments > 0
                                  ? '${(pendingAppointments / totalAppointments * 100).toStringAsFixed(0)}%'
                                  : '0%',
                              color: const Color(0xFFF59E0B),
                              radius: 50,
                              titleStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            PieChartSectionData(
                              value: rejectedAppointments.toDouble(),
                              title: totalAppointments > 0
                                  ? '${(rejectedAppointments / totalAppointments * 100).toStringAsFixed(0)}%'
                                  : '0%',
                              color: const Color(0xFFEF4444),
                              radius: 50,
                              titleStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                          centerSpaceRadius: 40,
                          sectionsSpace: 2,
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              // Legend - Vertical
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatusLegendItem('Completed', const Color(0xFF10B981),
                        completedAppointments),
                    const SizedBox(height: 8),
                    _buildStatusLegendItem('Pending', const Color(0xFFF59E0B),
                        pendingAppointments),
                    const SizedBox(height: 8),
                    _buildStatusLegendItem('Rejected', const Color(0xFFEF4444),
                        rejectedAppointments),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusLegendItem(String label, Color color, int count) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label ($count)',
            style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
          ),
        ),
      ],
    );
  }

  Widget _buildAppointmentsOverview() {
    return StreamBuilder<QuerySnapshot>(
      stream: _appointmentsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Loading appointments...',
                  style: TextStyle(color: Color(0xFF6B7280)),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    size: 64, color: Color(0xFFDC2626)),
                const SizedBox(height: 16),
                const Text(
                  'Unable to load appointments',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? 16 : 32),
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.calendar_month,
                        size: 64, color: Color(0xFF9CA3AF)),
                    SizedBox(height: 16),
                    Text(
                      'No bookings available yet',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final docs = snapshot.data!.docs;
        final pendingAppointments = <QueryDocumentSnapshot>[];
        final inProcessAppointments = <QueryDocumentSnapshot>[];
        final completedRejectedAppointments = <QueryDocumentSnapshot>[];

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status']?.toString().toLowerCase() ?? 'pending';

          if (status == 'pending') {
            pendingAppointments.add(doc);
          } else if (status == 'in_process') {
            inProcessAppointments.add(doc);
          } else if (status == 'completed' || status == 'rejected') {
            completedRejectedAppointments.add(doc);
          }
        }

        // Sort completed/rejected appointments by updatedAt (most recent first)
        completedRejectedAppointments.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aUpdated = aData['updatedAt'] as Timestamp?;
          final bUpdated = bData['updatedAt'] as Timestamp?;

          if (aUpdated == null && bUpdated == null) return 0;
          if (aUpdated == null) return 1;
          if (bUpdated == null) return -1;

          return bUpdated.compareTo(aUpdated); // Descending order
        });

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Modern Status Indicator Cards at the top
              _buildStatusIndicatorCards(
                pendingAppointments.length,
                inProcessAppointments.length,
                completedRejectedAppointments.length,
              ),
              const SizedBox(height: 32),

              // Pending Appointments
              const Text(
                'Pending Appointments',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 16),
              _buildPendingAppointmentsTable(pendingAppointments),
              const SizedBox(height: 32),

              // In Process Appointments
              const Text(
                'In Process Appointments',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 16),
              _buildInProcessAppointmentsTable(inProcessAppointments),
              const SizedBox(height: 32),

              // Completed/Rejected
              const Text(
                'Completed & Rejected Appointments',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 16),
              _buildCompletedRejectedTable(completedRejectedAppointments),
            ],
          ),
        );
      },
    );
  }

  // New Modern Status Indicator Cards
  Widget _buildStatusIndicatorCards(int pending, int processing, int finished) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int columns = isMobile ? 1 : 3;
        double cardWidth = isMobile
            ? constraints.maxWidth
            : ((constraints.maxWidth - (20 * (columns - 1))) / columns);

        return Wrap(
          spacing: 20,
          runSpacing: 20,
          children: [
            SizedBox(
              width: cardWidth,
              child: _buildStatusCard(
                'Pending',
                pending.toString(),
                Icons.pending_actions,
                const Color(0xFFF59E0B),
                'Awaiting confirmation',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildStatusCard(
                'Processing',
                processing.toString(),
                Icons.settings,
                const Color(0xFF3B82F6),
                'Currently in progress',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildStatusCard(
                'Finished',
                finished.toString(),
                Icons.check_circle,
                const Color(0xFF10B981),
                'Completed & Rejected',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusCard(
    String title,
    String count,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 48),
          ),
          const SizedBox(height: 20),
          Text(
            count,
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPendingAppointmentsTable(
      List<QueryDocumentSnapshot> appointments) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: appointments.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.calendar_month,
                        size: 64, color: Color(0xFF9CA3AF)),
                    SizedBox(height: 16),
                    Text(
                      'No pending appointments',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFFF3F4F6)),
                  columns: const [
                    DataColumn(
                        label: Text('Date',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Time',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Customer',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Service',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Actions',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: appointments.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final docId = doc.id;
                    final dateString = data['date']?.toString() ?? 'No date';
                    final timeSlotString =
                        data['timeSlot']?.toString() ?? 'No time';
                    final service =
                        data['service'] ?? data['serviceType'] ?? 'Unknown';
                    final userId = data['userId']?.toString() ?? '';

                    return DataRow(
                      cells: [
                        DataCell(Text(dateString)),
                        DataCell(Text(timeSlotString)),
                        DataCell(_buildUserInfoCell(userId, data)),
                        DataCell(
                          SizedBox(
                            width: 200,
                            child:
                                Text(service, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: 'View Details',
                                child: IconButton(
                                  icon: const Icon(Icons.visibility,
                                      size: 20, color: Color(0xFF3B82F6)),
                                  onPressed: () {
                                    _showAppointmentDetails({
                                      ...data,
                                      'id': docId,
                                    });
                                  },
                                  splashRadius: 20,
                                ),
                              ),
                              Tooltip(
                                message: 'Accept',
                                child: IconButton(
                                  icon: const Icon(Icons.check_circle,
                                      size: 20, color: Color(0xFF10B981)),
                                  onPressed: () {
                                    _updateAppointmentStatus(
                                        docId, 'in_process');
                                  },
                                  splashRadius: 20,
                                ),
                              ),
                              Tooltip(
                                message: 'Reject',
                                child: IconButton(
                                  icon: const Icon(Icons.cancel,
                                      size: 20, color: Color(0xFFEF4444)),
                                  onPressed: () {
                                    final rejectionReasonController =
                                        TextEditingController();
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        title: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEF4444)
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                Icons.cancel_outlined,
                                                color: Color(0xFFEF4444),
                                                size: 24,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Text('Reject Appointment'),
                                          ],
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Are you sure you want to reject this appointment?',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Color(0xFF6B7280),
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            const Text(
                                              'Rejection Reason (Optional)',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF374151),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            TextField(
                                              controller:
                                                  rejectionReasonController,
                                              maxLines: 3,
                                              decoration: InputDecoration(
                                                hintText:
                                                    'Enter reason for rejection...',
                                                hintStyle: TextStyle(
                                                  color: Colors.grey.shade400,
                                                  fontSize: 14,
                                                ),
                                                filled: true,
                                                fillColor:
                                                    const Color(0xFFF9FAFB),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                    color: Colors.grey.shade300,
                                                  ),
                                                ),
                                                enabledBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                    color: Colors.grey.shade300,
                                                  ),
                                                ),
                                                focusedBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFFEF4444),
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              _updateAppointmentStatus(
                                                docId,
                                                'rejected',
                                                rejectionReason:
                                                    rejectionReasonController
                                                        .text
                                                        .trim(),
                                              );
                                            },
                                            icon: const Icon(Icons.cancel,
                                                size: 18),
                                            label: const Text('Reject'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFFEF4444),
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 12),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  splashRadius: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
    );
  }

  Widget _buildInProcessAppointmentsTable(
      List<QueryDocumentSnapshot> appointments) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: appointments.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.build_circle,
                        size: 64, color: Color(0xFF9CA3AF)),
                    SizedBox(height: 16),
                    Text(
                      'No appointments in process',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFFF3F4F6)),
                  columns: const [
                    DataColumn(
                        label: Text('Date',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Time',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Customer',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Service',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(
                        label: Text('Actions',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: appointments.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final docId = doc.id;
                    final dateString = data['date']?.toString() ?? 'No date';
                    final timeSlotString =
                        data['timeSlot']?.toString() ?? 'No time';
                    final service = data['service'] ?? 'N/A';
                    final userId = data['userId']?.toString() ?? '';

                    return DataRow(
                      cells: [
                        DataCell(Text(dateString)),
                        DataCell(Text(timeSlotString)),
                        DataCell(_buildUserInfoCell(userId, data)),
                        DataCell(
                          SizedBox(
                            width: 200,
                            child:
                                Text(service, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: 'Manage',
                                child: IconButton(
                                  icon: const Icon(Icons.manage_accounts,
                                      size: 20, color: Color(0xFF3B82F6)),
                                  onPressed: () {
                                    _showInProcessDialog({
                                      ...data,
                                      'id': docId,
                                    });
                                  },
                                  splashRadius: 20,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Tooltip(
                                message: 'Move back to Pending',
                                child: IconButton(
                                  icon: const Icon(Icons.undo,
                                      size: 20, color: Color(0xFFF59E0B)),
                                  onPressed: () async {
                                    try {
                                      await FirebaseFirestore.instance
                                          .collection('appointments')
                                          .doc(docId)
                                          .update({
                                        'status': 'pending',
                                        'updatedAt':
                                            FieldValue.serverTimestamp(),
                                      });
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Appointment moved back to pending'),
                                            backgroundColor: Color(0xFFF59E0B),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content:
                                                Text('Error: ${e.toString()}'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  splashRadius: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
    );
  }

  Widget _buildCompletedRejectedTable(
      List<QueryDocumentSnapshot> appointments) {
    // No search filter applied anymore
    List<QueryDocumentSnapshot> filteredAppointments = appointments;

    // Calculate pagination
    final totalItems = filteredAppointments.length;
    final totalPages = totalItems > 0
        ? (totalItems / _completedRejectedItemsPerPage).ceil()
        : 1;

    // Ensure current page is within valid range
    if (_completedRejectedCurrentPage >= totalPages && totalPages > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _completedRejectedCurrentPage = totalPages - 1;
          });
        }
      });
    }
    if (_completedRejectedCurrentPage < 0) {
      _completedRejectedCurrentPage = 0;
    }

    final startIndex =
        _completedRejectedCurrentPage * _completedRejectedItemsPerPage;
    final endIndex = (startIndex + _completedRejectedItemsPerPage > totalItems)
        ? totalItems
        : startIndex + _completedRejectedItemsPerPage;

    final paginatedAppointments = totalItems > 0
        ? filteredAppointments.sublist(startIndex, endIndex)
        : <QueryDocumentSnapshot>[];

    // Build data rows
    final dataRows = paginatedAppointments.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final dateString = data['date']?.toString() ?? 'No date';
      final timeSlotString = data['timeSlot']?.toString() ?? 'No time';
      final status = data['status']?.toString().toLowerCase() ?? 'completed';
      final service = data['service'] ?? 'N/A';
      final userId = data['userId']?.toString() ?? '';

      return DataRow(
        cells: [
          DataCell(Text(dateString)),
          DataCell(Text(timeSlotString)),
          DataCell(_buildUserInfoCell(userId, data)),
          DataCell(Text(service, overflow: TextOverflow.ellipsis)),
          DataCell(_buildSparePartsCell(data, status)),
          DataCell(_buildStatusBadge(status)),
          DataCell(_buildActionsCell(data, status)),
        ],
      );
    }).toList();

    // Add empty rows to maintain fixed table size
    final emptyRowsCount = _completedRejectedItemsPerPage - dataRows.length;
    final emptyRows = List.generate(
      emptyRowsCount,
      (index) => DataRow(cells: [
        const DataCell(Text('')),
        const DataCell(Text('')),
        const DataCell(Text('')),
        const DataCell(Text('')),
        const DataCell(Text('')),
        const DataCell(Text('')),
        const DataCell(Text('')),
      ]),
    );

    final allRows = [...dataRows, ...emptyRows];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: double.infinity,
              child: DataTable(
                headingRowColor:
                    WidgetStateProperty.all(const Color(0xFFF3F4F6)),
                columnSpacing: 24,
                columns: const [
                  DataColumn(
                      label: Text('Date',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('Time',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('Customer',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('Service',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('Spare Parts',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('Status',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('Actions',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: allRows,
              ),
            ),
            // Pagination Controls
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Showing ${totalItems == 0 ? 0 : startIndex + 1} - ${endIndex.clamp(0, totalItems)} of $totalItems entries',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Row(
                    children: [
                      // First page button
                      IconButton(
                        onPressed: _completedRejectedCurrentPage > 0
                            ? () => setState(
                                () => _completedRejectedCurrentPage = 0)
                            : null,
                        icon: const Icon(Icons.first_page_rounded),
                        tooltip: 'First page',
                        iconSize: 20,
                        splashRadius: 20,
                        color: const Color(0xFF225FFF),
                        disabledColor: Colors.grey.shade400,
                      ),
                      // Previous page button
                      IconButton(
                        onPressed: _completedRejectedCurrentPage > 0
                            ? () =>
                                setState(() => _completedRejectedCurrentPage--)
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                        tooltip: 'Previous page',
                        iconSize: 20,
                        splashRadius: 20,
                        color: const Color(0xFF225FFF),
                        disabledColor: Colors.grey.shade400,
                      ),
                      // Page indicator
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          'Page ${totalPages == 0 ? 0 : _completedRejectedCurrentPage + 1} of $totalPages',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // Next page button
                      IconButton(
                        onPressed: _completedRejectedCurrentPage <
                                totalPages - 1
                            ? () =>
                                setState(() => _completedRejectedCurrentPage++)
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                        tooltip: 'Next page',
                        iconSize: 20,
                        splashRadius: 20,
                        color: const Color(0xFF225FFF),
                        disabledColor: Colors.grey.shade400,
                      ),
                      // Last page button
                      IconButton(
                        onPressed: _completedRejectedCurrentPage <
                                totalPages - 1
                            ? () => setState(() =>
                                _completedRejectedCurrentPage = totalPages - 1)
                            : null,
                        icon: const Icon(Icons.last_page_rounded),
                        tooltip: 'Last page',
                        iconSize: 20,
                        splashRadius: 20,
                        color: const Color(0xFF225FFF),
                        disabledColor: Colors.grey.shade400,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfoCell(String userId, Map<String, dynamic> data) {
    if (_userCache.containsKey(userId)) {
      final userInfo = _userCache[userId]!;
      return SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              userInfo['name'] ?? 'Unknown',
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              userInfo['email'] ?? userId,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    if (userId.isNotEmpty) {
      return FutureBuilder<Map<String, String>>(
        future: _getUserInfo(userId),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return SizedBox(
              width: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    snapshot.data!['name'] ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    snapshot.data!['email'] ?? userId,
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }
          return SizedBox(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 14,
                  width: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 12,
                  width: 150,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            data['customerName']?.toString() ?? 'Unknown',
            style: const TextStyle(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            data['customerEmail']?.toString() ?? 'No email',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    String displayText;

    switch (status.toLowerCase()) {
      case 'completed':
        bgColor = const Color(0xFF3B82F6).withOpacity(0.1);
        textColor = const Color(0xFF3B82F6);
        displayText = 'Completed';
        break;
      case 'rejected':
        bgColor = const Color(0xFFEF4444).withOpacity(0.1);
        textColor = const Color(0xFFEF4444);
        displayText = 'Rejected';
        break;
      default:
        bgColor = const Color(0xFFF59E0B).withOpacity(0.1);
        textColor = const Color(0xFFF59E0B);
        displayText = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildSparePartsCell(Map<String, dynamic> data, String status) {
    // If rejected, show "None"
    if (status.toLowerCase() == 'rejected') {
      return const SizedBox(
        width: 200,
        child: Text(
          'None',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7280),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    // For completed appointments, show spare parts
    final spareParts = data['spareParts'];

    if (spareParts == null || spareParts is! List || spareParts.isEmpty) {
      return const SizedBox(
        width: 200,
        child: Text(
          'No parts used',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7280),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    // Build list of parts
    final parts = spareParts.whereType<Map<String, dynamic>>().toList();
    if (parts.isEmpty) {
      return const SizedBox(
        width: 200,
        child: Text(
          'No parts used',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7280),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    // Show only first part, then "+X more" if there are more
    final firstPart = parts.first;
    final partName = firstPart['name']?.toString() ?? 'Unknown';
    final quantity = firstPart['quantity']?.toString() ?? '0';
    final remainingCount = parts.length - 1;

    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '• $partName (x$quantity)',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF1A1A1A),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (remainingCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '+ $remainingCount more',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionsCell(Map<String, dynamic> data, String status) {
    final spareParts = data['spareParts'];
    final hasParts = spareParts != null &&
        spareParts is List &&
        spareParts.isNotEmpty &&
        status.toLowerCase() == 'completed';

    if (!hasParts) {
      return const SizedBox.shrink();
    }

    return Tooltip(
      message: 'View Spare Parts Details',
      child: IconButton(
        icon: const Icon(Icons.visibility, size: 20, color: Color(0xFF3B82F6)),
        onPressed: () {
          _showSparePartsDetailsDialog(data);
        },
        splashRadius: 20,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }

  void _showSparePartsDetailsDialog(Map<String, dynamic> appointment) {
    final spareParts = appointment['spareParts'];
    final dateString = appointment['date']?.toString() ?? 'No date';
    final timeSlotString = appointment['timeSlot']?.toString() ?? 'No time';
    final service = appointment['service']?.toString() ?? 'Unknown Service';

    if (spareParts == null || spareParts is! List || spareParts.isEmpty) {
      return;
    }

    final parts = spareParts.whereType<Map<String, dynamic>>().toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.build_circle,
                color: Color(0xFF3B82F6),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Spare Parts Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Appointment Info
                _buildDetailRow('Service', service),
                _buildDetailRow('Date & Time', '$dateString • $timeSlotString'),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),

                // Spare Parts List
                const Text(
                  'Spare Parts Used:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 12),
                ...parts.map((part) {
                  final partName = part['name']?.toString() ?? 'Unknown';
                  final quantity = part['quantity']?.toString() ?? '0';
                  final price = (part['price'] as num?)?.toDouble() ?? 0.0;
                  final totalPrice = price * (int.tryParse(quantity) ?? 0);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.inventory_2,
                            color: Color(0xFF3B82F6),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                partName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    'Quantity: $quantity',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    'Price: ₱${price.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₱${totalPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF3B82F6),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),

                // Total
                if (parts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      Text(
                        '₱${parts.fold<double>(0.0, (sum, part) {
                          final price =
                              (part['price'] as num?)?.toDouble() ?? 0.0;
                          final quantity = int.tryParse(
                                  part['quantity']?.toString() ?? '0') ??
                              0;
                          return sum + (price * quantity);
                        }).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showInProcessDialog(Map<String, dynamic> appointment) async {
    final dateString = appointment['date']?.toString() ?? 'No date';
    final timeSlotString = appointment['timeSlot']?.toString() ?? 'No time';
    final service = appointment['service']?.toString() ??
        appointment['serviceType']?.toString() ??
        'Unknown Service';
    final docId = appointment['id'];
    final userId = appointment['userId']?.toString() ?? '';

    // Fetch customer info if userId exists, otherwise use defaults
    Map<String, dynamic> customerInfo;
    if (userId.isNotEmpty) {
      final userInfo = await _getUserInfo(userId);
      customerInfo = {
        'name': userInfo['name'] ?? 'Unknown Customer',
        'email': userInfo['email'] ?? 'N/A',
      };
    } else {
      customerInfo = {
        'name': 'Unknown Customer',
        'email': 'N/A',
      };
    }

    // Initialize selectedParts from existing appointment data
    // Filter out any null values and ensure proper type
    List<Map<String, dynamic>> selectedParts = [];
    if (appointment['spareParts'] != null &&
        appointment['spareParts'] is List) {
      selectedParts = (appointment['spareParts'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => _InProcessDialogWidget(
        dateString: dateString,
        timeSlotString: timeSlotString,
        service: service,
        docId: docId,
        customerInfo: customerInfo,
        selectedParts: selectedParts,
        onComplete: (List<Map<String, dynamic>> parts) {
          _updateAppointmentStatus(docId, 'completed', partsUsed: parts);
        },
        buildDetailRow: _buildDetailRow,
      ),
    );
  }

  void _showAppointmentDetails(Map<String, dynamic> appointment) {
    final dateString = appointment['date']?.toString() ?? 'No date';
    final timeSlotString = appointment['timeSlot']?.toString() ?? 'No time';
    final service = appointment['service']?.toString() ??
        appointment['serviceType']?.toString() ??
        'Unknown Service';
    final reference = appointment['reference']?.toString() ?? 'N/A';
    final motorBrand = appointment['motorBrand']?.toString() ?? '';
    final plateNumber = appointment['plateNumber']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.calendar_today,
                color: Color(0xFF3B82F6),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Appointment Details'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Reference', reference),
              _buildDetailRow('Service', service),
              _buildDetailRow('Date & Time', '$dateString • $timeSlotString'),
              _buildDetailRow('Motor',
                  motorBrand.isNotEmpty ? motorBrand : 'Not specified'),
              if (plateNumber.isNotEmpty) _buildDetailRow('Plate', plateNumber),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF1A1A1A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// Separate widget for the In Process Dialog
class _InProcessDialogWidget extends StatefulWidget {
  final String dateString;
  final String timeSlotString;
  final String service;
  final String docId;
  final Map<String, dynamic> customerInfo;
  final List<Map<String, dynamic>> selectedParts;
  final Function(List<Map<String, dynamic>>) onComplete;
  final Widget Function(String, String) buildDetailRow;

  const _InProcessDialogWidget({
    required this.dateString,
    required this.timeSlotString,
    required this.service,
    required this.docId,
    required this.customerInfo,
    required this.selectedParts,
    required this.onComplete,
    required this.buildDetailRow,
  });

  @override
  State<_InProcessDialogWidget> createState() => _InProcessDialogWidgetState();
}

class _InProcessDialogWidgetState extends State<_InProcessDialogWidget> {
  late List<Map<String, dynamic>> selectedParts;

  @override
  void initState() {
    super.initState();
    selectedParts = List.from(widget.selectedParts);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.check_circle,
              color: Color(0xFF10B981),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text('Complete Appointment'),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 500,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Appointment Details
              widget.buildDetailRow('Customer', widget.customerInfo['name']),
              widget.buildDetailRow('Email', widget.customerInfo['email']),
              widget.buildDetailRow('Service', widget.service),
              widget.buildDetailRow('Date & Time',
                  '${widget.dateString} • ${widget.timeSlotString}'),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 20),

              // Spare Parts Section
              const Text(
                'Spare Parts Used',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 12),

              // Spare Parts Selector
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('spare_parts')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // CRITICAL: Include imageUrl when mapping spare parts
                  final parts = snapshot.data!.docs
                      .map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return {
                          'id': doc.id,
                          'name': data['name'] ?? 'Unknown',
                          'price': (data['price'] as num?)?.toDouble() ?? 0.0,
                          'stock': (data['stock'] as num?)?.toInt() ?? 0,
                          'imageUrl': data['imageUrl'],
                        };
                      })
                      .where((part) => part['stock'] as int > 0)
                      .toList();

                  if (parts.isEmpty) {
                    return const Text(
                      'No spare parts available',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                        fontStyle: FontStyle.italic,
                      ),
                    );
                  }

                  String? partDropdownValue =
                      parts.isNotEmpty ? parts.first['id'] : null;
                  Map<String, dynamic>? selectedPartDetails =
                      parts.isNotEmpty ? parts.first : null;
                  int quantityDropdownValue = 1;
                  int maxStock = selectedPartDetails != null
                      ? selectedPartDetails['stock'] as int
                      : 0;

                  return StatefulBuilder(
                    builder: (context, setDialogState) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Part Selector
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: const Color(0xFFE5E7EB)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: partDropdownValue,
                                isExpanded: true,
                                icon: const Icon(Icons.arrow_drop_down,
                                    color: Color(0xFF8B5CF6)),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF1A1A1A),
                                ),
                                items: parts.map((part) {
                                  final partName = part['name'];
                                  final partPrice = part['price'];
                                  final partStock = part['stock'];
                                  return DropdownMenuItem<String>(
                                    value: part['id'],
                                    child: Text(
                                      '$partName (₱${partPrice.toStringAsFixed(2)}) - Stock: $partStock',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  setDialogState(() {
                                    partDropdownValue = newValue;
                                    selectedPartDetails = parts
                                        .firstWhere((p) => p['id'] == newValue);
                                    maxStock =
                                        selectedPartDetails!['stock'] as int;
                                    quantityDropdownValue = 1;
                                  });
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Quantity Selector
                          const Text(
                            'Quantity',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: const Color(0xFFE5E7EB)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Decrement Button
                                IconButton(
                                  onPressed: quantityDropdownValue > 1
                                      ? () {
                                          setDialogState(() {
                                            quantityDropdownValue--;
                                          });
                                        }
                                      : null,
                                  icon: Icon(
                                    Icons.remove_circle_outline,
                                    color: quantityDropdownValue > 1
                                        ? const Color(0xFF8B5CF6)
                                        : Colors.grey.shade400,
                                    size: 28,
                                  ),
                                  tooltip: 'Decrease quantity',
                                ),
                                // Quantity Display
                                Column(
                                  children: [
                                    Text(
                                      '$quantityDropdownValue',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1A1A1A),
                                      ),
                                    ),
                                    Text(
                                      'of $maxStock available',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                // Increment Button
                                IconButton(
                                  onPressed: quantityDropdownValue < maxStock
                                      ? () {
                                          setDialogState(() {
                                            quantityDropdownValue++;
                                          });
                                        }
                                      : null,
                                  icon: Icon(
                                    Icons.add_circle_outline,
                                    color: quantityDropdownValue < maxStock
                                        ? const Color(0xFF8B5CF6)
                                        : Colors.grey.shade400,
                                    size: 28,
                                  ),
                                  tooltip: 'Increase quantity',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Quick quantity buttons
                          if (maxStock > 1)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (int qty in [1, 2, 3, 5, 10]
                                    .where((q) => q <= maxStock))
                                  InkWell(
                                    onTap: () {
                                      setDialogState(() {
                                        quantityDropdownValue = qty;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: quantityDropdownValue == qty
                                            ? const Color(0xFF8B5CF6)
                                            : const Color(0xFFF3F4F6),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: quantityDropdownValue == qty
                                              ? const Color(0xFF8B5CF6)
                                              : const Color(0xFFE5E7EB),
                                        ),
                                      ),
                                      child: Text(
                                        '$qty',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: quantityDropdownValue == qty
                                              ? Colors.white
                                              : const Color(0xFF4B5563),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),

                          const SizedBox(height: 20),

                          // Add Part Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: (partDropdownValue != null &&
                                      quantityDropdownValue > 0 &&
                                      selectedPartDetails != null &&
                                      selectedPartDetails!.isNotEmpty &&
                                      selectedPartDetails!
                                          .containsKey('name') &&
                                      selectedPartDetails!
                                          .containsKey('price') &&
                                      selectedPartDetails!
                                          .containsKey('stock') &&
                                      maxStock > 0)
                                  ? () {
                                      setState(() {
                                        final partId = partDropdownValue!;
                                        final partName =
                                            selectedPartDetails!['name'] ??
                                                'Unknown';
                                        final partPrice =
                                            (selectedPartDetails!['price']
                                                        as num?)
                                                    ?.toDouble() ??
                                                0.0;
                                        final quantity = quantityDropdownValue;
                                        // CRITICAL: Get imageUrl from selectedPartDetails
                                        final imageUrl =
                                            selectedPartDetails!['imageUrl'];

                                        // Remove existing entry if it exists
                                        selectedParts.removeWhere(
                                            (p) => p['id'] == partId);

                                        // CRITICAL: Add new entry with imageUrl included
                                        selectedParts.add({
                                          'id': partId,
                                          'name': partName,
                                          'price': partPrice,
                                          'quantity': quantity,
                                          'imageUrl': imageUrl,
                                        });
                                      });

                                      // Reset dropdown to first part
                                      setDialogState(() {
                                        if (parts.isNotEmpty) {
                                          partDropdownValue = parts.first['id'];
                                          selectedPartDetails = parts.first;
                                          maxStock =
                                              selectedPartDetails!['stock']
                                                  as int;
                                          quantityDropdownValue = 1;
                                        }
                                      });
                                    }
                                  : null,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add Part to List'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF8B5CF6),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
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
              const SizedBox(height: 20),

              // Display Selected Parts
              if (selectedParts.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Parts Used in Appointment:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...selectedParts.map((part) => Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${part['name']} x ${part['quantity']} (₱${(part['price'] * part['quantity']).toStringAsFixed(2)})',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: Colors.red, size: 20),
                                tooltip: 'Remove',
                                onPressed: () {
                                  setState(() {
                                    selectedParts.removeWhere(
                                        (p) => p['id'] == part['id']);
                                  });
                                },
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: 16),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Complete Appointment'),
          onPressed: () {
            Navigator.pop(context);
            widget.onComplete(selectedParts);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }
}

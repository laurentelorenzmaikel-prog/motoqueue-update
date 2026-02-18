  // KEEP YOUR IMPORTS
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:intl/intl.dart';
import 'package:lorenz_app/BookAppointmentsPage.dart';
import 'package:lorenz_app/MyAppointmentsPage.dart';
import 'package:lorenz_app/ProfilePage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:lorenz_app/RepairReco.dart';
import 'package:lorenz_app/SettingsPage.dart';
import 'package:lorenz_app/models/appointment.dart';
import 'package:lorenz_app/feedbackPage.dart';
import 'package:lorenz_app/BookPage.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Appointment? nextAppointment;
  DocumentSnapshot<Map<String, dynamic>>? _nextApptDoc;

  @override
  void initState() {
    super.initState();
    _loadNextAppointment();
  }

  Future<void> _loadNextAppointment() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final now = DateTime.now();
    final snap = await FirebaseFirestore.instance
        .collection('appointments')
        .where('userId', isEqualTo: uid)
        .where('dateTime', isGreaterThan: Timestamp.fromDate(now))
        .orderBy('dateTime')
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      _nextApptDoc = snap.docs.first;
    } else {
      _nextApptDoc = null;
    }
    setState(() {});
  }

  String _formatDateTime(DateTime dateTime) {
    final dayOfWeek = DateFormat('EEEE').format(dateTime);
    final formattedDate = DateFormat('MMM dd, yyyy').format(dateTime);
    final time = DateFormat('hh:mm a').format(dateTime);
    return '$time\n$formattedDate\n$dayOfWeek';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final username = user?.email ?? 'User';
    return Builder(
      builder: (context) {
        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFF),
          endDrawer: Drawer(
            backgroundColor: Colors.white,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.blue.shade600,
                        Colors.blue.shade800,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.two_wheeler,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Welcome back,',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _modernDrawerTile(
                  icon: Icons.person_outline,
                  title: 'Profile',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProfilePage()),
                    );
                  },
                ),
                _modernDrawerTile(
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                  },
                ),
                // _modernDrawerTile(
                //   icon: Icons.feedback_outlined,
                //   title: 'Feedback',
                //   onTap: () {
                //     Navigator.pop(context);
                //     Navigator.push(
                //       context,
                //       MaterialPageRoute(builder: (_) => const FeedbackPage()),
                //     );
                //   },
                // ),
                const Divider(height: 32),
                _modernDrawerTile(
                  icon: Icons.logout,
                  title: 'Log Out',
                  iconColor: Colors.red.shade400,
                  textColor: Colors.red.shade700,
                  onTap: () async {
                    Navigator.pop(context);
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    Navigator.pushNamedAndRemoveUntil(
                        context, '/login', (_) => false);
                  },
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          MediaQuery.of(context).size.width < 360 ? 12 : 16,
                      vertical:
                          MediaQuery.of(context).size.width < 360 ? 12 : 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.shade100.withOpacity(0.5),
                          blurRadius: 20,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Avatar and greeting - Flexible to prevent overflow
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blue.shade400,
                                      Colors.blue.shade600
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: CircleAvatar(
                                  radius:
                                      MediaQuery.of(context).size.width < 360
                                          ? 20
                                          : 24,
                                  backgroundImage:
                                      const AssetImage('assets/prof_pic.png'),
                                ),
                              ),
                              SizedBox(
                                  width: MediaQuery.of(context).size.width < 360
                                      ? 8
                                      : 12),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hi, Welcome Back!',
                                      style: TextStyle(
                                        color: Colors.blue.shade600,
                                        fontWeight: FontWeight.w500,
                                        fontSize:
                                            MediaQuery.of(context).size.width <
                                                    360
                                                ? 11
                                                : 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      username,
                                      style: TextStyle(
                                        fontSize:
                                            MediaQuery.of(context).size.width <
                                                    360
                                                ? 14
                                                : 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black87,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    )
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),

                        // Icons on the right
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                iconSize:
                                    MediaQuery.of(context).size.width < 360
                                        ? 20
                                        : 24,
                                padding: EdgeInsets.all(
                                    MediaQuery.of(context).size.width < 360
                                        ? 8
                                        : 12),
                                constraints: const BoxConstraints(),
                                icon: Icon(
                                  Icons.notifications_outlined,
                                  color: Colors.blue.shade600,
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => NotificationsPage()),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Builder(
                              builder: (context) => Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: IconButton(
                                  iconSize:
                                      MediaQuery.of(context).size.width < 360
                                          ? 20
                                          : 24,
                                  padding: EdgeInsets.all(
                                      MediaQuery.of(context).size.width < 360
                                          ? 8
                                          : 12),
                                  constraints: const BoxConstraints(),
                                  icon: Icon(
                                    Icons.menu,
                                    color: Colors.blue.shade600,
                                  ),
                                  onPressed: () {
                                    Scaffold.of(context).openEndDrawer();
                                  },
                                ),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.blue.shade50,
                          Colors.blue.shade100.withOpacity(0.5),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.blue.shade200.withOpacity(0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.shade100.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade600,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.event_note,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Next Appointment',
                              style: TextStyle(
                                color: Colors.blue.shade800,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.blue.shade100.withOpacity(0.5),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.two_wheeler,
                                      color: Colors.blue.shade600,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _nextApptDoc?.data()?['service'] ??
                                            'No Service',
                                        style: TextStyle(
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      color: Colors.grey.shade600,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _nextApptDoc != null
                                            ? _formatDateTime(((_nextApptDoc!
                                                        .data()?['dateTime'])
                                                    as Timestamp)
                                                .toDate())
                                            : 'No Upcoming Date',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 12,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Make action cards responsive with Flexible
                  // Row(
                  //   children: [
                  //     Expanded(
                  //       child: GestureDetector(
                  //         onTap: () {
                  //           Navigator.push(
                  //             context,
                  //             MaterialPageRoute(
                  //                 builder: (_) => const BookingAppointmentsPage(
                  //                       preselectedService: '',
                  //                     )),
                  //           );
                  //         },
                  //         child: _actionCard(
                  //             Icons.calendar_today, 'Book\nAppointment'),
                  //       ),
                  //     ),
                  //     const SizedBox(width: 16),
                  //     Expanded(
                  //       child: GestureDetector(
                  //         onTap: () async {
                  //           await Navigator.push(
                  //             context,
                  //             MaterialPageRoute(
                  //                 builder: (_) => const MyAppointmentsPage(
                  //                     appointments: [])),
                  //           );
                  //           _loadNextAppointment();
                  //         },
                  //         child:
                  //             _actionCard(Icons.event_note, 'My\nAppointments'),
                  //       ),
                  //     ),
                  //   ],
                  // ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AIChatbotPage()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.teal.shade50,
                            Colors.teal.shade100.withOpacity(0.5),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.teal.shade200.withOpacity(0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.teal.shade100.withOpacity(0.4),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.teal.shade500,
                                  Colors.teal.shade700
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.teal.shade300.withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.smart_toy_outlined,
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI Repair Assistant',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: Colors.teal.shade800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Get instant repair recommendations',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.teal.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: Colors.teal.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade600,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.miscellaneous_services,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Our Services',
                        style: TextStyle(
                          color: Colors.blue.shade800,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _serviceItem('General Maintenance &\nRepairs',
                      'assets/motor.jpg', context),
                  _serviceItem('Engine & Electrical\nWork',
                      'assets/seasonal.png', context),
                  _serviceItem('Performance &\nCustomization',
                      'assets/tuning.jpg', context),
                  _serviceItem('Custom Work &\nAccessories Installation',
                      'assets/accesories.jpg', context),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
          bottomNavigationBar: BottomNavigationBar(
            onTap: (index) async {
              if (index == 0) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HomePage()),
                );
              } else if (index == 1) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const MyAppointmentsPage(appointments: [])),
                );
                _loadNextAppointment();
              } else if (index == 2) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ProfilePage()),
                );
              }
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
              BottomNavigationBarItem(
                  icon: Icon(Icons.calendar_month), label: ''),
              BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline), label: ''),
            ],
            selectedItemColor: Colors.blue,
            unselectedItemColor: Colors.grey,
            showSelectedLabels: false,
            showUnselectedLabels: false,
            type: BottomNavigationBarType.fixed,
          ),
        );
      },
    );
  }

  Widget _actionCard(IconData icon, String label) {
    // Use LayoutBuilder to make cards responsive
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate responsive padding based on screen width
        final screenWidth = MediaQuery.of(context).size.width;
        final cardPadding = screenWidth < 360 ? 12.0 : 16.0;
        final iconSize = screenWidth < 360 ? 20.0 : 24.0;
        final fontSize = screenWidth < 360 ? 12.0 : 14.0;

        return Container(
          padding: EdgeInsets.all(cardPadding),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Colors.blue.shade50.withOpacity(0.3),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.blue.shade100.withOpacity(0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.shade100.withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(screenWidth < 360 ? 10 : 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade400, Colors.red.shade600],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.shade300.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, size: iconSize, color: Colors.white),
              ),
              SizedBox(height: screenWidth < 360 ? 8 : 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _serviceItem(String title, String imagePath, BuildContext context) {
    final serviceDescriptions = {
      'General Maintenance &\nRepairs':
          'Covers oil changes, tire checks, brake repairs, and general upkeep.',
      'Engine & Electrical\nWork':
          'Diagnose engine issues, wiring, spark plugs, and battery checks.',
      'Performance &\nCustomization':
          'Tune-ups, exhaust upgrades, suspension modifications, and racing kits.',
      'Custom Work &\nAccessories Installation':
          'Install accessories, lighting, storage, and modify visuals.',
    };

    final mechanicData = {
      'General Maintenance &\nRepairs': ['John Cruz', 'ASE Certified', 5],
      'Engine & Electrical\nWork': ['Mark Reyes', 'Electrical Tech Expert', 8],
      'Performance &\nCustomization': [
        'Lucas Tan',
        'Performance Specialist',
        6
      ],
      'Custom Work &\nAccessories Installation': [
        'Ella Lim',
        'Custom Bike Builder',
        4
      ],
    };

    final description =
        serviceDescriptions[title] ?? 'Service description not available.';
    final mechanicInfoRaw = mechanicData[title] ?? ['Unknown', 'N/A', 0];
    final String mechanicName = mechanicInfoRaw[0] as String;
    final String credentials = mechanicInfoRaw[1] as String;
    final int experienceYears = mechanicInfoRaw[2] as int;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ServiceDetailPage(
              title: title,
              description: description,
              imagePath: imagePath,
              mechanicName: mechanicName,
              credentials: credentials,
              experienceYears: experienceYears,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.blue.shade100.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.shade50.withOpacity(0.8),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.blue.shade100,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  imagePath,
                  width: 65,
                  height: 65,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    // Show placeholder icon when image is not found
                    return Container(
                      width: 65,
                      height: 65,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue.shade400, Colors.blue.shade600],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.build_circle,
                        color: Colors.white,
                        size: 32,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Professional service',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade500, Colors.blue.shade700],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.shade300.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ServiceDetailPage(
                        title: title,
                        description: description,
                        imagePath: imagePath,
                        mechanicName: mechanicName,
                        credentials: credentials,
                        experienceYears: experienceYears,
                      ),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Book',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _modernDrawerTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (iconColor ?? Colors.blue.shade600).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: iconColor ?? Colors.blue.shade600,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: textColor ?? Colors.grey.shade800,
          ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}

class NotificationsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: const Center(child: Text('No new notifications')),
    );
  }
}

class AIChatbotPage extends StatefulWidget {
  const AIChatbotPage({Key? key}) : super(key: key);

  @override
  State<AIChatbotPage> createState() => _AIChatbotPageState();
}

class _AIChatbotPageState extends State<AIChatbotPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..loadHtmlString(_html, baseUrl: 'https://app.local');
  }

  static const String _html = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <style>
    html, body { height: 100%; margin: 0; padding: 0; }
    #wrap { position: fixed; inset: 0; width: 100%; height: 100%; }
    #agent-iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; display: block; }
  </style>
  <title>AI Assistant</title>
  
</head>
<body>
  <div id="wrap">
    <iframe
      id="agent-iframe"
      title="Lorenz: Motorcycle Troubleshooting Expert"
      allow="geolocation; microphone; camera; fullscreen"
      src="https://agent.jotform.com/019a9c618a827d89847c4f3a23147d6ce36a?embedMode=iframe&background=1&shadow=1"
      frameborder="0"
      scrolling="yes">
    </iframe>
  </div>
<script src='https://cdn.jotfor.ms/s/umd/c0e42b950eb/for-form-embed-handler.js'></script>
<script>
  window.jotformEmbedHandler("iframe#agent-iframe",
    "https://www.jotform.com")
</script>
</body>
</html>
""";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox.expand(
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}

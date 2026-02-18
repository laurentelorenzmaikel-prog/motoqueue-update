import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminFeedbackPage extends StatefulWidget {
  const AdminFeedbackPage({super.key});

  @override
  State<AdminFeedbackPage> createState() => _AdminFeedbackPageState();
}

class _AdminFeedbackPageState extends State<AdminFeedbackPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> feedbackList = [];
  bool isLoading = true;

  // Pagination
  int currentPage = 0;
  final int rowsPerPage = 10;
  int? sortColumnIndex;
  bool sortAscending = true;

  // Service types
  final List<String> serviceTypes = [
    'General Maintenance & Repairs',
    'Engine & Electrical Work',
    'Performance & Customization',
    'Custom Work & Accessories Installation',
  ];

  void refresh() {
    _loadFeedback();
  }

  @override
  void initState() {
    super.initState();
    _loadFeedback();
  }

  int get totalPages => (feedbackList.length / rowsPerPage).ceil();

  List<Map<String, dynamic>> get paginatedFeedback {
    final startIndex = currentPage * rowsPerPage;
    final endIndex = (startIndex + rowsPerPage).clamp(0, feedbackList.length);
    if (startIndex >= feedbackList.length) return [];
    return feedbackList.sublist(startIndex, endIndex);
  }

  // Calculate average rating for each service type
  Map<String, double> _calculateAverageRatings() {
    Map<String, List<int>> serviceRatings = {
      for (final s in serviceTypes) s: <int>[]
    };

    // Collect ratings for each normalized service
    for (var feedback in feedbackList) {
      final rawService = (feedback['service'] ?? '').toString();
      final canonical = _canonicalizeService(rawService);

      final rating = feedback['rating'];
      int parsed = 0;
      if (rating is int) {
        parsed = rating;
      } else if (rating is num) {
        parsed = rating.round();
      } else {
        parsed = int.tryParse(rating?.toString() ?? '') ?? 0;
      }

      if (canonical != null && parsed > 0) {
        serviceRatings[canonical]!.add(parsed);
      }
    }

    // Calculate averages
    Map<String, double> averages = {};
    serviceRatings.forEach((service, ratings) {
      if (ratings.isNotEmpty) {
        averages[service] = ratings.reduce((a, b) => a + b) / ratings.length;
      } else {
        averages[service] = 0.0;
      }
    });

    return averages;
  }

  // Get icon for service type
  IconData _getServiceIcon(String service) {
    switch (service) {
      case 'General Maintenance & Repairs':
        return Icons.build_rounded;
      case 'Engine & Electrical Work':
        return Icons.electric_bolt_rounded;
      case 'Performance & Customization':
        return Icons.speed_rounded;
      case 'Custom Work & Accessories Installation':
        return Icons.auto_awesome_rounded;
      default:
        return Icons.miscellaneous_services_rounded;
    }
  }

  // Get color for service type
  Color _getServiceColor(String service) {
    switch (service) {
      case 'General Maintenance & Repairs':
        return const Color(0xFF3B82F6); // Blue
      case 'Engine & Electrical Work':
        return const Color(0xFFEF4444); // Red
      case 'Performance & Customization':
        return const Color(0xFF8B5CF6); // Purple
      case 'Custom Work & Accessories Installation':
        return const Color(0xFF10B981); // Green
      default:
        return const Color(0xFF6B7280); // Gray
    }
  }

  Widget _buildAverageRatingCards() {
    final averages = _calculateAverageRatings();
    final counts = _calculateFeedbackCounts();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.5,
      ),
      itemCount: serviceTypes.length,
      itemBuilder: (context, index) {
        final service = serviceTypes[index];
        final average = averages[service] ?? 0.0;
        final count = counts[service] ?? 0;
        final color = _getServiceColor(service);
        final icon = _getServiceIcon(service);

        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withOpacity(0.1),
                  color.withOpacity(0.05),
                ],
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        color: color,
                        size: 28,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            color: Colors.amber.shade600,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            average > 0 ? average.toStringAsFixed(1) : 'N/A',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        service,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // Star rating visualization
                      Builder(builder: (context) {
                        final fullStars = average.floor();
                        final hasHalf =
                            (average - fullStars) >= 0.5 && fullStars < 5;
                        return Row(
                          children: List.generate(5, (i) {
                            IconData icon;
                            if (i < fullStars) {
                              icon = Icons.star_rounded;
                            } else if (i == fullStars && hasHalf) {
                              icon = Icons.star_half_rounded;
                            } else {
                              icon = Icons.star_border_rounded;
                            }
                            return Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: Icon(
                                icon,
                                color: Colors.amber.shade600,
                                size: 16,
                              ),
                            );
                          }),
                        );
                      }),
                      const SizedBox(height: 4),
                      Text(
                        count > 0 ? '$count ratings' : 'No ratings',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Map<String, int> _calculateFeedbackCounts() {
    final Map<String, int> counts = {for (var s in serviceTypes) s: 0};
    for (final f in feedbackList) {
      final rawService = (f['service'] ?? '').toString();
      final canonical = _canonicalizeService(rawService);
      final rating = f['rating'];
      int parsed = 0;
      if (rating is int) {
        parsed = rating;
      } else if (rating is num) {
        parsed = rating.round();
      } else {
        parsed = int.tryParse(rating?.toString() ?? '') ?? 0;
      }
      if (canonical != null && parsed > 0) {
        counts[canonical] = (counts[canonical] ?? 0) + 1;
      }
    }
    return counts;
  }

  String? _canonicalizeService(String raw) {
    if (raw.isEmpty) return null;
    String norm(String s) =>
        s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), "").trim();

    final normalizedRaw = norm(raw);
    // Try exact normalized match first
    for (final s in serviceTypes) {
      if (norm(s) == normalizedRaw) return s;
    }
    // Try contains-based fallback (handles minor phrasing differences)
    for (final s in serviceTypes) {
      final ns = norm(s);
      if (normalizedRaw.contains(ns) || ns.contains(normalizedRaw)) return s;
    }
    // Keyword-based fallback mapping
    final rawLower = raw.toLowerCase();
    bool hasAll(List<String> kws) => kws.every((k) => rawLower.contains(k));

    if (hasAll(['maintenance']) &&
        (rawLower.contains('repair') ||
            rawLower.contains('repairs') ||
            rawLower.contains('service'))) {
      return 'General Maintenance & Repairs';
    }
    if (rawLower.contains('engine') || rawLower.contains('electrical')) {
      return 'Engine & Electrical Work';
    }
    if (rawLower.contains('performance') ||
        rawLower.contains('customization')) {
      return 'Performance & Customization';
    }
    if (rawLower.contains('custom') ||
        rawLower.contains('accessor') ||
        rawLower.contains('installation')) {
      return 'Custom Work & Accessories Installation';
    }
    return null;
  }

  Future<void> _deleteFeedback(String feedbackId, String userName) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Text('Confirm Delete'),
            ],
          ),
          content: Text(
            'Are you sure you want to delete the feedback from "$userName"?\n\nThis action cannot be undone.',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    // If user confirmed, proceed with deletion
    if (confirmed == true) {
      try {
        await _firestore.collection('feedback').doc(feedbackId).delete();

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Feedback deleted successfully'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 2),
            ),
          );

          // Reload the feedback list
          _loadFeedback();
        }
      } catch (e) {
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Error deleting feedback: $e')),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Widget _buildFeedbackDataTable() {
    int _parseRating(dynamic r) {
      if (r is int) return r;
      if (r is num) return r.round();
      return int.tryParse(r?.toString() ?? '') ?? 0;
    }

    DateTime _parseDate(dynamic ts) {
      try {
        return (ts as Timestamp).toDate();
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    void _sortByRating(bool ascending) {
      feedbackList.sort((a, b) {
        final ar = _parseRating(a['rating']);
        final br = _parseRating(b['rating']);
        return ascending ? ar.compareTo(br) : br.compareTo(ar);
      });
    }

    void _sortByDate(bool ascending) {
      feedbackList.sort((a, b) {
        final ad = _parseDate(a['createdAt']);
        final bd = _parseDate(b['createdAt']);
        return ascending ? ad.compareTo(bd) : bd.compareTo(ad);
      });
    }

    final dataRows = paginatedFeedback.map((f) {
      final rating = (f['rating'] is int)
          ? f['rating'] as int
          : int.tryParse(f['rating']?.toString() ?? '') ?? 0;
      final message = (f['message'] ?? f['feedback'] ?? '').toString();
      final user = (f['userName'] ?? 'Anonymous').toString();
      final service = (f['service'] ?? '—').toString();
      final createdAt = _formatDate(f['createdAt']);
      final feedbackId = f['id'] ?? '';

      return DataRow(cells: [
        DataCell(Text(user, overflow: TextOverflow.ellipsis)),
        DataCell(Text(service, overflow: TextOverflow.ellipsis)),
        DataCell(Row(
          children: List.generate(
            5,
            (i) => Icon(
              i < rating ? Icons.star_rounded : Icons.star_border_rounded,
              color: Colors.amber.shade600,
              size: 16,
            ),
          ),
        )),
        DataCell(Text(message, maxLines: 2, overflow: TextOverflow.ellipsis)),
        DataCell(Text(createdAt)),
        DataCell(
          IconButton(
            onPressed: () => _deleteFeedback(feedbackId, user),
            icon: const Icon(Icons.delete_outline_rounded),
            color: Colors.red,
            tooltip: 'Delete feedback',
            iconSize: 20,
            splashRadius: 20,
          ),
        ),
      ]);
    }).toList();

    // Add empty rows to maintain fixed table size
    final emptyRowsCount = rowsPerPage - dataRows.length;
    final emptyRows = List.generate(
      emptyRowsCount,
      (index) => DataRow(cells: [
        const DataCell(Text('')),
        const DataCell(Text('')),
        const DataCell(Text('')),
        const DataCell(Text('')),
        const DataCell(Text('')),
        const DataCell(Text('')),
      ]),
    );

    final rows = [...dataRows, ...emptyRows];

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
                headingRowColor: WidgetStateProperty.resolveWith(
                    (states) => Colors.grey.shade100),
                columnSpacing: 24,
                sortColumnIndex: sortColumnIndex,
                sortAscending: sortAscending,
                columns: [
                  const DataColumn(label: Text('User')),
                  const DataColumn(label: Text('Service')),
                  DataColumn(
                    label: const Text('Rating'),
                    onSort: (index, ascending) {
                      setState(() {
                        sortColumnIndex = index;
                        sortAscending = ascending;
                        _sortByRating(ascending);
                        currentPage = 0;
                      });
                    },
                  ),
                  const DataColumn(label: Text('Comment')),
                  DataColumn(
                    label: const Text('Date'),
                    onSort: (index, ascending) {
                      setState(() {
                        sortColumnIndex = index;
                        sortAscending = ascending;
                        _sortByDate(ascending);
                        currentPage = 0;
                      });
                    },
                  ),
                  const DataColumn(label: Text('Action')),
                ],
                rows: rows,
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
                    'Showing ${feedbackList.isEmpty ? 0 : currentPage * rowsPerPage + 1} - ${((currentPage + 1) * rowsPerPage).clamp(0, feedbackList.length)} of ${feedbackList.length} entries',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Row(
                    children: [
                      // First page button
                      IconButton(
                        onPressed: currentPage > 0
                            ? () => setState(() => currentPage = 0)
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
                        onPressed: currentPage > 0
                            ? () => setState(() => currentPage--)
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
                          'Page ${totalPages == 0 ? 0 : currentPage + 1} of $totalPages',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // Next page button
                      IconButton(
                        onPressed: currentPage < totalPages - 1
                            ? () => setState(() => currentPage++)
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
                        onPressed: currentPage < totalPages - 1
                            ? () => setState(() => currentPage = totalPages - 1)
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

  Future<void> _loadFeedback() async {
    setState(() => isLoading = true);
    try {
      final snapshot = await _firestore
          .collection('feedback')
          .orderBy('createdAt', descending: true)
          .get();

      setState(() {
        feedbackList = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
        isLoading = false;
        currentPage = 0; // Reset to first page on refresh
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: Column(
        children: [
          // Header with refresh button only
          Container(
            padding: const EdgeInsets.all(24),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // const Text(
                //   'Feedback Management',
                //   style: TextStyle(
                //     fontSize: 24,
                //     fontWeight: FontWeight.bold,
                //     color: Color(0xFF1F2937),
                //   ),
                // ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : feedbackList.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.feedback_outlined,
                                size: 64, color: Color(0xFF9CA3AF)),
                            SizedBox(height: 16),
                            Text(
                              'No feedback yet',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'User feedback will appear here',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Average Rating Cards Section
                            const Text(
                              'Service Ratings Overview',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildAverageRatingCards(),
                            const SizedBox(height: 32),

                            // Feedback Table Section
                            const Text(
                              'All Feedback',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildFeedbackDataTable(),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Unknown date';
    try {
      final date = (timestamp as Timestamp).toDate();
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      } else if (difference.inDays == 1) {
        return 'Yesterday at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return 'Unknown date';
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lorenz_app/services/prediction_service.dart';
import 'package:lorenz_app/services/dart_prediction_client.dart';

enum PredictionRange { weekly, monthly, yearly }

/// Admin Predictions Page - Displays inventory forecasts and analytics
class PredictionsPage extends ConsumerStatefulWidget {
  const PredictionsPage({super.key});

  @override
  ConsumerState<PredictionsPage> createState() => _PredictionsPageState();
}

class _PredictionsPageState extends ConsumerState<PredictionsPage> {
  final PredictionService _predictionService = PredictionService();
  RestockForecast? _forecast;
  List<ServiceUsage> _topServices = [];
  List<SparePartUsage> _topSpareParts = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _apiAvailable = false;
  PredictionRange _selectedRange = PredictionRange.monthly;

  // Responsive breakpoints
  bool get isMobile => MediaQuery.of(context).size.width < 768;
  bool get isTablet =>
      MediaQuery.of(context).size.width >= 768 &&
      MediaQuery.of(context).size.width < 1024;

  void refresh() {
    _loadData();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  int _daysForRange(PredictionRange range) {
    switch (range) {
      case PredictionRange.weekly:
        return 7;
      case PredictionRange.monthly:
        return 30;
      case PredictionRange.yearly:
        return 90;
    }
  }

  String _rangeLabel(PredictionRange range) {
    switch (range) {
      case PredictionRange.weekly:
        return 'Weekly';
      case PredictionRange.monthly:
        return 'Monthly';
      case PredictionRange.yearly:
        return 'Yearly';
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check API health
      _apiAvailable = await checkApiHealth();

      // Load all data in parallel
      final results = await Future.wait([
        _predictionService
            .getInventoryForecast(forecastDays: _daysForRange(_selectedRange)),
        _predictionService.getTopServices(limit: 3),
        _predictionService.getTopSpareParts(limit: 3),
      ]);

      if (mounted) {
        setState(() {
          _forecast = results[0] as RestockForecast?;
          _topServices = results[1] as List<ServiceUsage>;
          _topSpareParts = results[2] as List<SparePartUsage>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading data: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading predictions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? 16 : 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    _buildHeader(),
                    const SizedBox(height: 24),

                    // API Status Banner
                    if (!_apiAvailable) _buildApiWarningBanner(),

                    // Error Message
                    if (_errorMessage != null) _buildErrorMessage(),

                    // Inventory Forecast Section (show when API is available)
                    if (_apiAvailable) ...[
                      _buildSectionTitle(
                          '📦 Inventory Forecast (${_rangeLabel(_selectedRange)})'),
                      const SizedBox(height: 16),
                      _buildRangeSelector(),
                      if (_selectedRange == PredictionRange.yearly) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Showing up to 90 days due to API limits.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _forecast == null
                          ? _buildNoDataCard('No forecast data available')
                          : _buildForecastCard(),
                      const SizedBox(height: 32),
                    ],

                    // Top Services Section
                    _buildSectionTitle('🔧 Top 3 Most Used Services'),
                    const SizedBox(height: 16),
                    _topServices.isEmpty
                        ? _buildNoDataCard('No service data available')
                        : _buildTopServicesCard(),
                    const SizedBox(height: 32),

                    // Top Spare Parts Section
                    _buildSectionTitle('⚙️ Top 3 Most Used Spare Parts'),
                    const SizedBox(height: 16),
                    _topSpareParts.isEmpty
                        ? _buildNoDataCard('No spare parts data available')
                        : _buildTopSparePartsCard(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRangeSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Weekly'),
          selected: _selectedRange == PredictionRange.weekly,
          onSelected: (v) async {
            if (!v) return;
            setState(() {
              _selectedRange = PredictionRange.weekly;
            });
            await _loadData();
          },
        ),
        ChoiceChip(
          label: const Text('Monthly'),
          selected: _selectedRange == PredictionRange.monthly,
          onSelected: (v) async {
            if (!v) return;
            setState(() {
              _selectedRange = PredictionRange.monthly;
            });
            await _loadData();
          },
        ),
        ChoiceChip(
          label: const Text('Yearly'),
          selected: _selectedRange == PredictionRange.yearly,
          onSelected: (v) async {
            if (!v) return;
            setState(() {
              _selectedRange = PredictionRange.yearly;
            });
            await _loadData();
          },
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.analytics, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Predictive Analytics',
                style: TextStyle(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Inventory forecasting & usage analytics',
                style: TextStyle(
                  fontSize: isMobile ? 13 : 14,
                  color: const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadData,
          tooltip: 'Refresh data',
        ),
      ],
    );
  }

  Widget _buildApiWarningBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'API Service Unavailable',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The inventory forecast API is not running. Please start the Python API service to see forecasts.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: isMobile ? 18 : 20,
        fontWeight: FontWeight.bold,
        color: const Color(0xFF1A1A1A),
      ),
    );
  }

  Widget _buildNoDataCard(String message) {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(MaterialColor color, String label, String range) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color.shade400,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color.shade700,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            range,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildForecastCard() {
    if (_forecast == null || _forecast!.totalRestockDemand.isEmpty) {
      return _buildNoDataCard('No forecast data available');
    }

    final sortedDemand = _forecast!.totalRestockDemand.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF3B82F6).withOpacity(0.1),
            const Color(0xFF8B5CF6).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph, color: Color(0xFF3B82F6), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Restock Forecast',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    if (_forecast!.startDate != null &&
                        _forecast!.endDate != null)
                      Text(
                        '${_forecast!.startDate} to ${_forecast!.endDate}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Color Legend
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLegendItem(
                    Colors.red, 'Restock Immediately', '10+ units'),
                _buildLegendItem(Colors.orange, 'Plan to Restock', '5-9 units'),
                _buildLegendItem(Colors.green, 'Monitor Only', '0-4 units'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...sortedDemand.map((entry) {
            final partName = entry.key;
            final quantity = entry.value;
            final maxQuantity = sortedDemand.first.value;
            final percentage = maxQuantity > 0 ? quantity / maxQuantity : 0.0;

            // Determine urgency level and action text
            String actionText;
            MaterialColor actionColor;
            if (quantity > 10) {
              actionText = 'Restock Immediately';
              actionColor = Colors.red;
            } else if (quantity > 5) {
              actionText = 'Plan to Restock';
              actionColor = Colors.orange;
            } else {
              actionText = 'Monitor Only';
              actionColor = Colors.green;
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              partName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 14,
                                  color: actionColor.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  actionText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: actionColor.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: quantity > 10
                              ? Colors.red.shade50
                              : quantity > 5
                                  ? Colors.orange.shade50
                                  : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$quantity units',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: quantity > 10
                                ? Colors.red.shade700
                                : quantity > 5
                                    ? Colors.orange.shade700
                                    : Colors.green.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentage,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        quantity > 10
                            ? Colors.red.shade400
                            : quantity > 5
                                ? Colors.orange.shade400
                                : Colors.green.shade400,
                      ),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTopServicesCard() {
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
        children: _topServices.asMap().entries.map((entry) {
          final index = entry.key;
          final service = entry.value;
          final isFirst = index == 0;

          return Container(
            margin: EdgeInsets.only(bottom: isFirst ? 0 : 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isFirst
                  ? const Color(0xFF3B82F6).withOpacity(0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isFirst
                  ? Border.all(color: const Color(0xFF3B82F6).withOpacity(0.2))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isFirst
                        ? const Color(0xFF3B82F6)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isFirst ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              isFirst ? FontWeight.bold : FontWeight.w600,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${service.count} appointment${service.count != 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isFirst)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Most Popular',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTopSparePartsCard() {
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
        children: _topSpareParts.asMap().entries.map((entry) {
          final index = entry.key;
          final part = entry.value;
          final isFirst = index == 0;

          return Container(
            margin: EdgeInsets.only(bottom: isFirst ? 0 : 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isFirst
                  ? const Color(0xFF10B981).withOpacity(0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isFirst
                  ? Border.all(color: const Color(0xFF10B981).withOpacity(0.2))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isFirst
                        ? const Color(0xFF10B981)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isFirst ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        part.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              isFirst ? FontWeight.bold : FontWeight.w600,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${part.count} unit${part.count != 1 ? 's' : ''} used',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isFirst)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Most Used',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

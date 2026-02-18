import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lorenz_app/Home.dart';
import 'package:lorenz_app/services/booking_service.dart';

class BookingAppointmentsPage extends StatefulWidget {
  final String preselectedService; // Properly store the preselected service

  const BookingAppointmentsPage({
    super.key,
    required this.preselectedService,
  });

  @override
  State<BookingAppointmentsPage> createState() =>
      _BookingAppointmentsPageState();
}

class _BookingAppointmentsPageState extends State<BookingAppointmentsPage> {
  String selectedService = '';
  DateTime? selectedDate;
  String?
      selectedTimeSlot; // Now stores full time slot string (e.g., "8:00 AM")
  final brandController = TextEditingController();
  final plateController = TextEditingController();
  final _bookingService = BookingService();

  // Track available slots for selected date
  List<String> availableTimeSlots = [];
  Map<String, int> slotAvailability = {}; // Maps time slot to remaining spots
  bool isLoadingSlots = false;
  String? availabilityMessage;

  // Simple loading state instead of complex dialog overlay
  bool _isSubmitting = false;

  // Check if service was preselected (coming from BookPage)
  bool get _hasPreselectedService => widget.preselectedService.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Use the preselected service if provided
    selectedService = widget.preselectedService;
  }

  /// Load available time slots when date is selected
  Future<void> _loadAvailableSlots(DateTime date) async {
    setState(() {
      isLoadingSlots = true;
      availabilityMessage = null;
      selectedTimeSlot = null; // Reset selection when date changes
    });

    // Get current user ID for checking user-specific availability
    final uid = FirebaseAuth.instance.currentUser?.uid;

    try {
      // Load available slots (excludes full slots and user's existing bookings)
      final slots = await _bookingService.getAvailableTimeSlots(
        date: date,
        userId: uid,
      );

      // Load availability info (remaining spots per slot)
      final availability = await _bookingService.getSlotAvailabilityInfo(
        date: date,
      );

      // Filter out past slots if the selected date is today
      List<String> filteredSlots = [];
      Map<String, int> filteredAvailability = {};
      final now = DateTime.now();

      if (_isToday(date)) {
        for (final slot in slots) {
          final slotDateTime = _parseSlotToDateTime(slot, date);
          if (slotDateTime.isAfter(now)) {
            filteredSlots.add(slot);
            filteredAvailability[slot] = availability[slot] ?? 0;
          }
        }
      } else {
        filteredSlots = slots;
        filteredAvailability = availability;
      }

      if (mounted) {
        setState(() {
          availableTimeSlots = filteredSlots;
          slotAvailability = filteredAvailability;
          isLoadingSlots = false;

          if (filteredSlots.isEmpty) {
            availabilityMessage =
                'No slots available for this date. Please choose another day.';
          } else {
            final totalSpots = filteredAvailability.values.fold(0, (sum, spots) => sum + spots);
            availabilityMessage = '$totalSpots time slots available';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingSlots = false;
          availabilityMessage =
              'Unable to load availability. Check your connection.';
        });
      }
    }
  }

  /// Check if the given date is today
  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  /// Parse time slot string (e.g., "8:00 AM") to DateTime for the given date
  DateTime _parseSlotToDateTime(String slot, DateTime date) {
    final timeParts = slot.split(' '); // "8:00 AM" -> ["8:00", "AM"]
    final time = timeParts[0].split(':'); // "8:00" -> ["8", "00"]
    var hour = int.parse(time[0]);
    final minute = int.parse(time[1]);

    if (timeParts.length == 2 && timeParts[1].toUpperCase() == 'PM' && hour < 12) {
      hour += 12;
    }
    if (timeParts.length == 2 && timeParts[1].toUpperCase() == 'AM' && hour == 12) {
      hour = 0; // Midnight case
    }

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  Future<void> _submitBooking() async {
    // Validate required fields
    if (selectedService.isEmpty) {
      _showErrorSnackBar('Please select a service');
      return;
    }

    if (selectedDate == null) {
      _showErrorSnackBar('Please select a date');
      return;
    }

    if (selectedTimeSlot == null) {
      _showErrorSnackBar('Please select a time slot');
      return;
    }

    // Validate that the selected date and time are not in the past
    final now = DateTime.now();
    // Example format "8:00 AM"
    final timeParts = selectedTimeSlot!.split(' '); // "8:00 AM" -> ["8:00", "AM"]
    final time = timeParts[0].split(':'); // "8:00" -> ["8", "00"]
    var hour = int.parse(time[0]);
    final minute = int.parse(time[1]);

    if (timeParts.length == 2 && timeParts[1].toUpperCase() == 'PM' && hour < 12) {
      hour += 12;
    }
    if (timeParts.length == 2 && timeParts[1].toUpperCase() == 'AM' && hour == 12) {
      hour = 0; // Midnight case
    }

    final selectedDateTime = DateTime(
      selectedDate!.year,
      selectedDate!.month,
      selectedDate!.day,
      hour,
      minute,
    );

    // Allow a small buffer (e.g., 1 minute) to account for processing time
    if (selectedDateTime.isBefore(now.subtract(const Duration(minutes: 1)))) {
      _showErrorSnackBar('You cannot book an appointment in the past.');
      return;
    }

    if (brandController.text.trim().isEmpty) {
      _showErrorSnackBar('Please enter your motorcycle brand');
      return;
    }

    // Get current user ID
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showErrorSnackBar('Please log in to book an appointment');
      return;
    }

    // Set loading state
    setState(() => _isSubmitting = true);

    try {
      // Create booking with comprehensive validation
      final reference = await _bookingService.createBooking(
        userId: uid,
        service: selectedService,
        date: selectedDate!,
        timeSlot: selectedTimeSlot!,
        motorBrand: brandController.text.trim(),
        plateNumber: plateController.text.trim().isEmpty
            ? null
            : plateController.text.trim(),
      );

      // Navigate to confirmation page
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BookingConfirmationPage(
              service: selectedService,
              date: selectedDate!,
              time: selectedTimeSlot!,
              brand: brandController.text.trim(),
              plate: plateController.text.trim(),
              reference: reference,
            ),
          ),
        );
      }
    } catch (e) {
      // Show specific error message
      if (mounted) {
        setState(() => _isSubmitting = false);
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        _showErrorSnackBar(errorMessage);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new,
              color: Colors.blue.shade600,
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.calendar_today,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Book Appointment',
              style: TextStyle(
                color: Colors.blue.shade800,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.blue.shade100,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Services Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.build_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _hasPreselectedService
                          ? 'Selected Service'
                          : 'Select Service',
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Service Cards - Show only preselected or all services
                ..._buildServiceCards(),
                const SizedBox(height: 32),

                // Date & Time Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.schedule_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Select Date & Time',
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Date Picker Card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.shade50.withOpacity(0.8),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose Date',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        CalendarDatePicker(
                          initialDate: selectedDate ??
                              DateTime.now().add(const Duration(days: 1)),
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 90)),
                          onDateChanged: (date) {
                            setState(() {
                              selectedDate = date;
                            });
                            // Load available slots for selected date
                            _loadAvailableSlots(date);
                          },
                        ),

                        // Show availability status
                        if (selectedDate != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isLoadingSlots
                                  ? Colors.blue.shade50
                                  : availableTimeSlots.isEmpty
                                      ? Colors.red.shade50
                                      : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isLoadingSlots
                                    ? Colors.blue.shade200
                                    : availableTimeSlots.isEmpty
                                        ? Colors.red.shade200
                                        : Colors.green.shade200,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isLoadingSlots
                                      ? Icons.hourglass_empty
                                      : availableTimeSlots.isEmpty
                                          ? Icons.event_busy
                                          : Icons.event_available,
                                  color: isLoadingSlots
                                      ? Colors.blue.shade600
                                      : availableTimeSlots.isEmpty
                                          ? Colors.red.shade600
                                          : Colors.green.shade600,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    isLoadingSlots
                                        ? 'Checking availability...'
                                        : availabilityMessage ?? '',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isLoadingSlots
                                          ? Colors.blue.shade700
                                          : availableTimeSlots.isEmpty
                                              ? Colors.red.shade700
                                              : Colors.green.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Time Selection Card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.shade50.withOpacity(0.8),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              color: Colors.blue.shade600,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Select Time Slot',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Show time slots or placeholder
                        if (selectedDate == null)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  color: Colors.grey.shade500,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Please select a date first',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (isLoadingSlots)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (availableTimeSlots.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.event_busy,
                                  color: Colors.red.shade600,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'No available slots for this date',
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: availableTimeSlots.map((slot) {
                              final isSelected = selectedTimeSlot == slot;
                              final remainingSpots =
                                  slotAvailability[slot] ?? 0;

                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    selectedTimeSlot = slot;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.blue.shade600
                                        : Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.blue.shade600
                                          : Colors.blue.shade200,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        slot,
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.blue.shade800,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$remainingSpots spots left',
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white70
                                              : Colors.grey.shade600,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Motor Details Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.two_wheeler_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Motor Details',
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Motor Details Card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.shade50.withOpacity(0.8),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Motor Brand *',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: brandController,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade800,
                          ),
                          decoration: InputDecoration(
                            hintText: 'e.g. Honda, Yamaha, Suzuki',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                            ),
                            filled: true,
                            fillColor: Colors.blue.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.blue.shade600,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Plate Number (Optional)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: plateController,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade800,
                          ),
                          decoration: InputDecoration(
                            hintText: 'e.g. ABC-1234',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                            ),
                            filled: true,
                            fillColor: Colors.blue.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.blue.shade600,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Book Appointment Button
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isSubmitting
                          ? [Colors.grey.shade400, Colors.grey.shade500]
                          : [Colors.blue.shade600, Colors.blue.shade800],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _isSubmitting
                            ? Colors.grey.shade300.withOpacity(0.5)
                            : Colors.blue.shade300.withOpacity(0.5),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _isSubmitting ? null : _submitBooking,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isSubmitting) ...[
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Booking...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else ...[
                          const Icon(
                            Icons.calendar_month,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Book Appointment',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build service cards - shows only preselected service if coming from BookPage,
  /// otherwise shows all available services
  List<Widget> _buildServiceCards() {
    final allServices = [
      {
        'title': 'General Maintenance & Repairs',
        'icon': Icons.build_circle_outlined,
        'description': 'Oil changes, tire checks, brake repairs',
      },
      {
        'title': 'Engine & Electrical Work',
        'icon': Icons.electrical_services_outlined,
        'description': 'Engine diagnostics, wiring, battery checks',
      },
      {
        'title': 'Performance & Customization',
        'icon': Icons.speed_outlined,
        'description': 'Tune-ups, exhaust upgrades, modifications',
      },
      {
        'title': 'Custom Work & Accessories Installation',
        'icon': Icons.construction_outlined,
        'description': 'Accessories, lighting, storage installation',
      },
    ];

    // If a service was preselected from BookPage, show only that service
    List<Map<String, dynamic>> servicesToShow;

    if (_hasPreselectedService) {
      // Find the matching service or create a generic one
      final matchingService = allServices.firstWhere(
        (s) => s['title'] == widget.preselectedService,
        orElse: () => {
          'title': widget.preselectedService,
          'icon': Icons.build_circle_outlined,
          'description': 'Selected service',
        },
      );
      servicesToShow = [matchingService];
    } else {
      // Show all services when accessed directly
      servicesToShow = allServices;
    }

    return servicesToShow.map((service) {
      final isSelected = selectedService == service['title'];

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.blue.shade300
                : Colors.blue.shade100.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? Colors.blue.shade100.withOpacity(0.6)
                  : Colors.blue.shade50.withOpacity(0.4),
              blurRadius: isSelected ? 12 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            // Only allow tapping to select if NOT preselected
            onTap: _hasPreselectedService
                ? null // Disable selection - service is locked
                : () {
                    setState(() {
                      selectedService = service['title'] as String;
                    });
                  },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.blue.shade600
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      service['icon'] as IconData,
                      color: isSelected ? Colors.white : Colors.blue.shade600,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['title'] as String,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.blue.shade800
                                : Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          service['description'] as String,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Show checkmark for selected/preselected service
                  if (isSelected)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}

// ============================================================================
// BOOKING CONFIRMATION PAGE
// ============================================================================

class BookingConfirmationPage extends StatelessWidget {
  final String service;
  final DateTime date;
  final String time;
  final String brand;
  final String plate;
  final String reference;

  const BookingConfirmationPage({
    super.key,
    required this.service,
    required this.date,
    required this.time,
    required this.brand,
    required this.plate,
    required this.reference,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Success Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade400, Colors.green.shade600],
                    ),
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.shade200.withOpacity(0.6),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.white,
                    size: 60,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Booking Confirmed!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your Appointment Has Been Scheduled',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 32),

                // Details Card
                Container(
                  padding: const EdgeInsets.all(24),
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
                        blurRadius: 20,
                        offset: const Offset(0, 8),
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
                              Icons.receipt_long,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Booking Details',
                            style: TextStyle(
                              color: Colors.blue.shade800,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildModernLabelValue('Booking Reference', reference),
                      _buildModernLabelValue('Service', service,
                          isHighlighted: true),
                      _buildModernLabelValue(
                          'Date & Time', '${_formatDate(date)} – $time'),
                      _buildModernLabelValue('Motor Details', brand),
                      _buildModernLabelValue('Estimated Time', '2–3 Hours',
                          isLast: true),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Return to Dashboard Button
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade600, Colors.blue.shade800],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.shade300.withOpacity(0.5),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const HomePage()),
                        (route) => false,
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.home_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Return to Dashboard',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

  Widget _buildModernLabelValue(String label, String value,
      {bool isHighlighted = false, bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              padding: isHighlighted
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                  : null,
              decoration: isHighlighted
                  ? BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.blue.shade200,
                        width: 1,
                      ),
                    )
                  : null,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w600,
                  color: isHighlighted
                      ? Colors.blue.shade800
                      : Colors.grey.shade800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${_monthName(date.month)} ${date.day}, ${date.year}';
  }

  String _monthName(int month) {
    const months = [
      '',
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
    return months[month];
  }
}

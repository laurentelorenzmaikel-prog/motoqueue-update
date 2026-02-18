import 'package:cloud_firestore/cloud_firestore.dart';

/// Result of a booking validation check
class BookingValidationResult {
  final bool isValid;
  final String? errorMessage;

  BookingValidationResult.success()
      : isValid = true,
        errorMessage = null;

  BookingValidationResult.failure(this.errorMessage) : isValid = false;
}

/// Service for managing appointment bookings with strict validation
class BookingService {
  final FirebaseFirestore _firestore;

  // Configuration constants
  static const int maxBookingsPerSlot = 2; // Maximum 2 bookings per time slot
  static const int slotDurationMinutes = 120; // 2-hour slots

  BookingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ============================================================================
  // CORE VALIDATION METHODS
  // ============================================================================

  /// Check if the time slot has reached maximum capacity (2 bookings)
  /// Returns the current booking count for the slot
  Future<int> getSlotBookingCount({
    required DateTime date,
    required String timeSlot,
  }) async {
    try {
      final querySnapshot = await _firestore
          .collection('appointments')
          .where('date', isEqualTo: _formatDateOnly(date))
          .where('timeSlot', isEqualTo: timeSlot)
          .where('status', whereIn: ['pending', 'confirmed', 'in_process'])
          .get(const GetOptions(source: Source.server));

      return querySnapshot.docs.length;
    } catch (e) {
      print('Error checking slot booking count: $e');
      rethrow;
    }
  }

  /// Check if a specific user has already booked the same time slot on the same date
  Future<bool> hasUserAlreadyBooked({
    required String userId,
    required DateTime date,
    required String timeSlot,
  }) async {
    try {
      final querySnapshot = await _firestore
          .collection('appointments')
          .where('date', isEqualTo: _formatDateOnly(date))
          .where('timeSlot', isEqualTo: timeSlot)
          .where('userId', isEqualTo: userId)
          .where('status', whereIn: ['pending', 'confirmed', 'in_process'])
          .get(const GetOptions(source: Source.server));

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking user booking: $e');
      rethrow;
    }
  }

  /// Comprehensive validation for a booking request
  /// Returns BookingValidationResult with success or specific error message
  Future<BookingValidationResult> validateBooking({
    required String userId,
    required DateTime date,
    required String timeSlot,
  }) async {
    try {
      // 1. Check if date is in the past
      final now = DateTime.now();
      final bookingDate = DateTime(date.year, date.month, date.day);
      final today = DateTime(now.year, now.month, now.day);

      if (bookingDate.isBefore(today)) {
        return BookingValidationResult.failure(
            'Cannot book appointments in the past.');
      }

      // 2. Check if date is too far in the future (max 90 days)
      final maxDate = today.add(const Duration(days: 90));
      if (bookingDate.isAfter(maxDate)) {
        return BookingValidationResult.failure(
            'Cannot book more than 3 months in advance.');
      }

      // 3. Check if it's a weekday
      if (date.weekday == DateTime.saturday ||
          date.weekday == DateTime.sunday) {
        return BookingValidationResult.failure(
            'Appointments are only available on weekdays.');
      }

      // 4. Check if user already booked this slot (PREVENT DUPLICATE)
      final userAlreadyBooked = await hasUserAlreadyBooked(
        userId: userId,
        date: date,
        timeSlot: timeSlot,
      );

      if (userAlreadyBooked) {
        return BookingValidationResult.failure(
            'You have already booked this time slot.');
      }

      // 5. Check if slot is full (MAX 2 BOOKINGS)
      final currentBookings = await getSlotBookingCount(
        date: date,
        timeSlot: timeSlot,
      );

      if (currentBookings >= maxBookingsPerSlot) {
        return BookingValidationResult.failure(
            'This time slot is already full.');
      }

      // All checks passed
      return BookingValidationResult.success();
    } catch (e) {
      return BookingValidationResult.failure(
          'Booking failed. Please check your connection and try again.');
    }
  }

  // ============================================================================
  // BOOKING CREATION
  // ============================================================================

  /// Create a new booking after validation
  /// Returns the booking reference number on success
  /// Throws an exception with a user-friendly message on failure
  Future<String> createBooking({
    required String userId,
    required String service,
    required DateTime date,
    required String timeSlot,
    required String motorBrand,
    String? plateNumber,
  }) async {
    // Step 1: Validate the booking request
    final validation = await validateBooking(
      userId: userId,
      date: date,
      timeSlot: timeSlot,
    );

    if (!validation.isValid) {
      throw Exception(validation.errorMessage);
    }

    // Step 2: Generate unique reference number
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final reference = 'MQ-${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}-$timestamp';

    // Step 3: Parse time slot to create full DateTime
    final dateTime = _parseTimeSlotToDateTime(date, timeSlot);

    // Step 4: Create the appointment document
    await _firestore.collection('appointments').add({
      'userId': userId,
      'service': service,
      'date': _formatDateOnly(date), // Store date as string for easy querying
      'timeSlot': timeSlot, // Store time slot string (e.g., "8:00 AM")
      'dateTime': Timestamp.fromDate(dateTime), // Full DateTime for compatibility
      'motorBrand': motorBrand,
      'plateNumber': plateNumber ?? '',
      'reference': reference,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    return reference;
  }

  // ============================================================================
  // AVAILABILITY METHODS
  // ============================================================================

  /// Get available time slots for a specific date
  /// Returns list of time slot strings (e.g., ["8:00 AM", "10:00 AM", "2:00 PM"])
  Future<List<String>> getAvailableTimeSlots({
    required DateTime date,
    String? userId,
  }) async {
    // Define all possible time slots
    final allSlots = [
      '8:00 AM',
      '10:00 AM',
      '12:00 PM',
      '2:00 PM',
      '4:00 PM',
    ];

    List<String> availableSlots = [];

    for (final slot in allSlots) {
      // Check booking count for this slot
      final bookingCount = await getSlotBookingCount(
        date: date,
        timeSlot: slot,
      );

      // Only add if slot has capacity
      if (bookingCount < maxBookingsPerSlot) {
        // If userId provided, also check if user already booked
        if (userId != null) {
          final userBooked = await hasUserAlreadyBooked(
            userId: userId,
            date: date,
            timeSlot: slot,
          );
          if (!userBooked) {
            availableSlots.add(slot);
          }
        } else {
          availableSlots.add(slot);
        }
      }
    }

    return availableSlots;
  }

  /// Get slot availability info with remaining spots
  Future<Map<String, int>> getSlotAvailabilityInfo({
    required DateTime date,
  }) async {
    final allSlots = [
      '8:00 AM',
      '10:00 AM',
      '12:00 PM',
      '2:00 PM',
      '4:00 PM',
    ];

    Map<String, int> availability = {};

    for (final slot in allSlots) {
      final bookingCount = await getSlotBookingCount(
        date: date,
        timeSlot: slot,
      );
      final remainingSpots = maxBookingsPerSlot - bookingCount;
      availability[slot] = remainingSpots.clamp(0, maxBookingsPerSlot);
    }

    return availability;
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  /// Format date to string for Firestore queries (YYYY-MM-DD)
  String _formatDateOnly(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Parse time slot string to full DateTime
  DateTime _parseTimeSlotToDateTime(DateTime date, String timeSlot) {
    // Parse "8:00 AM" or "2:00 PM" format
    final parts = timeSlot.split(' ');
    final timeParts = parts[0].split(':');
    int hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    final isPM = parts[1].toUpperCase() == 'PM';

    // Convert to 24-hour format
    if (isPM && hour != 12) {
      hour += 12;
    } else if (!isPM && hour == 12) {
      hour = 0;
    }

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  /// Format time slot for display
  static String formatTimeSlot(int hour, int minute) {
    final isPM = hour >= 12;
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final period = isPM ? 'PM' : 'AM';
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }
}

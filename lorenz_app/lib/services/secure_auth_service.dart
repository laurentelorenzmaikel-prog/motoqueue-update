import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

enum UserRole { admin, user, mechanic }

class UserProfile {
  final String uid;
  final String email;
  final UserRole role;
  final String displayName;
  final bool isActive;
  final DateTime createdAt;
  final DateTime lastLoginAt;
  final Map<String, dynamic> permissions;

  UserProfile({
    required this.uid,
    required this.email,
    required this.role,
    required this.displayName,
    required this.isActive,
    required this.createdAt,
    required this.lastLoginAt,
    required this.permissions,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      role: UserRole.values.firstWhere(
        (r) => r.toString().split('.').last == map['role'],
        orElse: () => UserRole.user,
      ),
      displayName: map['displayName'] ?? '',
      isActive: map['isActive'] ?? true,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastLoginAt:
          (map['lastLoginAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      permissions: Map<String, dynamic>.from(map['permissions'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'role': role.toString().split('.').last,
      'displayName': displayName,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt': Timestamp.fromDate(lastLoginAt),
      'permissions': permissions,
    };
  }

  bool hasPermission(String permission) {
    return permissions[permission] == true;
  }

  bool canAccessAdmin() {
    return role == UserRole.admin && isActive;
  }
}

class SecurityEvent {
  final String eventType;
  final String userId;
  final String userEmail;
  final DateTime timestamp;
  final String ipAddress;
  final String userAgent;
  final Map<String, dynamic> details;

  SecurityEvent({
    required this.eventType,
    required this.userId,
    required this.userEmail,
    required this.timestamp,
    required this.ipAddress,
    required this.userAgent,
    required this.details,
  });

  Map<String, dynamic> toMap() {
    return {
      'eventType': eventType,
      'userId': userId,
      'userEmail': userEmail,
      'timestamp': Timestamp.fromDate(timestamp),
      'ipAddress': ipAddress,
      'userAgent': userAgent,
      'details': details,
    };
  }
}

class SecureAuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  GoogleSignIn? _googleSignIn;

  static const int _maxLoginAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 30);
  static const Duration _sessionTimeout = Duration(hours: 8);

  SecureAuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _googleSignIn = googleSignIn;

  /// Lazy initialization of GoogleSignIn to avoid errors on web without client ID
  GoogleSignIn _getGoogleSignIn() {
    if (_googleSignIn == null) {
      try {
        _googleSignIn = GoogleSignIn(
          signInOption: SignInOption.standard,
          clientId: '579238365079-sb2julgnhjt43kt85bbcjn0mlqtnpfnf.apps.googleusercontent.com',
        );
      } catch (e) {
        throw Exception(
            'Google Sign-In not configured. Please add client ID for web platform.');
      }
    }
    return _googleSignIn!;
  }

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  // Enhanced sign-in with security checks
  Future<UserProfile> signInWithEmail({
    required String email,
    required String password,
    String? ipAddress,
    String? userAgent,
  }) async {
    await _validateEmail(email);
    await _checkAccountLockout(email);

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        throw Exception('Authentication failed');
      }

      final userProfile = await _getUserProfile(credential.user!.uid);

      if (!userProfile.isActive) {
        await _auth.signOut();
        throw Exception('Account is deactivated. Please contact support.');
      }

      // Update last login and reset failed attempts
      await _updateLastLogin(userProfile.uid);
      await _resetFailedAttempts(email);

      // Log successful login
      await _logSecurityEventWithDetails(
        eventType: 'LOGIN_SUCCESS',
        userId: userProfile.uid,
        userEmail: email,
        ipAddress: ipAddress ?? 'unknown',
        userAgent: userAgent ?? 'unknown',
        details: {'method': 'email_password'},
      );

      return userProfile;
    } catch (e) {
      // Log failed attempt
      await _incrementFailedAttempts(email);
      await _logSecurityEventWithDetails(
        eventType: 'LOGIN_FAILED',
        userId: 'unknown',
        userEmail: email,
        ipAddress: ipAddress ?? 'unknown',
        userAgent: userAgent ?? 'unknown',
        details: {'method': 'email_password', 'error': e.toString()},
      );
      rethrow;
    }
  }

  // Enhanced sign-up with role assignment
  Future<UserProfile> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    UserRole role = UserRole.user,
    String? ipAddress,
    String? userAgent,
  }) async {
    await _validateEmail(email);
    await _validatePassword(password);

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user == null) {
        throw Exception('Account creation failed');
      }

      // Update display name
      await credential.user!.updateDisplayName(displayName);

      // Send email verification
      await credential.user!.sendEmailVerification();

      // Create user profile
      final userProfile = UserProfile(
        uid: credential.user!.uid,
        email: email,
        role: role,
        displayName: displayName,
        isActive: true,
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
        permissions: _getDefaultPermissions(role),
      );

      await _createUserProfile(userProfile);

      // Log account creation
      await _logSecurityEventWithDetails(
        eventType: 'ACCOUNT_CREATED',
        userId: userProfile.uid,
        userEmail: email,
        ipAddress: ipAddress ?? 'unknown',
        userAgent: userAgent ?? 'unknown',
        details: {'method': 'email_password', 'role': role.toString(), 'emailVerificationSent': true},
      );

      return userProfile;
    } catch (e) {
      await _logSecurityEventWithDetails(
        eventType: 'SIGNUP_FAILED',
        userId: 'unknown',
        userEmail: email,
        ipAddress: ipAddress ?? 'unknown',
        userAgent: userAgent ?? 'unknown',
        details: {'method': 'email_password', 'error': e.toString()},
      );
      rethrow;
    }
  }

  // Enhanced Google sign-in
  Future<UserProfile> signInWithGoogle({
    String? ipAddress,
    String? userAgent,
  }) async {
    try {
      UserCredential authResult;

      if (kIsWeb) {
        // Use Firebase Auth popup for Web - avoids JavaScript Origin configuration issues
        final googleProvider = GoogleAuthProvider();
        authResult = await _auth.signInWithPopup(googleProvider);
      } else {
        // Standard flow for Mobile
        final googleUser = await _getGoogleSignIn().signIn();
        if (googleUser == null) {
          throw Exception('Google Sign-In aborted');
        }

        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        authResult = await _auth.signInWithCredential(credential);
      }

      if (authResult.user == null) {
        throw Exception('Google authentication failed');
      }

      UserProfile userProfile;
      try {
        userProfile = await _getUserProfile(authResult.user!.uid);
      } catch (e) {
        // Create new user profile for first-time Google users
        userProfile = UserProfile(
          uid: authResult.user!.uid,
          email: authResult.user!.email ?? '',
          role: UserRole.user,
          displayName: authResult.user!.displayName ?? '',
          isActive: true,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
          permissions: _getDefaultPermissions(UserRole.user),
        );
        await _createUserProfile(userProfile);
      }

      if (!userProfile.isActive) {
        await _auth.signOut();
        await _googleSignIn?.signOut();
        throw Exception('Account is deactivated. Please contact support.');
      }

      await _updateLastLogin(userProfile.uid);

      await _logSecurityEventWithDetails(
        eventType: 'LOGIN_SUCCESS',
        userId: userProfile.uid,
        userEmail: userProfile.email,
        ipAddress: ipAddress ?? 'unknown',
        userAgent: userAgent ?? 'unknown',
        details: {'method': 'google_oauth'},
      );

      return userProfile;
    } catch (e) {
      await _logSecurityEventWithDetails(
        eventType: 'LOGIN_FAILED',
        userId: 'unknown',
        userEmail: 'unknown',
        ipAddress: ipAddress ?? 'unknown',
        userAgent: userAgent ?? 'unknown',
        details: {'method': 'google_oauth', 'error': e.toString()},
      );
      rethrow;
    }
  }

  // Secure sign-out with session cleanup
  Future<void> signOut({
    String? ipAddress,
    String? userAgent,
  }) async {
    final user = currentUser;
    if (user != null) {
      await _logSecurityEventWithDetails(
        eventType: 'LOGOUT',
        userId: user.uid,
        userEmail: user.email ?? '',
        ipAddress: ipAddress ?? 'unknown',
        userAgent: userAgent ?? 'unknown',
        details: {},
      );
    }

    await _auth.signOut();
    await _googleSignIn?.signOut();
  }

  // Get user profile
  Future<UserProfile> getUserProfile(String uid) async {
    return await _getUserProfile(uid);
  }

  // Update user role (admin only)
  Future<void> updateUserRole(String uid, UserRole newRole) async {
    final currentUserProfile = await _getCurrentUserProfile();
    if (!currentUserProfile.canAccessAdmin()) {
      throw Exception('Insufficient permissions');
    }

    await _firestore.collection('users').doc(uid).update({
      'role': newRole.toString().split('.').last,
      'permissions': _getDefaultPermissions(newRole),
    });

    await _logSecurityEventWithDetails(
      eventType: 'ROLE_UPDATED',
      userId: currentUserProfile.uid,
      userEmail: currentUserProfile.email,
      ipAddress: 'unknown',
      userAgent: 'unknown',
      details: {'targetUserId': uid, 'newRole': newRole.toString()},
    );
  }

  // Deactivate user account (admin only)
  Future<void> deactivateUser(String uid) async {
    final currentUserProfile = await _getCurrentUserProfile();
    if (!currentUserProfile.canAccessAdmin()) {
      throw Exception('Insufficient permissions');
    }

    await _firestore.collection('users').doc(uid).update({
      'isActive': false,
    });

    await _logSecurityEventWithDetails(
      eventType: 'ACCOUNT_DEACTIVATED',
      userId: currentUserProfile.uid,
      userEmail: currentUserProfile.email,
      ipAddress: 'unknown',
      userAgent: 'unknown',
      details: {'targetUserId': uid},
    );
  }

  // Check if session is valid
  Future<bool> isSessionValid() async {
    final user = currentUser;
    if (user == null) return false;

    try {
      final userProfile = await _getUserProfile(user.uid);
      if (!userProfile.isActive) return false;

      final timeSinceLastLogin =
          DateTime.now().difference(userProfile.lastLoginAt);
      return timeSinceLastLogin <= _sessionTimeout;
    } catch (e) {
      return false;
    }
  }

  // Send email verification
  Future<void> sendEmailVerification() async {
    final user = currentUser;
    if (user == null) {
      throw Exception('No authenticated user');
    }

    if (user.emailVerified) {
      throw Exception('Email is already verified');
    }

    try {
      await user.sendEmailVerification();

      await _logSecurityEventWithDetails(
        eventType: 'EMAIL_VERIFICATION_SENT',
        userId: user.uid,
        userEmail: user.email ?? '',
        ipAddress: 'unknown',
        userAgent: 'unknown',
        details: {},
      );
    } catch (e) {
      throw Exception('Failed to send verification email: ${e.toString()}');
    }
  }

  // Check if current user's email is verified
  bool isEmailVerified() {
    final user = currentUser;
    return user?.emailVerified ?? false;
  }

  // Reload user to check verification status
  Future<bool> reloadAndCheckEmailVerification() async {
    final user = currentUser;
    if (user == null) return false;

    try {
      await user.reload();
      // Get fresh user instance after reload
      final refreshedUser = _auth.currentUser;
      return refreshedUser?.emailVerified ?? false;
    } catch (e) {
      return false;
    }
  }

  // Private helper methods
  Future<UserProfile> _getUserProfile(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) {
      // Create a basic profile for legacy users who don't have a Firestore document
      final user = _auth.currentUser;
      if (user != null && user.uid == uid) {
        final newProfile = UserProfile(
          uid: uid,
          email: user.email ?? 'unknown@email.com',
          role: UserRole.user,
          displayName: user.displayName ?? 'User',
          isActive: true,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
          permissions: _getDefaultPermissions(UserRole.user),
        );
        await _createUserProfile(newProfile);
        return newProfile;
      }
      throw Exception('User profile not found');
    }
    return UserProfile.fromMap(doc.data()!);
  }

  Future<UserProfile> _getCurrentUserProfile() async {
    final user = currentUser;
    if (user == null) {
      throw Exception('No authenticated user');
    }
    return await _getUserProfile(user.uid);
  }

  Future<void> _createUserProfile(UserProfile profile) async {
    await _firestore.collection('users').doc(profile.uid).set(profile.toMap());
  }

  Future<void> _updateLastLogin(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'lastLoginAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> _validateEmail(String email) async {
    if (email.isEmpty || !email.contains('@')) {
      throw Exception('Invalid email format');
    }
  }

  Future<void> _validatePassword(String password) async {
    if (password.length < 8) {
      throw Exception('Password must be at least 8 characters long');
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      throw Exception('Password must contain at least one uppercase letter');
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      throw Exception('Password must contain at least one lowercase letter');
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      throw Exception('Password must contain at least one number');
    }
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      throw Exception('Password must contain at least one special character');
    }
  }

  Future<void> _checkAccountLockout(String email) async {
    try {
      final doc =
          await _firestore.collection('security').doc('failed_attempts').get();
      if (doc.exists) {
        final data = doc.data()!;
        final attempts = data[email] as Map<String, dynamic>?;

        if (attempts != null) {
          final count = attempts['count'] as int? ?? 0;
          final lastAttempt = (attempts['lastAttempt'] as Timestamp?)?.toDate();

          if (count >= _maxLoginAttempts && lastAttempt != null) {
            final timeSinceLastAttempt = DateTime.now().difference(lastAttempt);
            if (timeSinceLastAttempt < _lockoutDuration) {
              throw Exception(
                  'Account locked due to too many failed attempts. Try again in ${_lockoutDuration.inMinutes - timeSinceLastAttempt.inMinutes} minutes.');
            }
          }
        }
      }
    } catch (e) {
      // If security document doesn't exist or can't be accessed, allow login to proceed
      // Only re-throw if it's an actual account lockout exception
      if (e.toString().contains('Account locked')) {
        rethrow;
      }
      // Otherwise, silently continue with login attempt
      return;
    }
  }

  Future<void> _incrementFailedAttempts(String email) async {
    try {
      final docRef = _firestore.collection('security').doc('failed_attempts');

      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        final data = doc.exists ? doc.data()! : <String, dynamic>{};

        final attempts = data[email] as Map<String, dynamic>? ?? {};
        final currentCount = attempts['count'] as int? ?? 0;

        data[email] = {
          'count': currentCount + 1,
          'lastAttempt': Timestamp.fromDate(DateTime.now()),
        };

        transaction.set(docRef, data);
      });
    } catch (e) {
      // Silently fail if we can't increment failed attempts
      // This prevents blocking login due to security tracking issues
      // Log error but don't block login
    }
  }

  Future<void> _resetFailedAttempts(String email) async {
    try {
      final docRef = _firestore.collection('security').doc('failed_attempts');

      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        if (doc.exists) {
          final data = doc.data()!;
          data.remove(email);
          transaction.set(docRef, data);
        }
      });
    } catch (e) {
      // Silently fail if we can't reset failed attempts
      // This prevents blocking login due to security tracking issues
    }
  }

  Future<void> _logSecurityEvent(SecurityEvent event) async {
    try {
      await _firestore.collection('security_logs').add(event.toMap());
    } catch (e) {
      // Silently fail if we can't log security events
      // This prevents blocking operations due to logging issues
    }
  }

  Future<void> _logSecurityEventWithDetails({
    required String eventType,
    required String userId,
    required String userEmail,
    required String ipAddress,
    required String userAgent,
    required Map<String, dynamic> details,
  }) async {
    try {
      final event = SecurityEvent(
        eventType: eventType,
        userId: userId,
        userEmail: userEmail,
        timestamp: DateTime.now(),
        ipAddress: ipAddress,
        userAgent: userAgent,
        details: details,
      );

      await _logSecurityEvent(event);
    } catch (e) {
      // Silently fail if we can't log security events
      // This prevents blocking operations due to logging issues
    }
  }

  Map<String, dynamic> _getDefaultPermissions(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return {
          'view_dashboard': true,
          'manage_users': true,
          'manage_appointments': true,
          'view_analytics': true,
          'manage_inventory': true,
          'system_settings': true,
        };
      case UserRole.mechanic:
        return {
          'view_dashboard': true,
          'manage_appointments': true,
          'view_analytics': false,
          'manage_inventory': true,
          'system_settings': false,
        };
      case UserRole.user:
        return {
          'book_appointments': true,
          'view_appointments': true,
          'provide_feedback': true,
        };
    }
  }
}

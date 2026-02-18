import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lorenz_app/providers/admin_providers.dart';
import 'package:lorenz_app/services/secure_auth_service.dart';
import 'package:intl/intl.dart';

class UsersManagementPage extends ConsumerStatefulWidget {
  const UsersManagementPage({super.key});

  @override
  ConsumerState<UsersManagementPage> createState() =>
      _UsersManagementPageState();
}

class _UsersManagementPageState extends ConsumerState<UsersManagementPage> {
  String _searchQuery = '';
  UserRole? _filterRole;

  void refresh() {
    ref.refresh(allUsersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final allUsersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      body: Container(
        color: const Color(0xFFF5F7FA),
        child: Column(
          children: [
          // Search and Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                // Search Bar
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by email or name...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value.toLowerCase());
                  },
                ),
                const SizedBox(height: 12),

                // Role Filter
                Row(
                  children: [
                    const Text('Filter by role: ',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('All'),
                            selected: _filterRole == null,
                            onSelected: (_) =>
                                setState(() => _filterRole = null),
                          ),
                          FilterChip(
                            label: const Text('Admin'),
                            selected: _filterRole == UserRole.admin,
                            onSelected: (_) =>
                                setState(() => _filterRole = UserRole.admin),
                          ),
                          FilterChip(
                            label: const Text('User'),
                            selected: _filterRole == UserRole.user,
                            onSelected: (_) =>
                                setState(() => _filterRole = UserRole.user),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Users Grid
          Expanded(
            child: allUsersAsync.when(
              data: (users) {
                // Apply filters
                var filteredUsers = users.where((user) {
                  final matchesSearch =
                      user.email.toLowerCase().contains(_searchQuery) ||
                          user.displayName.toLowerCase().contains(_searchQuery);
                  final matchesRole =
                      _filterRole == null || user.role == _filterRole;
                  return matchesSearch && matchesRole;
                }).toList();

                if (filteredUsers.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No users found',
                            style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    return ref.refresh(allUsersProvider);
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 320,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = filteredUsers[index];
                      return _buildUserCard(context, user);
                    },
                  ),
                );
              },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64, color: Colors.red.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading users: ${error.toString()}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => ref.refresh(allUsersProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(BuildContext context, UserProfile user) {
    final roleColor = _getRoleColor(user.role);
    final statusColor = user.isActive ? Colors.green : Colors.red;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Profile Avatar at top
            CircleAvatar(
              radius: 40,
              backgroundColor: roleColor.withOpacity(0.2),
              child: Text(
                user.displayName.isNotEmpty
                    ? user.displayName[0].toUpperCase()
                    : 'U',
                style: TextStyle(
                  color: roleColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 32,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // User Name
            Text(
              user.displayName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),

            // Email
            Text(
              user.email,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),

            // Role and Status Badges
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    user.role.toString().split('.').last.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: roleColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    user.isActive ? 'ACTIVE' : 'INACTIVE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Join Date
            Text(
              'Joined: ${DateFormat('MMM dd, yyyy').format(user.createdAt)}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),

            const Spacer(),

            // Action Buttons at bottom
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showUserDetails(context, user),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('View', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showChangeRoleDialog(context, user),
                    icon: const Icon(Icons.admin_panel_settings, size: 16),
                    label: const Text('Role', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _handleActivationToggle(context, user),
                icon: Icon(
                  user.isActive ? Icons.block : Icons.check_circle,
                  size: 16,
                ),
                label: Text(
                  user.isActive ? 'Deactivate' : 'Activate',
                  style: const TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: user.isActive ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Colors.purple;
      case UserRole.user:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  void _handleActivationToggle(BuildContext context, UserProfile user) async {
    final adminService = ref.read(adminServiceProvider);

    try {
      if (user.isActive) {
        final confirmed = await _showConfirmDialog(
          context,
          'Deactivate User',
          'Are you sure you want to deactivate ${user.displayName}?',
        );
        if (confirmed == true) {
          await adminService.deactivateUser(user.uid);
          ref.invalidate(allUsersProvider);
          if (mounted) {
            _showSnackBar('User deactivated successfully', isError: false);
          }
        }
      } else {
        await adminService.activateUser(user.uid);
        ref.invalidate(allUsersProvider);
        if (mounted) {
          _showSnackBar('User activated successfully', isError: false);
        }
      }
    } catch (e) {
      _showSnackBar('Error: ${e.toString()}', isError: true);
    }
  }

  void _showUserDetails(BuildContext context, UserProfile user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(user.displayName),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Email', user.email),
              _buildDetailRow(
                  'Role', user.role.toString().split('.').last.toUpperCase()),
              _buildDetailRow('Status', user.isActive ? 'Active' : 'Inactive'),
              _buildDetailRow('User ID', user.uid),
              _buildDetailRow(
                  'Created', DateFormat('MMM dd, yyyy').format(user.createdAt)),
              _buildDetailRow('Last Login',
                  DateFormat('MMM dd, yyyy').format(user.lastLoginAt)),
              const SizedBox(height: 16),
              const Text('Permissions:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...user.permissions.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Row(
                      children: [
                        Icon(e.value ? Icons.check : Icons.close,
                            size: 16,
                            color: e.value ? Colors.green : Colors.red),
                        const SizedBox(width: 8),
                        Text(e.key),
                      ],
                    ),
                  )),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _showChangeRoleDialog(BuildContext context, UserProfile user) {
    UserRole? newRole = user.role;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change User Role'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Change role for ${user.displayName}'),
              const SizedBox(height: 16),
              RadioListTile<UserRole>(
                title: const Text('Admin'),
                value: UserRole.admin,
                groupValue: newRole,
                onChanged: (value) => setDialogState(() => newRole = value),
              ),
              RadioListTile<UserRole>(
                title: const Text('User'),
                value: UserRole.user,
                groupValue: newRole,
                onChanged: (value) => setDialogState(() => newRole = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (newRole != null && newRole != user.role) {
                  try {
                    final adminService = ref.read(adminServiceProvider);
                    await adminService.updateUserRole(user.uid, newRole!);
                    ref.invalidate(allUsersProvider);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    _showSnackBar('Role updated successfully', isError: false);
                  } catch (e) {
                    if (!context.mounted) return;
                    _showSnackBar('Error: ${e.toString()}', isError: true);
                  }
                } else {
                  Navigator.pop(context);
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showConfirmDialog(
      BuildContext context, String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

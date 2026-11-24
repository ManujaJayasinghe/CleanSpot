import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app/theme_proposal.dart';
import '../../../models/user_model.dart';
import '../../../services/firestore_service.dart';

/// Users tab allowing admins to search users, change their roles, and block/unblock accounts.
class AdminUsersTab extends StatefulWidget {
  final FirestoreService firestoreService;

  const AdminUsersTab({
    super.key,
    required this.firestoreService,
  });

  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<AdminUsersTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search Input
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search users by name, role or UID...',
              prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
        ),

        // User List
        Expanded(
          child: StreamBuilder<List<UserModel>>(
            stream: widget.firestoreService.watchAllUsers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error loading users: ${snapshot.error}',
                      style: AppTypography.body.copyWith(color: AppColors.errorText),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final allUsers = snapshot.data ?? [];
              final filteredUsers = allUsers.where((u) {
                if (_searchQuery.isEmpty) return true;
                final nameMatch = u.displayName.toLowerCase().contains(_searchQuery);
                final uidMatch = u.uid.toLowerCase().contains(_searchQuery);
                final roleMatch = u.role.toLowerCase().contains(_searchQuery);
                return nameMatch || uidMatch || roleMatch;
              }).toList();

              if (filteredUsers.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _searchQuery.isEmpty ? Icons.people_outline : Icons.search_off,
                          size: 48,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No users found.'
                              : 'No users matching "$_searchQuery".',
                          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: filteredUsers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final user = filteredUsers[index];
                  return _UserCard(
                    user: user,
                    firestoreService: widget.firestoreService,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final FirestoreService firestoreService;

  const _UserCard({
    required this.user,
    required this.firestoreService,
  });

  Color _roleColor(String role) {
    switch (role) {
      case kRoleAdmin:
        return const Color(0xFF7B1FA2); // Purple
      case kRoleAuthority:
        return const Color(0xFF0288D1); // Blue
      default:
        return AppColors.primary; // Green
    }
  }

  Color _roleBgColor(String role) {
    switch (role) {
      case kRoleAdmin:
        return const Color(0xFFF3E5F5);
      case kRoleAuthority:
        return const Color(0xFFE1F5FE);
      default:
        return AppColors.primaryLight;
    }
  }

  Future<void> _showRoleDialog(BuildContext context) async {
    String selectedRole = user.role;

    final newRole = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Change Role',
            style: AppTypography.heading.copyWith(fontSize: 18),
          ),
          content: RadioGroup<String>(
            groupValue: selectedRole,
            onChanged: (val) {
              if (val != null) {
                setDialogState(() => selectedRole = val);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select role for ${user.displayName.isNotEmpty ? user.displayName : user.uid}:',
                  style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                for (final role in kUserRoles)
                  RadioListTile<String>(
                    title: Text(
                      role.toUpperCase(),
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _roleColor(role),
                      ),
                    ),
                    subtitle: Text(
                      role == kRoleAdmin
                          ? 'Full admin access to dashboard & users'
                          : role == kRoleAuthority
                              ? 'Can verify and clear dengue hotspots'
                              : 'Standard community user',
                      style: AppTypography.caption,
                    ),
                    value: role,
                    activeColor: AppColors.primary,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, selectedRole),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Update Role'),
            ),
          ],
        ),
      ),
    );

    if (newRole != null && newRole != user.role && context.mounted) {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (user.uid == currentUid && newRole != kRoleAdmin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot remove the admin role from your own account.'),
            backgroundColor: AppColors.errorText,
          ),
        );
        return;
      }

      try {
        await firestoreService.setUserRole(user.uid, newRole);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Updated ${user.displayName}\'s role to ${newRole.toUpperCase()}'),
              backgroundColor: AppColors.primaryDark,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update role: $e'),
              backgroundColor: AppColors.errorText,
            ),
          );
        }
      }
    }
  }

  Future<void> _toggleBlock(BuildContext context) async {
    final willBlock = !user.blocked;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    if (willBlock && user.uid == currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot block your own admin account.'),
          backgroundColor: AppColors.errorText,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          willBlock ? 'Block User?' : 'Unblock User?',
          style: AppTypography.heading.copyWith(fontSize: 18),
        ),
        content: Text(
          willBlock
              ? 'Are you sure you want to block ${user.displayName.isNotEmpty ? user.displayName : user.uid}? They will be immediately signed out and blocked from saving any data.'
              : 'Restore access for ${user.displayName.isNotEmpty ? user.displayName : user.uid}?',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: willBlock ? AppColors.errorText : AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(willBlock ? 'Block' : 'Unblock'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        await firestoreService.setUserBlocked(user.uid, willBlock);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                willBlock
                    ? 'Blocked ${user.displayName.isNotEmpty ? user.displayName : user.uid}'
                    : 'Unblocked ${user.displayName.isNotEmpty ? user.displayName : user.uid}',
              ),
              backgroundColor: willBlock ? AppColors.errorText : AppColors.primaryDark,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Action failed: $e'),
              backgroundColor: AppColors.errorText,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.isNotEmpty ? user.displayName : 'User (${user.uid.substring(0, 6)})';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: user.blocked ? AppColors.errorBg : AppColors.border,
          width: user.blocked ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: user.blocked ? AppColors.errorBg : _roleBgColor(user.role),
              foregroundColor: user.blocked ? AppColors.errorText : _roleColor(user.role),
              radius: 20,
              child: Text(
                initial,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            if (user.blocked)
              const Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(
                  radius: 7,
                  backgroundColor: AppColors.errorText,
                  child: Icon(Icons.block, size: 10, color: Colors.white),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  decoration: user.blocked ? TextDecoration.lineThrough : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            // Role chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _roleBgColor(user.role),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                user.role.toUpperCase(),
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: _roleColor(user.role),
                ),
              ),
            ),
            if (user.blocked) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.errorBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'BLOCKED',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: AppColors.errorText,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                '${user.pointsBalance} pts',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 8),
              Text('•', style: AppTypography.caption),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'UID: ${user.uid}',
                  style: AppTypography.caption.copyWith(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (action) {
            if (action == 'role') {
              _showRoleDialog(context);
            } else if (action == 'block') {
              _toggleBlock(context);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'role',
              child: Row(
                children: [
                  Icon(Icons.manage_accounts_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('Change Role'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'block',
              child: Row(
                children: [
                  Icon(
                    user.blocked ? Icons.lock_open_outlined : Icons.block_outlined,
                    size: 18,
                    color: user.blocked ? AppColors.primary : AppColors.errorText,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    user.blocked ? 'Unblock User' : 'Block User',
                    style: TextStyle(
                      color: user.blocked ? AppColors.primary : AppColors.errorText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

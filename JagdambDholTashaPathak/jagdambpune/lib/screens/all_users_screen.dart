import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

class AllUsersScreen extends StatefulWidget {
  const AllUsersScreen({super.key});

  @override
  State<AllUsersScreen> createState() => _AllUsersScreenState();
}

class _AllUsersScreenState extends State<AllUsersScreen> {
  List<User> _users = [];
  List<User> _filteredUsers = [];
  String _statusFilter = 'all';

  bool _isLoading = true;
  String? _errorMessage;

  final TextEditingController _searchController = TextEditingController();

  int get _pendingCount =>
      _users.where((user) => user.isActive == false).length;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final users = await ApiService.fetchAllUsers();

      setState(() {
        _users = users;
        _filteredUsers = users;
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      if (_isSessionExpiredError(e)) {
        await _redirectToLoginWithMessage();
        return;
      }

      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      _filteredUsers = _users.where((user) {
        final name = '${user.firstName ?? ''} ${user.lastName ?? ''}'
            .toLowerCase();
        final matchesSearch = name.contains(query);

        final matchesStatus = switch (_statusFilter) {
          'pending' => user.isActive == false,
          'approved' => user.isActive != false,
          _ => true,
        };

        return matchesSearch && matchesStatus;
      }).toList();
    });
  }

  void _setStatusFilter(String status) {
    if (_statusFilter == status) {
      return;
    }
    _statusFilter = status;
    _applyFilters();
  }

  bool _isSessionExpiredError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('session expired') ||
        message.contains('login again') ||
        message.contains('no access token found');
  }

  Future<void> _redirectToLoginWithMessage() async {
    if (!mounted) {
      return;
    }

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Session Expired'),
        content: const Text('Your session has expired. Please login again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (!mounted) {
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _openUserDetails(User user) async {
    final userId = user.id;
    if (userId == null) {
      _showUserDetails(user);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final detailedUser = await ApiService.fetchUserById(userId);
      if (!mounted) return;
      _showUserDetails(detailedUser, fallbackUserId: userId);
    } catch (e) {
      if (!mounted) return;

      if (_isSessionExpiredError(e)) {
        await _redirectToLoginWithMessage();
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load user details: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _approveUser(int userId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await ApiService.activateUser(userId);

      try {
        await ApiService.sendPersonalNotification(
          targetUser: userId,
          title: 'Account Approved',
          message:
              'Your account has been approved by admin. You can now login.',
        );
      } catch (_) {
        // User activation already succeeded; notification failure should not block approval UX.
      }

      if (!mounted) return;

      Navigator.pop(context); // close details popup

      _markUserAsApprovedLocally(userId);

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Success'),
          content: const Text('User approved'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      if (_isSessionExpiredError(e)) {
        await _redirectToLoginWithMessage();
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to approve user: $e')));
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _markUserAsApprovedLocally(int userId) {
    _users = _users.map<User>((user) {
      if (user.id != userId) {
        return user;
      }

      return User(
        id: user.id,
        isActive: true,
        phoneNumber: user.phoneNumber,
        firstName: user.firstName,
        lastName: user.lastName,
        instrument: user.instrument,
        sex: user.sex,
        role: user.role,
        bloodGroup: user.bloodGroup,
        emergencyContactName: user.emergencyContactName,
        emergencyContactPhone: user.emergencyContactPhone,
        gatName: user.gatName,
        gatPramukhName: user.gatPramukhName,
      );
    }).toList();
    _applyFilters();
  }

  void _showUserDetails(User user, {int? fallbackUserId}) {
    final effectiveUserId = user.id ?? fallbackUserId;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryMaroon,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.accentYellow,
                child: Text(
                  _userInitial(user),
                  style: const TextStyle(
                    color: AppColors.primaryMaroon,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _fullName(user),
                  style: const TextStyle(
                    color: AppColors.textLight,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailCard(
                children: [
                  _row('Phone', user.phoneNumber),
                  _row('Role', user.role),
                  _row('Status', user.isActive == true ? 'Active' : 'Inactive'),
                  _row('Instrument', user.instrument),
                  _row('Sex', user.sex),
                  _row('Blood Group', user.bloodGroup),
                ],
              ),
              const SizedBox(height: 12),
              _detailCard(
                children: [
                  _row('Emergency Name', user.emergencyContactName),
                  _row('Emergency Phone', user.emergencyContactPhone),
                  _row('Gat Name', user.gatName),
                  _row('Gat Pramukh', user.gatPramukhName),
                ],
              ),
            ],
          ),
        ),
        actions: [
          if (user.isActive != true)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentYellow,
                foregroundColor: AppColors.primaryMaroon,
              ),
              onPressed: effectiveUserId == null
                  ? null
                  : () => _approveUser(effectiveUserId),
              child: const Text(
                'Approve',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(
                color: AppColors.primaryMaroon,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fullName(User user) {
    final firstName = user.firstName?.trim() ?? '';
    final lastName = user.lastName?.trim() ?? '';
    final fullName = '$firstName $lastName'.trim();
    return fullName.isEmpty ? 'Unknown User' : fullName;
  }

  String _userInitial(User user) {
    final firstName = user.firstName?.trim();
    if (firstName != null && firstName.isNotEmpty) {
      return firstName[0].toUpperCase();
    }
    return '?';
  }

  Widget _detailCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryMaroon.withAlpha(18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: AppColors.primaryMaroon.withAlpha(24)),
      ),
      child: Column(children: children),
    );
  }

  Widget _row(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.primaryMaroon,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value == null || value.trim().isEmpty ? '-' : value,
              style: const TextStyle(color: AppColors.primaryMaroon),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Users'),
        backgroundColor: AppColors.primaryMaroon,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryMaroon),
            )
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryMaroon.withAlpha(18),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.primaryMaroon,
                        size: 42,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryMaroon.withAlpha(16),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(
                        color: AppColors.primaryMaroon,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search by name...',
                        hintStyle: const TextStyle(color: AppColors.disabled),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: AppColors.primaryMaroon,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: AppColors.primaryMaroon.withAlpha(28),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppColors.accentYellow,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _statusFilter == 'all',
                        selectedColor: AppColors.accentYellow,
                        onSelected: (_) => _setStatusFilter('all'),
                        labelStyle: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text('Pending ($_pendingCount)'),
                        selected: _statusFilter == 'pending',
                        selectedColor: AppColors.accentYellow,
                        onSelected: (_) => _setStatusFilter('pending'),
                        labelStyle: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Approved'),
                        selected: _statusFilter == 'approved',
                        selectedColor: AppColors.accentYellow,
                        onSelected: (_) => _setStatusFilter('approved'),
                        labelStyle: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _filteredUsers.isEmpty
                      ? const Center(
                          child: Text(
                            'No users found',
                            style: TextStyle(
                              color: AppColors.primaryMaroon,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredUsers.length,
                          itemBuilder: (context, index) {
                            final user = _filteredUsers[index];

                            return Card(
                              color: Colors.white,
                              elevation: 5,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                onTap: () => _openUserDetails(user),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.accentYellow,
                                  child: Text(
                                    _userInitial(user),
                                    style: const TextStyle(
                                      color: AppColors.primaryMaroon,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  _fullName(user),
                                  style: const TextStyle(
                                    color: AppColors.primaryMaroon,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    user.role == null ||
                                            user.role!.trim().isEmpty
                                        ? 'Tap to view details'
                                        : user.role!,
                                    style: const TextStyle(
                                      color: AppColors.disabled,
                                    ),
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  color: AppColors.primaryMaroon,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

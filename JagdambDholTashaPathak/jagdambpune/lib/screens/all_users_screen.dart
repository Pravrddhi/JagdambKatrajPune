import 'package:flutter/material.dart';
import '../config/api_endpoints.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

class AllUsersScreen extends StatefulWidget {
  final bool showStatusFilters;
  final bool isPathakAdmin;
  final bool isGatPramukh;
  final String? gatPramukhName;

  const AllUsersScreen({
    super.key,
    this.showStatusFilters = true,
    this.isPathakAdmin = false,
    this.isGatPramukh = false,
    this.gatPramukhName,
  });

  @override
  State<AllUsersScreen> createState() => _AllUsersScreenState();
}

class _AllUsersScreenState extends State<AllUsersScreen> {
  List<User> _users = [];
  List<User> _filteredUsers = [];
  List<String> _gatFilterOptions = ['all'];
  Map<String, String> _gatAliasToCanonical = {};
  String _statusFilter = 'all';
  String _selectedGatName = 'all';

  bool _isLoading = true;
  String? _errorMessage;

  final TextEditingController _searchController = TextEditingController();

  int get _pendingCount => _users.where((user) => _isPending(user)).length;

  int get _rejectedCount => _users.where((user) => _isRejected(user)).length;

  bool _isPending(User user) => user.approvalStatus == 0;

  bool _isApproved(User user) => user.approvalStatus == 1;

  bool _isRejected(User user) => user.approvalStatus == 3;

  String _statusLabel(User user) {
    if (_isApproved(user)) return 'Approved';
    if (_isRejected(user)) return 'Rejected';
    if (_isPending(user)) return 'Pending';
    return user.isActive == true ? 'Active' : 'Inactive';
  }

  String _normalizeText(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  String _normalizeGat(String? value) => _normalizeText(value);

  String _resolveCanonicalGat(String? value) {
    final normalized = _normalizeGat(value);
    if (normalized.isEmpty) return normalized;
    return _gatAliasToCanonical[normalized] ?? normalized;
  }

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
      List<String> gatOptions = _gatFilterOptions;
      Map<String, String> gatAliasToCanonical = <String, String>{};

      if (widget.isPathakAdmin) {
        try {
          final gats = await ApiService.fetchGats();
          for (final gat in gats) {
            final name = gat['name']?.toString().trim();
            if (name == null || name.isEmpty) continue;
            final canonical = _normalizeGat(name);
            gatAliasToCanonical[canonical] = canonical;

            final id = gat['id']?.toString().trim();
            if (id != null && id.isNotEmpty) {
              gatAliasToCanonical[_normalizeGat(id)] = canonical;
            }
          }

          final names =
              gats
                  .map((gat) => gat['name']?.toString().trim())
                  .whereType<String>()
                  .where((name) => name.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
          gatOptions = ['all', ...names];
        } catch (_) {
          // Fallback to deriving gat names from users if gats endpoint fails.
          final names =
              users
                  .map((user) => user.gatName?.trim())
                  .whereType<String>()
                  .where((name) => name.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
          gatOptions = ['all', ...names];

          for (final name in names) {
            final normalized = _normalizeGat(name);
            gatAliasToCanonical[normalized] = normalized;
          }
        }
      }

      setState(() {
        _users = users;
        _filteredUsers = users;
        _gatFilterOptions = gatOptions;
        _gatAliasToCanonical = gatAliasToCanonical;
        if (_selectedGatName != 'all' &&
            !_gatFilterOptions.contains(_selectedGatName)) {
          _selectedGatName = 'all';
        }
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      if (_isSessionExpiredError(e)) {
        await _redirectToLoginWithMessage();
        return;
      }

      setState(() {
        _errorMessage = ApiEndpoints.genericApiFailureMessage;
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
          'pending' => _isPending(user),
          'rejected' => _isRejected(user),
          _ => true,
        };

        final userGat = user.gatName?.trim() ?? '';
        final normalizedUserGat = _resolveCanonicalGat(userGat);
        final normalizedSelectedGat = _resolveCanonicalGat(_selectedGatName);
        final matchesGat =
            !widget.isPathakAdmin ||
            _selectedGatName == 'all' ||
            normalizedUserGat == normalizedSelectedGat;

        final shouldApplyGatPramukhScope =
            widget.isGatPramukh && !widget.isPathakAdmin;
        final normalizedLoggedInGatPramukh = _normalizeText(
          widget.gatPramukhName,
        );
        final normalizedUserGatPramukh = _normalizeText(user.gatPramukhName);
        final matchesGatPramukhScope =
            !shouldApplyGatPramukhScope ||
            normalizedLoggedInGatPramukh.isEmpty ||
            normalizedUserGatPramukh == normalizedLoggedInGatPramukh;

        return matchesSearch &&
            matchesStatus &&
            matchesGat &&
            matchesGatPramukhScope;
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

  void _setGatFilter(String? gatName) {
    if (gatName == null || _selectedGatName == gatName) {
      return;
    }
    _selectedGatName = gatName;
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
      _showUserDetails(
        detailedUser.copyWith(
          approvalStatus: detailedUser.approvalStatus ?? user.approvalStatus,
          isActive: detailedUser.isActive ?? user.isActive,
        ),
        fallbackUserId: userId,
      );
    } catch (e) {
      if (!mounted) return;

      if (_isSessionExpiredError(e)) {
        await _redirectToLoginWithMessage();
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ApiEndpoints.genericApiFailureMessage)),
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
      final message = await ApiService.updateUserApproval(
        userId: userId,
        decision: 1,
        comment: 'All details verified.',
      );

      if (!mounted) return;

      Navigator.pop(context); // close details popup

      _markUserAsApprovedLocally(userId);

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Success'),
          content: Text(message),
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
      ).showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _rejectUser(int userId) async {
    final commentController = TextEditingController();
    String? errorText;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Reject User'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Rejection comment is required.'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: commentController,
                      autofocus: true,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Enter rejection reason',
                        errorText: errorText,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final comment = commentController.text.trim();
                    if (comment.isEmpty) {
                      setDialogState(() {
                        errorText = 'Rejection comment is required.';
                      });
                      return;
                    }

                    Navigator.pop(dialogContext);
                    setState(() {
                      _isLoading = true;
                    });

                    try {
                      final message = await ApiService.updateUserApproval(
                        userId: userId,
                        decision: 0,
                        comment: comment,
                      );

                      if (!mounted) return;
                      // Close the user-details popup after reject dialog is closed.
                      Navigator.of(this.context).pop();
                      _markUserAsRejectedLocally(userId);
                      setState(() {
                        _isLoading = false;
                      });
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(message)));
                    } catch (e) {
                      if (!mounted) return;

                      if (_isSessionExpiredError(e)) {
                        await _redirectToLoginWithMessage();
                        return;
                      }

                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(e.toString())));
                      setState(() {
                        _isLoading = false;
                      });
                    }
                  },
                  child: const Text('Reject'),
                ),
              ],
            );
          },
        );
      },
    );

    commentController.dispose();
  }

  void _markUserAsApprovedLocally(int userId) {
    _users = _users.map<User>((user) {
      if (user.id != userId) {
        return user;
      }

      return user.copyWith(isActive: true, approvalStatus: 1);
    }).toList();
    _applyFilters();
  }

  void _markUserAsRejectedLocally(int userId) {
    _users = _users.map<User>((user) {
      if (user.id != userId) {
        return user;
      }

      return user.copyWith(isActive: false, approvalStatus: 3);
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
                  _row('Status', _statusLabel(user)),
                  _row('Instrument', user.instrument),
                  _row('Joined Year', user.joiningYear),
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
          if (_statusFilter == 'pending' && _isPending(user))
            TextButton(
              onPressed: effectiveUserId == null
                  ? null
                  : () => _rejectUser(effectiveUserId),
              child: const Text(
                'Reject',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if ((_statusFilter == 'pending' && _isPending(user)) ||
              (_statusFilter == 'rejected' && _isRejected(user)))
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
                if (widget.showStatusFilters)
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
                          label: Text('Rejected ($_rejectedCount)'),
                          selected: _statusFilter == 'rejected',
                          selectedColor: AppColors.accentYellow,
                          onSelected: (_) => _setStatusFilter('rejected'),
                          labelStyle: const TextStyle(
                            color: AppColors.primaryMaroon,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.isPathakAdmin)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
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
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _gatFilterOptions.contains(_selectedGatName)
                              ? _selectedGatName
                              : 'all',
                          isExpanded: true,
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: AppColors.primaryMaroon,
                          ),
                          style: const TextStyle(
                            color: AppColors.primaryMaroon,
                            fontWeight: FontWeight.w500,
                          ),
                          items: _gatFilterOptions
                              .map(
                                (gat) => DropdownMenuItem<String>(
                                  value: gat,
                                  child: Text(gat == 'all' ? 'All Gats' : gat),
                                ),
                              )
                              .toList(),
                          onChanged: _setGatFilter,
                        ),
                      ),
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

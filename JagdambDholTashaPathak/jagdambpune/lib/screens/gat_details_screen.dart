import 'package:flutter/material.dart';

import '../components/notification_dialog.dart';
import '../config/api_endpoints.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

class GatDetailsScreen extends StatefulWidget {
  final int? selectedGatId;
  final String? selectedGatName;
  final bool showAutoAssignAction;
  final bool isPathakAdmin;
  final bool canCreateGat;
  final bool useMyGatEndpoint;

  const GatDetailsScreen({
    super.key,
    this.selectedGatId,
    this.selectedGatName,
    this.showAutoAssignAction = true,
    this.isPathakAdmin = false,
    this.canCreateGat = false,
    this.useMyGatEndpoint = false,
  });

  @override
  State<GatDetailsScreen> createState() => _GatDetailsScreenState();
}

class _GatDetailsScreenState extends State<GatDetailsScreen> {
  List<Map<String, dynamic>> _gats = [];
  bool _isLoading = true;
  bool _isAssigning = false;
  bool _isCreating = false;
  String? _errorMessage;

  String _userDisplayName(User user) {
    final first = user.firstName?.trim() ?? '';
    final last = user.lastName?.trim() ?? '';
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    if ((user.phoneNumber ?? '').trim().isNotEmpty) {
      return user.phoneNumber!.trim();
    }
    return 'User #${user.id ?? '-'}';
  }

  String _gatNameFrom(Map<String, dynamic> gat) {
    final directName = gat['name']?.toString().trim();
    if (directName != null && directName.isNotEmpty) {
      return directName;
    }

    final gatName = gat['gat_name']?.toString().trim();
    if (gatName != null && gatName.isNotEmpty) {
      return gatName;
    }

    final nested = gat['gat'];
    if (nested is Map) {
      final nestedMap = Map<String, dynamic>.from(nested);
      final nestedName = nestedMap['name']?.toString().trim();
      if (nestedName != null && nestedName.isNotEmpty) {
        return nestedName;
      }
      final nestedGatName = nestedMap['gat_name']?.toString().trim();
      if (nestedGatName != null && nestedGatName.isNotEmpty) {
        return nestedGatName;
      }
    }

    return '-';
  }

  @override
  void initState() {
    super.initState();
    _loadGats();
  }

  Map<String, dynamic> _normalizeMyGatRecord(Map<String, dynamic> raw) {
    final normalized = Map<String, dynamic>.from(raw);
    final nested = raw['gat'] is Map
        ? Map<String, dynamic>.from(raw['gat'] as Map)
        : <String, dynamic>{};

    List<Map<String, dynamic>> pickMembers(dynamic source) {
      if (source is! List) return <Map<String, dynamic>>[];
      return source
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    final members = pickMembers(raw['members']).isNotEmpty
        ? pickMembers(raw['members'])
        : pickMembers(raw['users']).isNotEmpty
        ? pickMembers(raw['users'])
        : pickMembers(raw['members_list']).isNotEmpty
        ? pickMembers(raw['members_list'])
        : pickMembers(raw['member_list']).isNotEmpty
        ? pickMembers(raw['member_list'])
        : pickMembers(nested['members']).isNotEmpty
        ? pickMembers(nested['members'])
        : pickMembers(nested['users']).isNotEmpty
        ? pickMembers(nested['users'])
        : pickMembers(nested['members_list']).isNotEmpty
        ? pickMembers(nested['members_list'])
        : pickMembers(nested['member_list']);

    final nestedPramukh = nested['gat_pramukh'];
    final nestedPramukhName = nestedPramukh is Map
        ? (nestedPramukh['name']?.toString() ?? '').trim()
        : '';

    normalized['id'] =
        raw['id'] ?? raw['gat_id'] ?? nested['id'] ?? nested['gat_id'];
    normalized['gat_name'] =
        raw['gat_name'] ?? raw['name'] ?? nested['gat_name'] ?? nested['name'];
    normalized['gat_pramukh_name'] =
        raw['gat_pramukh_name'] ??
        raw['gatPramukhName'] ??
        nested['gat_pramukh_name'] ??
        nested['gatPramukhName'] ??
        (nestedPramukhName.isEmpty ? null : nestedPramukhName);
    normalized['members'] = members;
    normalized['members_count'] =
        raw['members_count'] ?? nested['members_count'] ?? members.length;

    return normalized;
  }

  Future<void> _loadGats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final gats = widget.useMyGatEndpoint
          ? <Map<String, dynamic>>[]
          : await ApiService.fetchGatsWithMembers(
              includeMembers: true,
              membersLimit: 50,
            );

      if (widget.useMyGatEndpoint) {
        final myGatRaw = await ApiService.fetchMyGat(
          includeMembers: true,
          membersLimit: 50,
        );
        final myGat = _normalizeMyGatRecord(myGatRaw);
        final hasAssignment =
            _gatNameFrom(myGat) != '-' ||
            _extractMembers(myGat).isNotEmpty ||
            myGat['id'] != null;

        setState(() {
          _gats = hasAssignment
              ? <Map<String, dynamic>>[myGat]
              : <Map<String, dynamic>>[];
          _errorMessage = hasAssignment ? null : 'Gat is not assigned yet';
          _isLoading = false;
        });
        return;
      }

      final selectedId = widget.selectedGatId;
      final selectedName = widget.selectedGatName?.trim().toLowerCase();

      final filtered = widget.useMyGatEndpoint
          ? gats
          : gats.where((gat) {
              if (selectedId != null &&
                  gat['id']?.toString() == '$selectedId') {
                return true;
              }
              if (selectedName != null && selectedName.isNotEmpty) {
                final gatName = _gatNameFrom(gat).trim().toLowerCase();
                return gatName == selectedName;
              }
              return selectedId == null &&
                  (selectedName == null || selectedName.isEmpty);
            }).toList();

      setState(() {
        _gats = filtered;
        _isLoading = false;
      });
    } catch (e) {
      final message = e
          .toString()
          .replaceFirst('Exception: ', '')
          .toLowerCase();
      setState(() {
        _errorMessage =
            widget.useMyGatEndpoint &&
                (message.contains('not assigned') ||
                    message.contains('no gat') ||
                    message.contains('not found'))
            ? 'Gat is not assigned yet'
            : ApiEndpoints.genericApiFailureMessage;
        _isLoading = false;
      });
    }
  }

  Future<void> _openAutoAssignDialog() async {
    final formKey = GlobalKey<FormState>();
    final yearController = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    final seedController = TextEditingController();
    var reassign = false;
    var dryRun = false;

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Auto Assign Members'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: yearController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Year',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final year = int.tryParse(value?.trim() ?? '');
                          if (year == null) {
                            return 'Enter a valid year';
                          }
                          if (year < 1900 || year > 3000) {
                            return 'Year must be between 1900 and 3000';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: seedController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Seed (optional)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final trimmed = value?.trim() ?? '';
                          if (trimmed.isEmpty) {
                            return null;
                          }
                          if (int.tryParse(trimmed) == null) {
                            return 'Seed must be an integer';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: dryRun,
                        onChanged: (value) {
                          setDialogState(() {
                            dryRun = value ?? false;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Dry run (no DB changes)'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        value: reassign,
                        onChanged: (value) {
                          setDialogState(() {
                            reassign = value ?? false;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Reassign existing members'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.of(dialogContext).pop(true);
                    }
                  },
                  child: const Text('Run'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSubmit != true || !mounted) {
      return;
    }

    final year = int.parse(yearController.text.trim());
    final seedText = seedController.text.trim();
    final seed = seedText.isEmpty ? null : int.parse(seedText);

    setState(() {
      _isAssigning = true;
    });

    try {
      final result = await ApiService.autoAssignMembersToGats(
        year: year,
        reassign: reassign,
        dryRun: dryRun,
        seed: seed,
      );

      if (!mounted) return;

      final message = result['message']?.toString() ?? 'Completed';
      final auditId = result['audit_id'];
      final data = result['data'];

      await showDialog<void>(
        context: context,
        builder: (context) {
          final resultData = data is Map<String, dynamic>
              ? data
              : <String, dynamic>{};
          final gats = resultData['gats'] is List
              ? List<Map<String, dynamic>>.from(resultData['gats'])
              : <Map<String, dynamic>>[];

          return AlertDialog(
            title: const Text('Auto Assign Result'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message),
                    const SizedBox(height: 12),
                    Text('Audit ID: ${auditId ?? '-'}'),
                    Text('Year: ${resultData['year'] ?? '-'}'),
                    Text(
                      'Dry run: ${resultData['dry_run'] == true ? 'Yes' : 'No'}',
                    ),
                    Text(
                      'Reassign: ${resultData['reassign'] == true ? 'Yes' : 'No'}',
                    ),
                    Text(
                      'Candidates: ${resultData['total_candidates'] ?? 0} | Assigned: ${resultData['total_assigned'] ?? 0}',
                    ),
                    Text('Skipped: ${resultData['total_skipped'] ?? 0}'),
                    const SizedBox(height: 12),
                    const Text(
                      'Gat Summary',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (gats.isEmpty)
                      const Text('No gat data returned')
                    else
                      ...gats.map((gat) {
                        final rawMembers = gat['members'];
                        final members = rawMembers is List
                            ? rawMembers
                                  .whereType<Map>()
                                  .map((e) => Map<String, dynamic>.from(e))
                                  .toList()
                            : <Map<String, dynamic>>[];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${gat['gat_name'] ?? '-'}: +${gat['added_count'] ?? 0} (final ${gat['final_count'] ?? 0})',
                              ),
                              const SizedBox(height: 4),
                              if (members.isEmpty)
                                const Text(
                                  'No member names returned',
                                  style: TextStyle(color: Colors.black54),
                                )
                              else
                                ...members.map((member) {
                                  final name = member['name']
                                      ?.toString()
                                      .trim();
                                  return Text(
                                    '- ${name != null && name.isNotEmpty ? name : 'Unnamed member'}',
                                  );
                                }),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );

      if (!dryRun) {
        await _loadGats();
      }
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAssigning = false;
        });
      }
    }
  }

  Future<void> _openCreateGatDialog() async {
    if (!widget.canCreateGat) return;

    List<User> pathakUsers = <User>[];
    try {
      pathakUsers = await ApiService.fetchAllUsers();
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    User? selectedGatPramukh;
    var userSearchQuery = '';

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredUsers = pathakUsers.where((user) {
              final q = userSearchQuery.trim().toLowerCase();
              if (q.isEmpty) return true;
              final name = _userDisplayName(user).toLowerCase();
              final phone = (user.phoneNumber ?? '').toLowerCase();
              return name.contains(q) || phone.contains(q);
            }).toList();

            return AlertDialog(
              title: const Text('Create Gat'),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Gat Name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Gat name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Select Gat Pramukh',
                          style: TextStyle(
                            color: AppColors.primaryMaroon,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          onChanged: (value) {
                            setDialogState(() {
                              userSearchQuery = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search by name',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppColors.primaryMaroon.withValues(
                                alpha: 0.2,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: filteredUsers.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text('No users found'),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: filteredUsers.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (_, index) {
                                    final user = filteredUsers[index];
                                    final isSelected =
                                        selectedGatPramukh?.id == user.id;
                                    return ListTile(
                                      dense: true,
                                      selected: isSelected,
                                      title: Text(_userDisplayName(user)),
                                      subtitle: Text(
                                        'ID: ${user.id ?? '-'}${(user.phoneNumber ?? '').isNotEmpty ? ' • ${user.phoneNumber}' : ''}',
                                      ),
                                      trailing: isSelected
                                          ? const Icon(
                                              Icons.check_circle,
                                              color: Colors.green,
                                            )
                                          : null,
                                      onTap: () {
                                        setDialogState(() {
                                          selectedGatPramukh = user;
                                        });
                                      },
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (selectedGatPramukh != null)
                              Chip(
                                label: Text(
                                  'Selected: ${_userDisplayName(selectedGatPramukh!)}',
                                ),
                                deleteIcon: const Icon(Icons.close),
                                onDeleted: () {
                                  setDialogState(() {
                                    selectedGatPramukh = null;
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Showing users available to your pathak scope.',
                          style: TextStyle(
                            color: AppColors.primaryMaroon.withValues(
                              alpha: 0.75,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      if (selectedGatPramukh == null) {
                        showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Error'),
                            content: const Text(
                              'Gat Pramukh is required for creating gat.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                        return;
                      }
                      Navigator.of(dialogContext).pop(true);
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSubmit != true || !mounted) {
      return;
    }

    final gatName = nameController.text.trim();
    final gatPramukhId = selectedGatPramukh?.id;

    setState(() {
      _isCreating = true;
    });

    try {
      final result = await ApiService.createGat(
        name: gatName,
        gatPramukhId: gatPramukhId,
      );

      if (!mounted) return;

      final message =
          result['message']?.toString() ?? 'Gat created successfully.';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Success'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      await _loadGats();
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  Future<void> _openGatMembersPopup(Map<String, dynamic> gat) async {
    final members = _extractMembers(gat);
    final membersCount =
        (gat['members_count'] as num?)?.toInt() ?? members.length;
    final gatName = _gatNameFrom(gat) == '-' ? 'Gat' : _gatNameFrom(gat);
    final gatId = int.tryParse((gat['id'] ?? gat['gat_id'] ?? '').toString());

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          actionsPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          title: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.primaryMaroon,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gatName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total Members: $membersCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          content: SizedBox(
            width: 460,
            child: members.isEmpty
                ? const Text('No members available')
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: members.length,
                      separatorBuilder: (_, __) => const Divider(height: 10),
                      itemBuilder: (_, index) {
                        final member = members[index];
                        final name =
                            member['name']?.toString() ??
                            member['full_name']?.toString() ??
                            [
                              member['first_name']?.toString() ?? '',
                              member['last_name']?.toString() ?? '',
                            ].join(' ').trim();
                        final phone = member['phone_number']?.toString() ?? '';

                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(name.isEmpty ? '-' : name),
                          subtitle: phone.isEmpty ? null : Text(phone),
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            if (widget.isPathakAdmin && gatId != null)
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await NotificationForm.open(
                    context,
                    targetGatId: gatId,
                    targetGatName: gatName,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentYellow,
                  foregroundColor: AppColors.primaryMaroon,
                ),
                icon: const Icon(Icons.campaign, size: 16),
                label: const Text('Send Notification'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Gat Details'),
        backgroundColor: AppColors.primaryMaroon,
        foregroundColor: AppColors.textLight,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadGats,
            icon: _isLoading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          if (widget.canCreateGat)
            IconButton(
              tooltip: 'Create Gat',
              onPressed: _isCreating ? null : _openCreateGatDialog,
              icon: _isCreating
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_circle_outline),
            ),
          if (widget.showAutoAssignAction)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _isAssigning ? null : _openAutoAssignDialog,
                icon: _isAssigning
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_isAssigning ? 'Running...' : 'Auto Assign'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentYellow,
                  foregroundColor: AppColors.primaryMaroon,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accentYellow),
            )
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.primaryMaroon),
                    ),
                    if (widget.canCreateGat || widget.showAutoAssignAction) ...[
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadGats,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentYellow,
                          foregroundColor: AppColors.primaryMaroon,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : _gats.isEmpty
          ? const Center(
              child: Text(
                'No gats found',
                style: TextStyle(color: AppColors.primaryMaroon, fontSize: 16),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadGats,
              color: AppColors.accentYellow,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _gats.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final gat = _gats[index];
                  final members = _extractMembers(gat);
                  final membersCount =
                      (gat['members_count'] as num?)?.toInt() ?? members.length;
                  return Card(
                    color: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      onTap: () => _openGatMembersPopup(gat),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primaryMaroon,
                        child: Text(
                          '${gat['id'] ?? index + 1}',
                          style: const TextStyle(
                            color: AppColors.accentYellow,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        _gatNameFrom(gat),
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gat Pramukh: ${gat['gat_pramukh_name'] ?? '-'}',
                            style: const TextStyle(
                              color: AppColors.primaryMaroon,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Members ($membersCount)',
                            style: const TextStyle(
                              color: AppColors.primaryMaroon,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            members.isEmpty
                                ? 'Tap to view details'
                                : 'Tap to view all members',
                            style: const TextStyle(
                              color: AppColors.primaryMaroon,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  List<Map<String, dynamic>> _extractMembers(Map<String, dynamic> gat) {
    final candidates = [
      gat['members'],
      gat['users'],
      gat['members_list'],
      gat['member_list'],
    ];

    for (final candidate in candidates) {
      if (candidate is List) {
        return candidate
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return <Map<String, dynamic>>[];
  }
}

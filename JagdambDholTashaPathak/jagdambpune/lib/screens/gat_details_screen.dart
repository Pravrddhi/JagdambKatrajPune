import 'package:flutter/material.dart';

import '../components/notification_dialog.dart';
import '../config/api_endpoints.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

class GatDetailsScreen extends StatefulWidget {
  final int? selectedGatId;
  final String? selectedGatName;
  final bool showAutoAssignAction;
  final bool useMyGatEndpoint;

  const GatDetailsScreen({
    super.key,
    this.selectedGatId,
    this.selectedGatName,
    this.showAutoAssignAction = true,
    this.useMyGatEndpoint = false,
  });

  @override
  State<GatDetailsScreen> createState() => _GatDetailsScreenState();
}

class _GatDetailsScreenState extends State<GatDetailsScreen> {
  List<Map<String, dynamic>> _gats = [];
  bool _isLoading = true;
  bool _isAssigning = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadGats();
  }

  Future<void> _loadGats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final gats = widget.useMyGatEndpoint
          ? <Map<String, dynamic>>[
              await ApiService.fetchMyGat(
                includeMembers: true,
                membersLimit: 50,
              ),
            ]
          : await ApiService.fetchGatsWithMembers(
              includeMembers: true,
              membersLimit: 50,
            );
      final selectedId = widget.selectedGatId;
      final selectedName = widget.selectedGatName?.trim().toLowerCase();

      final filtered = gats.where((gat) {
        if (selectedId != null && gat['id']?.toString() == '$selectedId') {
          return true;
        }
        if (selectedName != null && selectedName.isNotEmpty) {
          final gatName = gat['name']?.toString().trim().toLowerCase() ?? '';
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
      setState(() {
        _errorMessage = ApiEndpoints.genericApiFailureMessage;
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
    var dryRun = true;

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
                    const SizedBox(height: 12),
                    const Text(
                      'Gat Summary',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (gats.isEmpty)
                      const Text('No gat data returned')
                    else
                      ...gats.map(
                        (gat) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${gat['gat_name'] ?? '-'}: +${gat['added_count'] ?? 0} (final ${gat['final_count'] ?? 0})',
                          ),
                        ),
                      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAssigning = false;
        });
      }
    }
  }

  Future<void> _openGatMembersPopup(Map<String, dynamic> gat) async {
    final members = _extractMembers(gat);
    final membersCount =
        (gat['members_count'] as num?)?.toInt() ?? members.length;
    final gatName =
        gat['name']?.toString() ?? gat['gat_name']?.toString() ?? 'Gat';
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
            if (widget.showAutoAssignAction && gatId != null)
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
                        gat['name'] ?? '-',
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

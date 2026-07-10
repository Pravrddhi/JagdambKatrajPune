import 'dart:ui';

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
  bool _isApplyingChanges = false;
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
    final nestedSecondaryPramukh = nested['gat_pramukh_secondary'];
    final nestedSecondaryPramukhName = nestedSecondaryPramukh is Map
        ? (nestedSecondaryPramukh['name']?.toString() ?? '').trim()
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
    normalized['gat_pramukh_secondary_id'] =
        raw['gat_pramukh_secondary_id'] ??
        raw['gatPramukhSecondaryId'] ??
        nested['gat_pramukh_secondary_id'] ??
        nested['gatPramukhSecondaryId'] ??
        (nestedSecondaryPramukh is Map ? nestedSecondaryPramukh['id'] : null);
    normalized['gat_pramukh_secondary_name'] =
        raw['gat_pramukh_secondary_name'] ??
        raw['gatPramukhSecondaryName'] ??
        nested['gat_pramukh_secondary_name'] ??
        nested['gatPramukhSecondaryName'] ??
        (nestedSecondaryPramukhName.isEmpty
            ? null
            : nestedSecondaryPramukhName);
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
    final seedController = TextEditingController();
    final currentYear = DateTime.now().year;
    final availableYears = <int>[
      0,
      ...List<int>.generate(10, (index) => currentYear - index),
      ...List<int>.generate(10, (index) => currentYear + index + 1),
    ];
    var selectedYear = currentYear;
    var reassign = false;

    final action = await showDialog<String>(
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
                      DropdownButtonFormField<int>(
                        initialValue: selectedYear,
                        decoration: const InputDecoration(
                          labelText: 'Year',
                          border: OutlineInputBorder(),
                        ),
                        items: availableYears
                            .map(
                              (year) => DropdownMenuItem<int>(
                                value: year,
                                child: Text(
                                  year == 0 ? 'All' : year.toString(),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              selectedYear = value;
                            });
                          }
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'Select a year';
                          }
                          if (value != 0 && (value < 1900 || value > 3000)) {
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
                  onPressed: () => Navigator.of(dialogContext).pop('cancel'),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.of(dialogContext).pop('preview');
                    }
                  },
                  child: const Text('Preview Assignments'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.of(dialogContext).pop('apply');
                    }
                  },
                  child: const Text('Apply Changes'),
                ),
              ],
            );
          },
        );
      },
    );

    if (action == null || action == 'cancel' || !mounted) {
      return;
    }

    final year = selectedYear;
    final seedText = seedController.text.trim();
    final seed = seedText.isEmpty ? null : int.parse(seedText);
    final dryRun = action == 'preview';

    setState(() {
      _isAssigning = true;
      _isApplyingChanges = !dryRun;
    });

    try {
      final result = await ApiService.autoAssignMembersToGats(
        year: year,
        assignmentMode: 'balanced',
        reassign: reassign,
        dryRun: dryRun,
        seed: seed,
      );

      if (!mounted) return;

      final message = result['message']?.toString() ?? 'Completed';
      final auditId = result['audit_id'];
      final data = result['data'];

      final applyRequested = await showDialog<bool>(
        context: context,
        builder: (context) {
          final resultData = data is Map<String, dynamic>
              ? data
              : <String, dynamic>{};
          final skippedReasonsRaw = resultData['skipped_reasons'];
          final gats = resultData['gats'] is List
              ? List<Map<String, dynamic>>.from(resultData['gats'])
              : <Map<String, dynamic>>[];

          List<Widget> buildSkippedReasonWidgets() {
            if (skippedReasonsRaw is Map) {
              final entries = skippedReasonsRaw.entries
                  .map((entry) => MapEntry(entry.key.toString(), entry.value))
                  .toList();
              if (entries.isEmpty) {
                return const <Widget>[Text('No skipped reasons reported')];
              }
              return entries.map((entry) {
                final value = entry.value;
                final displayValue = value is List
                    ? value.map((item) => item.toString()).join(', ')
                    : value.toString();
                final label = entry.key
                    .split('_')
                    .where((part) => part.isNotEmpty)
                    .map(
                      (part) =>
                          '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
                    )
                    .join(' ');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('$label: $displayValue'),
                );
              }).toList();
            }

            if (skippedReasonsRaw is List && skippedReasonsRaw.isNotEmpty) {
              return skippedReasonsRaw
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(item.toString()),
                    ),
                  )
                  .toList();
            }

            return const <Widget>[Text('No skipped reasons reported')];
          }

          Widget buildSummaryCard(String label, Object? value) {
            return Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryMaroon,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${value ?? 0}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryMaroon,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return AlertDialog(
            title: const Text('Auto Assign Result'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message),
                    const SizedBox(height: 12),
                    Text('Audit ID: ${auditId ?? '-'}'),
                    Text('Year: ${resultData['year'] ?? '-'}'),
                    Text(
                      'Assignment mode: ${resultData['assignment_mode'] ?? 'balanced'}',
                    ),
                    Text(
                      'Dry run: ${resultData['dry_run'] == true ? 'Yes' : 'No'}',
                    ),
                    Text(
                      'Reassign: ${resultData['reassign'] == true ? 'Yes' : 'No'}',
                    ),
                    Text('Seed: ${resultData['seed'] ?? '-'}'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        buildSummaryCard(
                          'Total Candidates',
                          resultData['total_candidates'],
                        ),
                        const SizedBox(width: 8),
                        buildSummaryCard(
                          'Total Assigned',
                          resultData['total_assigned'],
                        ),
                        const SizedBox(width: 8),
                        buildSummaryCard(
                          'Total Skipped',
                          resultData['total_skipped'],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Skipped Reasons',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ...buildSkippedReasonWidgets(),
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
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ExpansionTile(
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              title: Text(gat['gat_name']?.toString() ?? '-'),
                              subtitle: Text(
                                'Added: ${gat['added_count'] ?? 0}   Final: ${gat['final_count'] ?? 0}',
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                12,
                                0,
                                12,
                                12,
                              ),
                              children: [
                                if (members.isEmpty)
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'No member preview returned',
                                      style: TextStyle(color: Colors.black54),
                                    ),
                                  )
                                else
                                  ...members.map((member) {
                                    final name = member['name']
                                        ?.toString()
                                        .trim();
                                    final email = member['email']
                                        ?.toString()
                                        .trim();
                                    final text = name != null && name.isNotEmpty
                                        ? name
                                        : 'Unnamed member';
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        email != null && email.isNotEmpty
                                            ? '$text ($email)'
                                            : text,
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            actions: [
              if (dryRun)
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Apply Changes'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );

      if (dryRun && applyRequested == true) {
        if (mounted) {
          setState(() {
            _isApplyingChanges = true;
          });
        }

        final applyResult = await ApiService.autoAssignMembersToGats(
          year: year,
          assignmentMode: 'balanced',
          reassign: reassign,
          dryRun: false,
          seed: seed,
        );

        if (!mounted) return;

        final applyMessage =
            applyResult['message']?.toString() ??
            'Members assigned successfully.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(applyMessage),
            backgroundColor: Colors.green.shade700,
          ),
        );
        await _loadGats();
        return;
      }

      if (!dryRun) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green.shade700,
          ),
        );
        await _loadGats();
      }
    } on ApiValidationException catch (e) {
      if (!mounted) return;
      final errorText = e.errors.entries
          .expand((entry) => entry.value.map((value) => '${entry.key}: $value'))
          .join('\n');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text(errorText.isNotEmpty ? errorText : e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
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
          _isApplyingChanges = false;
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
    final pathakScopedUsers = pathakUsers
        .where((user) => user.id != null)
        .toList();
    int? selectedPrimaryId;
    int? selectedSecondaryId;
    bool isSubmitting = false;
    String? formMessage;
    bool isSuccess = false;
    final fieldErrors = <String, String?>{};

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submitForm() async {
              FocusScope.of(dialogContext).unfocus();
              fieldErrors.clear();
              formMessage = null;

              if (!(formKey.currentState?.validate() ?? false)) {
                setDialogState(() {});
                return;
              }

              if (selectedPrimaryId == null) {
                fieldErrors['gat_pramukh_id'] =
                    'Primary GAT pramukh is required';
                setDialogState(() {});
                return;
              }

              if (selectedSecondaryId != null &&
                  selectedSecondaryId == selectedPrimaryId) {
                fieldErrors['gat_pramukh_secondary_id'] =
                    'Secondary GAT pramukh must be different from primary';
                setDialogState(() {});
                return;
              }

              setDialogState(() {
                isSubmitting = true;
                isSuccess = false;
              });

              try {
                final result = await ApiService.createGat(
                  name: nameController.text.trim(),
                  gatPramukhId: selectedPrimaryId,
                  gatPramukhSecondaryId: selectedSecondaryId,
                );

                if (!mounted) return;

                final successMessage =
                    result['message']?.toString() ?? 'Gat created successfully';

                setDialogState(() {
                  isSuccess = true;
                  formMessage = successMessage;
                });

                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();

                if (!mounted) return;

                await showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Success'),
                    content: Text(successMessage),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
                await _loadGats();
              } on ApiValidationException catch (e) {
                if (!mounted) return;
                setDialogState(() {
                  formMessage = e.message;
                  for (final entry in e.errors.entries) {
                    if (entry.value.isNotEmpty) {
                      fieldErrors[entry.key] = entry.value.first;
                    }
                  }
                });
              } catch (e) {
                if (!mounted) return;
                setDialogState(() {
                  formMessage = e.toString().replaceFirst('Exception: ', '');
                });
              } finally {
                if (mounted) {
                  setDialogState(() {
                    isSubmitting = false;
                  });
                }
              }
            }

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
                        if (isSubmitting)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: LinearProgressIndicator(),
                          ),
                        if (formMessage != null &&
                            formMessage!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              formMessage!,
                              style: TextStyle(
                                color: isSuccess ? Colors.green : Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        TextFormField(
                          controller: nameController,
                          decoration: InputDecoration(
                            labelText: 'Gat Name',
                            border: const OutlineInputBorder(),
                            errorText: fieldErrors['name'],
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Gat name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: selectedPrimaryId,
                          decoration: InputDecoration(
                            labelText: 'Primary GAT Pramukh',
                            border: const OutlineInputBorder(),
                            errorText: fieldErrors['gat_pramukh_id'],
                          ),
                          items: pathakScopedUsers
                              .map(
                                (user) => DropdownMenuItem<int>(
                                  value: user.id,
                                  child: Text(
                                    '${_userDisplayName(user)}${(user.phoneNumber ?? '').isNotEmpty ? ' • ${user.phoneNumber}' : ''}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: isSubmitting
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    selectedPrimaryId = value;
                                    fieldErrors.remove('gat_pramukh_id');
                                    if (selectedSecondaryId == value) {
                                      selectedSecondaryId = null;
                                    }
                                  });
                                },
                          validator: (value) {
                            if (value == null) {
                              return 'Primary GAT pramukh is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: selectedSecondaryId,
                          decoration: InputDecoration(
                            labelText: 'Secondary GAT Pramukh (Optional)',
                            border: const OutlineInputBorder(),
                            errorText: fieldErrors['gat_pramukh_secondary_id'],
                          ),
                          items: <DropdownMenuItem<int>>[
                            const DropdownMenuItem<int>(
                              value: null,
                              child: Text('None'),
                            ),
                            ...pathakScopedUsers
                                .where((user) => user.id != selectedPrimaryId)
                                .map(
                                  (user) => DropdownMenuItem<int>(
                                    value: user.id,
                                    child: Text(
                                      '${_userDisplayName(user)}${(user.phoneNumber ?? '').isNotEmpty ? ' • ${user.phoneNumber}' : ''}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                          ],
                          onChanged: isSubmitting
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    selectedSecondaryId = value;
                                    fieldErrors.remove(
                                      'gat_pramukh_secondary_id',
                                    );
                                  });
                                },
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Both pramukh users must belong to your pathak.',
                          style: TextStyle(
                            color: AppColors.primaryMaroon,
                            fontWeight: FontWeight.w600,
                          ),
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
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : submitForm,
                  child: Text(isSubmitting ? 'Creating...' : 'Create'),
                ),
              ],
            );
          },
        );
      },
    );
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
    final body = _isLoading
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
                final primaryPramukhName =
                    gat['gat_pramukh_name']?.toString().trim() ?? '';
                final secondaryPramukhName =
                    gat['gat_pramukh_secondary_name']?.toString().trim() ?? '';
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
                          'Gat Pramukh: ${primaryPramukhName.isEmpty ? '-' : primaryPramukhName}',
                          style: const TextStyle(
                            color: AppColors.primaryMaroon,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Gat Pramukh: ${secondaryPramukhName.isEmpty ? '-' : secondaryPramukhName}',
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
          );

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
              onPressed: _openCreateGatDialog,
              icon: const Icon(Icons.add_circle_outline),
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
      body: Stack(
        children: [
          body,
          if (_isApplyingChanges)
            Positioned.fill(
              child: AbsorbPointer(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.18),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: AppColors.primaryMaroon,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Applying changes...',
                            style: TextStyle(
                              color: AppColors.primaryMaroon,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
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

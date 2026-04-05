import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_endpoints.dart';
import '../theme/app_colors.dart'; // adjust path as per your project
import '../components/link_launcher.dart';
import '../services/authorized_api_service.dart';

class UpcomingEvents extends StatefulWidget {
  final List<Map<String, dynamic>> events;
  final bool isPathakAdmin;
  final Future<void> Function()? onRefresh;

  const UpcomingEvents({
    super.key,
    required this.events,
    this.isPathakAdmin = false,
    this.onRefresh,
  });

  @override
  State<UpcomingEvents> createState() => _UpcomingEventsState();
}

class _UpcomingEventsState extends State<UpcomingEvents>
    with SingleTickerProviderStateMixin {
  late List<Map<String, dynamic>> _events;
  final Map<int, bool> _loading = {};
  bool _isRefreshing = false;
  // null = All, 0 = Not Started, 1 = Started, 3 = Canceled, 4 = Completed
  int? _activeFilter;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _events = List<Map<String, dynamic>>.from(widget.events);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(UpcomingEvents oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.events != oldWidget.events) {
      setState(() {
        _events = List<Map<String, dynamic>>.from(widget.events);
      });
    }
  }

  List<Map<String, dynamic>> get _filteredEvents {
    if (_activeFilter == null) return _events;
    return _events.where((e) {
      final s = e['status'] is int
          ? e['status'] as int
          : int.tryParse(e['status']?.toString() ?? '') ?? 0;
      return s == _activeFilter;
    }).toList();
  }

  Widget _buildFilterChips() {
    const filters = [
      (label: 'All', value: null),
      (label: 'Not Started', value: 0),
      (label: 'Started', value: 1),
      (label: 'Completed', value: 4),
      (label: 'Canceled', value: 3),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: filters.map((f) {
        final selected = _activeFilter == f.value;
        return FilterChip(
          label: Text(f.label, textAlign: TextAlign.center),
          selected: selected,
          onSelected: (_) => setState(() => _activeFilter = f.value),
          selectedColor: AppColors.primaryMaroon,
          checkmarkColor: Colors.white,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.primaryMaroon,
            fontWeight: FontWeight.w600,
            fontSize: 11,
            height: 1.2,
          ),
          side: const BorderSide(color: AppColors.primaryMaroon),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      }).toList(),
    );
  }

  static ({String label, Color bg, Color fg}) _statusConfig(int? status) {
    switch (status) {
      case 1:
        return (label: 'Started', bg: Colors.green.shade600, fg: Colors.white);
      case 3:
        return (label: 'Canceled', bg: Colors.red.shade600, fg: Colors.white);
      case 4:
        return (label: 'Completed', bg: Colors.grey.shade500, fg: Colors.white);
      default: // 0 or null
        return (
          label: 'Not Started',
          bg: Colors.orange.shade600,
          fg: Colors.white,
        );
    }
  }

  Widget _statusChip(int? status) {
    final cfg = _statusConfig(status);
    final isLive = status == 1;

    final label = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: cfg.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Opacity(
                opacity: _pulseAnim.value,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            cfg.label,
            style: TextStyle(
              color: cfg.fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );

    if (!isLive) return label;

    // Outer pulsing ring for Started
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, child) => Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Transform.scale(
              scale: 1.0 + (_pulseAnim.value - 0.4) * 0.15,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.green.shade400.withOpacity(
                    (1.0 - _pulseAnim.value) * 0.5,
                  ),
                ),
              ),
            ),
          ),
          child!,
        ],
      ),
      child: label,
    );
  }

  Future<void> _handleRefresh() async {
    final onRefresh = widget.onRefresh;
    if (onRefresh == null || _isRefreshing) {
      return;
    }

    setState(() => _isRefreshing = true);
    try {
      await onRefresh();
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _refreshAfterStatusUpdate() async {
    final onRefresh = widget.onRefresh;
    if (onRefresh == null || _isRefreshing) {
      return;
    }

    setState(() => _isRefreshing = true);
    try {
      await onRefresh();
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _updateStatus(int index, int newStatus) async {
    final event = _events[index];
    final mirvnukId = event['id'];
    if (mirvnukId == null) return;

    setState(() => _loading[index] = true);

    try {
      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) => http.post(
          Uri.parse(ApiEndpoints.updateMirvnukStatus),
          headers: ApiEndpoints.authorizedHeaders(token),
          body: jsonEncode({'mirvnuk_id': mirvnukId, 'status': newStatus}),
        ),
      );

      if (response == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session expired. Please log in again.'),
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = response.body.isNotEmpty
            ? jsonDecode(response.body) as Map<String, dynamic>
            : <String, dynamic>{};
        if (data['status'] == true) {
          setState(() {
            _events[index] = Map<String, dynamic>.from(_events[index])
              ..['status'] = newStatus;
          });
          await _refreshAfterStatusUpdate();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Failed to update status.'),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error ${response.statusCode}: Could not update status.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading.remove(index));
    }
  }

  /// Builds the bottom action row for the card.
  /// Always shows "View on Map" (if available).
  /// Shows Start/Completed + Cancel only for pathak_admin when status is 0 or 1.
  Widget _cardFooter(int index) {
    final event = _events[index];
    final raw = event['status'];
    final status = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
    final isLoading = _loading[index] == true;
    final hasMap = event['map_link'] != null;
    final showAdminButtons =
        widget.isPathakAdmin && (status == 0 || status == 1);

    if (!hasMap && !showAdminButtons) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          // View on Map
          if (hasMap)
            Expanded(
              child: OutlinedButton(
                onPressed: () => LinkLauncher.openLink(event['map_link']),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryMaroon,
                  side: const BorderSide(color: AppColors.primaryMaroon),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                child: const Text('View on Map'),
              ),
            ),
          if (hasMap && showAdminButtons) const SizedBox(width: 8),
          // Start / Completed button
          if (showAdminButtons)
            Expanded(
              child: OutlinedButton(
                onPressed: isLoading
                    ? null
                    : () => _updateStatus(index, status == 0 ? 1 : 4),
                style: OutlinedButton.styleFrom(
                  foregroundColor: status == 0
                      ? Colors.green.shade700
                      : Colors.grey.shade700,
                  side: BorderSide(
                    color: status == 0
                        ? Colors.green.shade700
                        : Colors.grey.shade700,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                child: isLoading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: status == 0
                              ? Colors.green.shade700
                              : Colors.grey.shade700,
                        ),
                      )
                    : Text(status == 0 ? 'Start' : 'Completed'),
              ),
            ),
          if (showAdminButtons) const SizedBox(width: 8),
          // Cancel button
          if (showAdminButtons)
            Expanded(
              child: OutlinedButton(
                onPressed: isLoading ? null : () => _updateStatus(index, 3),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade700),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
        ],
      ),
    );
  }

  void _showEventPopup(BuildContext context, Map<String, dynamic> event) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final mediaQuery = MediaQuery.of(context);
        final screenHeight = mediaQuery.size.height;
        final bottomInset = mediaQuery.viewInsets.bottom;
        const verticalInset = 10.0;
        final availableHeight =
            (screenHeight - bottomInset - (verticalInset * 2)).clamp(
              220.0,
              screenHeight,
            );

        return AlertDialog(
          insetPadding: const EdgeInsets.all(10),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  event['name'] ?? '',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryMaroon,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusChip(
                event['status'] is int
                    ? event['status'] as int
                    : int.tryParse(event['status']?.toString() ?? ''),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: availableHeight),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (event['date'] != null)
                    Text(
                      'Date: ${event['date']}',
                      style: const TextStyle(
                        color: AppColors.primaryMaroon,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (event['time_from'] != null && event['time_to'] != null)
                    Text(
                      'Time: ${event['time_from']} → ${event['time_to']}',
                      style: const TextStyle(
                        color: AppColors.primaryMaroon,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (event['location'] != null)
                    Text(
                      'Location: ${event['location']}',
                      style: const TextStyle(
                        color: AppColors.primaryMaroon,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (event['duration'] != null)
                    Text(
                      'Duration: ${event['duration']}',
                      style: const TextStyle(
                        color: AppColors.primaryMaroon,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (event['description'] != null &&
                      event['description']!.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Description:',
                          style: TextStyle(
                            color: AppColors.primaryMaroon,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          event['description']!,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
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
  }

  @override
  Widget build(BuildContext context) {
    if (_events.isEmpty) {
      return const SizedBox.shrink();
    }

    final filtered = _filteredEvents;
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Upcoming Mirvnuk',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.primaryMaroon,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh events',
              onPressed: _isRefreshing ? null : _handleRefresh,
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, color: AppColors.primaryMaroon),
            ),
          ],
        ),
        _buildFilterChips(),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'No events for this filter.',
                style: TextStyle(
                  color: AppColors.primaryMaroon.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
            ),
          )
        else
          Column(
            children: filtered.asMap().entries.map((entry) {
              // Map filtered index back to _events index for _cardFooter/_updateStatus
              final filteredEvent = entry.value;
              final index = _events.indexOf(filteredEvent);
              final status = filteredEvent['status'] is int
                  ? filteredEvent['status'] as int
                  : int.tryParse(filteredEvent['status']?.toString() ?? '');

              return Center(
                child: SizedBox(
                  width: screenWidth * 0.95,
                  child: InkWell(
                    onTap: () => _showEventPopup(context, filteredEvent),
                    child: Card(
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title and status chip
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    filteredEvent['name'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryMaroon,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _statusChip(status),
                              ],
                            ),
                            const SizedBox(height: 5),
                            if (filteredEvent['duration'] != null)
                              Text(
                                'Duration: ${filteredEvent['duration']}',
                                style: const TextStyle(
                                  color: AppColors.primaryMaroon,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            const SizedBox(height: 8),
                            if (filteredEvent['date'] != null)
                              Text(
                                'Date: ${filteredEvent['date']}',
                                style: const TextStyle(
                                  color: AppColors.primaryMaroon,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            // Card footer: View on Map + Start/Completed + Cancel
                            _cardFooter(index),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

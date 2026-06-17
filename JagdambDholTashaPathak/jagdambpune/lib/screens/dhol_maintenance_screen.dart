import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/maintenance_models.dart';
import '../components/maintenance_completion_dialog.dart';
import '../services/api_service.dart';
import '../services/attendance_service.dart';
import '../services/maintenance_service.dart';
import '../theme/app_colors.dart';

class _EventUsageItemSummary {
  final String name;
  final int quantityUsed;

  const _EventUsageItemSummary({
    required this.name,
    required this.quantityUsed,
  });
}

class _EventUsageCategorySummary {
  final String categoryKey;
  final String categoryLabel;
  final int totalQuantityUsed;
  final List<_EventUsageItemSummary> items;

  const _EventUsageCategorySummary({
    required this.categoryKey,
    required this.categoryLabel,
    required this.totalQuantityUsed,
    required this.items,
  });
}

class DholMaintenanceScreen extends StatefulWidget {
  final String? initialAdminSection;
  final String? embeddedAdminSection;
  final bool canManageInventory;
  final bool canApproveEntries;
  final bool canCreateMaintenanceEvents;
  final bool canApproveCompletionRequests;
  final bool isPathakAdminApprover;
  final int? approverGatId;
  final int? currentUserId;
  final String? currentUserName;
  final int? openCompletionForEventIdOnStart;
  final int? openInstrumentMaintenanceIdOnStart;
  final bool openSubmitForInstrumentMaintenanceOnStart;
  final String? userInstrument;
  final bool openCreateMaintenanceDayOnStart;
  final bool openStartInstrumentMaintenanceOnStart;

  const DholMaintenanceScreen({
    super.key,
    this.initialAdminSection,
    this.embeddedAdminSection,
    required this.canManageInventory,
    required this.canApproveEntries,
    required this.canCreateMaintenanceEvents,
    required this.canApproveCompletionRequests,
    this.isPathakAdminApprover = false,
    this.approverGatId,
    this.currentUserId,
    this.currentUserName,
    this.openCompletionForEventIdOnStart,
    this.openInstrumentMaintenanceIdOnStart,
    this.openSubmitForInstrumentMaintenanceOnStart = false,
    this.userInstrument,
    this.openCreateMaintenanceDayOnStart = false,
    this.openStartInstrumentMaintenanceOnStart = false,
  });

  @override
  State<DholMaintenanceScreen> createState() => _DholMaintenanceScreenState();
}

class _DholMaintenanceScreenState extends State<DholMaintenanceScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool _isLoadingInventory = false;
  bool _isLoadingRequests = false;
  bool _isLoadingEntries = false;
  bool _isLoadingAnalysis = false;
  bool _isLoadingEvents = false;
  bool _isLoadingCompletionRequests = false;
  bool _isLoadingPathakDhols = false;
  bool _isLoadingMaintenancePartners = false;
  bool _isLoadingActiveInstrumentMaintenances = false;
  bool _isCreatingDholRange = false;
  int _activeApiCallCount = 0;

  bool get _isAnyApiCallInProgress {
    return _activeApiCallCount > 0 ||
        _isLoadingInventory ||
        _isLoadingRequests ||
        _isLoadingEntries ||
        _isLoadingAnalysis ||
        _isLoadingEvents ||
        _isLoadingCompletionRequests ||
        _isLoadingPathakDhols ||
        _isLoadingMaintenancePartners ||
        _isLoadingActiveInstrumentMaintenances;
  }

  String _requestStatusFilter = 'pending';
  String _entryStatusFilter = 'pending';
  String _completionStatusFilter = 'pending';
  String _eventStatusFilter = 'all';
  String _eventScopeFilter = 'all';
  String _eventDateFilter = '';
  String _dholStatusFilter = 'all';
  int? _analysisEventIdFilter;
  int? _completionEventIdFilter;
  String _completionEventDateFilter = '';
  final Map<String, String> _categorySearch = <String, String>{};
  bool _hasAppliedAdminDefaultTab = false;
  bool _showLegacyEntriesTab = true;
  Timer? _liveRefreshTimer;
  bool _isLiveRefreshInProgress = false;
  bool _hasOpenedCreateMaintenanceDayOnStart = false;
  bool _hasOpenedCompletionOnStart = false;
  bool _hasOpenedInstrumentMaintenanceOnStart = false;
  int? _lastSubmittedCompletionRequestId;

  List<InventoryItem> _inventory = <InventoryItem>[];
  List<InventoryRequestItem> _requests = <InventoryRequestItem>[];
  List<DholMaintenanceEntry> _entries = <DholMaintenanceEntry>[];
  List<MaintenanceEvent> _events = <MaintenanceEvent>[];
  final Map<int, int?> _completionEventAssignedGatById = <int, int?>{};
  List<MaintenanceCompletionRequest> _completionRequests =
      <MaintenanceCompletionRequest>[];
  List<PathakInstrumentMaintenance> _activeInstrumentMaintenances =
      <PathakInstrumentMaintenance>[];
  List<PathakDhol> _pathakDhols = <PathakDhol>[];
  List<PathakDhol> _damagedMaintenanceDhols = <PathakDhol>[];
  List<PathakDhol> _goodConditionDhols = <PathakDhol>[];
  List<CheckedInMaintenancePartner> _eligibleMaintenancePartners =
      <CheckedInMaintenancePartner>[];
  final Map<int, PathakInstrumentMaintenance> _instrumentMaintenanceDetails =
      <int, PathakInstrumentMaintenance>{};
  final Set<int> _updatingDholStatusIds = <int>{};
  final Set<int> _loadingInstrumentMaintenanceDetailIds = <int>{};
  final TextEditingController _dholRangeStartController =
      TextEditingController();
  final TextEditingController _dholRangeEndController = TextEditingController();
  final TextEditingController _dholSearchController = TextEditingController();
  MaintenanceAnalysis? _analysis;

  static const List<String> _dholStatusValues = <String>[
    'damaged',
    'good_condition',
    'under_maintenance',
  ];

  // Categories shown to non-admin users as individual tabs.
  static const List<String> _allCategoryTabs = [
    'dhol',
    'tasha',
    'dhwaj',
    'others',
  ];

  late List<String> _visibleCategoryTabs;

  static const Duration _liveRefreshInterval = Duration(seconds: 20);
  static const String _statePrefix = 'maintenance_screen_';
  static const String _kRequestStatus = '${_statePrefix}request_status';
  static const String _kEntryStatus = '${_statePrefix}entry_status';
  static const String _kCompletionStatus = '${_statePrefix}completion_status';
  static const String _kEventStatus = '${_statePrefix}event_status';
  static const String _kEventScope = '${_statePrefix}event_scope';
  static const String _kEventDate = '${_statePrefix}event_date';
  static const String _kAnalysisEventId = '${_statePrefix}analysis_event_id';
  static const String _kCompletionEventId =
      '${_statePrefix}completion_event_id';
  static const String _kCompletionEventDate =
      '${_statePrefix}completion_event_date';
  static const String _kShowLegacyEntries =
      '${_statePrefix}show_legacy_entries';
  static const String _kDamagedMarkedCachePrefix =
      '${_statePrefix}damaged_marked';

  Set<int> _todayMarkedDamagedDholIds = <int>{};

  bool get _showAdminCompletionTab {
    return widget.canApproveCompletionRequests;
  }

  bool get _canReviewInstrumentMaintenances {
    return widget.canApproveCompletionRequests ||
        widget.canApproveEntries ||
        widget.canManageInventory ||
        widget.isPathakAdminApprover;
  }

  int _approvalsTabIndex() => _allCategoryTabs.length;

  int _eventsTabIndex() => _approvalsTabIndex() + 1;

  int _instrumentMaintenanceTabIndex() => _eventsTabIndex() + 1;

  int _dholRangeTabIndex() => _instrumentMaintenanceTabIndex() + 1;

  int _dholStatusTabIndex() => _dholRangeTabIndex() + 1;

  int _completionTabIndex() {
    return _showAdminCompletionTab ? _dholStatusTabIndex() + 1 : -1;
  }

  int _completionTabIndexForCurrentUser() {
    if (widget.canManageInventory) {
      final index = _completionTabIndex();
      return index == -1 ? _analysisTabIndex() : index;
    }
    return _visibleCategoryTabs.length + 3;
  }

  int _adminTabCount() {
    var count = _allCategoryTabs.length + 5;
    if (_showAdminCompletionTab) {
      count += 1;
    }
    if (_showLegacyEntriesTab) {
      count += 1;
    }
    count += 1;
    return count;
  }

  int _entriesTabIndex() {
    if (!_showLegacyEntriesTab) {
      return -1;
    }
    return _dholStatusTabIndex() + (_showAdminCompletionTab ? 2 : 1);
  }

  int _analysisTabIndex() {
    return _showLegacyEntriesTab
        ? _entriesTabIndex() + 1
        : _dholStatusTabIndex() + (_showAdminCompletionTab ? 2 : 1);
  }

  bool _coerceBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  Future<(bool, bool)> _currentAttendanceState() async {
    final status = await AttendanceService.fetchMyCurrentAttendanceStatus();
    final isCheckedIn = _coerceBool(status['is_checked_in']);
    final isCheckedOut = _coerceBool(status['is_checked_out']);
    return (isCheckedIn, isCheckedOut);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Determine visible categories based on instrument and role
    _visibleCategoryTabs = _getVisibleCategories();

    // Admin: all 4 category tabs + Approvals + Events + Dhol Range + Dhol Status
    // + Completion + Entries + Analysis.
    // Other users: filtered categories + (Approvals or My Requests) + Events
    // + Instrument Maintenance + Completion.
    final tabCount = widget.canManageInventory
        ? _adminTabCount()
        : _visibleCategoryTabs.length + 4;
    _tabController = TabController(length: tabCount, vsync: this);
    _initScreen();
  }

  Future<void> _initScreen() async {
    await _restoreUiState();
    if (!mounted) return;
    await _restoreTodayMarkedDamagedDholCache();
    if (!mounted) return;
    await _initialLoad();
    if (!mounted) return;
    _startLiveRefresh();
    await _openCreateMaintenanceDayOnStartIfNeeded();
    if (!mounted) return;
    await _openCompletionForEventOnStartIfNeeded();
    if (!mounted) return;
    await _openInstrumentMaintenanceOnStartIfNeeded();
  }

  String _todayCacheDate() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  String _todayDamagedMarkedCacheKey() {
    final userScope = widget.currentUserId?.toString() ?? 'anonymous';
    return '${_kDamagedMarkedCachePrefix}_${_todayCacheDate()}_$userScope';
  }

  List<PathakDhol> _filterAlreadyMarkedToday(List<PathakDhol> items) {
    if (_todayMarkedDamagedDholIds.isEmpty) {
      return items;
    }

    return items
        .where((item) => !_todayMarkedDamagedDholIds.contains(item.id))
        .toList();
  }

  Future<void> _restoreTodayMarkedDamagedDholCache() async {
    try {
      final raw = await _storage.read(key: _todayDamagedMarkedCacheKey());
      if (!mounted || raw == null || raw.trim().isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }

      final ids = decoded
          .map((item) => int.tryParse(item.toString()))
          .whereType<int>()
          .toSet();
      if (ids.isEmpty) {
        return;
      }

      setState(() {
        _todayMarkedDamagedDholIds = ids;
      });
    } catch (_) {
      // Ignore cache restore errors.
    }
  }

  Future<void> _cacheTodayMarkedDamagedDhol(int dholId) async {
    if (dholId <= 0) {
      return;
    }

    final updated = <int>{..._todayMarkedDamagedDholIds, dholId};
    if (mounted) {
      setState(() {
        _todayMarkedDamagedDholIds = updated;
      });
    } else {
      _todayMarkedDamagedDholIds = updated;
    }

    try {
      await _storage.write(
        key: _todayDamagedMarkedCacheKey(),
        value: jsonEncode(updated.toList()..sort()),
      );
    } catch (_) {
      // Ignore cache write errors.
    }
  }

  Future<void> _openInstrumentMaintenanceOnStartIfNeeded() async {
    if (_hasOpenedInstrumentMaintenanceOnStart) {
      return;
    }

    final openStart = widget.openStartInstrumentMaintenanceOnStart;
    final maintenanceId = widget.openInstrumentMaintenanceIdOnStart;

    if (!openStart && maintenanceId == null) {
      return;
    }

    _hasOpenedInstrumentMaintenanceOnStart = true;

    if (openStart && !_canReviewInstrumentMaintenances) {
      _tabController.animateTo(_instrumentMaintenanceTabIndex());
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      await _openStartInstrumentMaintenanceDialog();
      return;
    }

    if (maintenanceId == null) {
      return;
    }

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return;
    }

    final matching = _activeInstrumentMaintenances.where(
      (item) => item.id == maintenanceId,
    );
    if (matching.isEmpty) {
      await _showSnack('Unable to find the selected active maintenance.');
      return;
    }

    _tabController.animateTo(_instrumentMaintenanceTabIndex());
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _openInstrumentMaintenanceDetail(
      matching.first,
      openSubmitOnStart: widget.openSubmitForInstrumentMaintenanceOnStart,
    );
  }

  Future<void> _openCreateMaintenanceDayOnStartIfNeeded() async {
    if (!widget.openCreateMaintenanceDayOnStart ||
        _hasOpenedCreateMaintenanceDayOnStart) {
      return;
    }

    final canCreateEvent = widget.canCreateMaintenanceEvents;
    if (!canCreateEvent) {
      return;
    }

    _hasOpenedCreateMaintenanceDayOnStart = true;

    if (widget.canManageInventory) {
      // For admin users, Events tab is fixed after the 4 category and 1 approval tab.
      _tabController.animateTo(_allCategoryTabs.length + 1);
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    final created = await _openCreateEventForm();
    if (created && mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route == null || route.isCurrent) {
          Navigator.of(context).maybePop();
        }
      });
    }
  }

  Future<void> _openCompletionForEventOnStartIfNeeded() async {
    final eventId = widget.openCompletionForEventIdOnStart;
    if (eventId == null || _hasOpenedCompletionOnStart) {
      return;
    }

    _hasOpenedCompletionOnStart = true;

    final matchingEvents = _events.where((event) => event.id == eventId);
    if (matchingEvents.isEmpty) {
      _showSnack('Unable to find the selected maintenance event.');
      return;
    }

    if (kIsWeb) {
      if (widget.canManageInventory) {
        _tabController.animateTo(_eventsTabIndex());
      } else {
        _tabController.animateTo(_visibleCategoryTabs.length + 1);
      }
      _showSnack('Event ready. Open Submit from Events tab.');
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return;
    }
    await _openCompletionRequestForm(matchingEvents.first);
  }

  void _rebuildTabController({required int preferredIndex}) {
    final oldController = _tabController;
    final tabCount = widget.canManageInventory
        ? _adminTabCount()
        : _visibleCategoryTabs.length + 4;
    final targetIndex = preferredIndex.clamp(0, tabCount - 1);

    setState(() {
      _tabController = TabController(
        length: tabCount,
        vsync: this,
        initialIndex: targetIndex,
      );
    });

    oldController.dispose();
  }

  void _toggleLegacyEntriesTab() {
    if (!widget.canManageInventory) return;

    final currentIndex = _tabController.index;
    final entriesIndexBefore = _entriesTabIndex();
    final analysisIndexBefore = _analysisTabIndex();

    setState(() {
      _showLegacyEntriesTab = !_showLegacyEntriesTab;
    });
    unawaited(_persistUiState());

    var nextIndex = currentIndex;
    if (!_showLegacyEntriesTab) {
      if (currentIndex == entriesIndexBefore ||
          currentIndex == analysisIndexBefore) {
        nextIndex = _analysisTabIndex();
      }
    } else if (currentIndex == _analysisTabIndex()) {
      nextIndex = _analysisTabIndex();
    }

    _rebuildTabController(preferredIndex: nextIndex);
  }

  List<String> _getVisibleCategories() {
    if (widget.canManageInventory) {
      return _allCategoryTabs;
    }

    final instrument =
        widget.userInstrument?.toString().trim().toLowerCase() ?? '';

    if (instrument == 'management' || instrument == 'managemnet') {
      return _allCategoryTabs;
    }

    if (instrument.isEmpty) {
      return ['others'];
    }

    return [instrument, 'others'];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveRefreshTimer?.cancel();
    _tabController.dispose();
    _dholRangeStartController.dispose();
    _dholRangeEndController.dispose();
    _dholSearchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startLiveRefresh();
      _runLiveRefreshSilently();
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _liveRefreshTimer?.cancel();
    }
  }

  Future<void> _restoreUiState() async {
    try {
      final requestStatus = await _storage.read(key: _kRequestStatus);
      final entryStatus = await _storage.read(key: _kEntryStatus);
      final completionStatus = await _storage.read(key: _kCompletionStatus);
      final eventStatus = await _storage.read(key: _kEventStatus);
      final eventScope = await _storage.read(key: _kEventScope);
      final eventDate = await _storage.read(key: _kEventDate);
      final analysisEventId = await _storage.read(key: _kAnalysisEventId);
      final completionEventId = await _storage.read(key: _kCompletionEventId);
      final completionEventDate = await _storage.read(
        key: _kCompletionEventDate,
      );
      final showLegacyEntriesRaw = await _storage.read(
        key: _kShowLegacyEntries,
      );

      if (!mounted) return;

      final savedShowLegacy = showLegacyEntriesRaw == null
          ? _showLegacyEntriesTab
          : (showLegacyEntriesRaw.toLowerCase() == 'true' ||
                showLegacyEntriesRaw == '1');

      final shouldRebuildController =
          widget.canManageInventory && savedShowLegacy != _showLegacyEntriesTab;

      setState(() {
        if (requestStatus != null && requestStatus.isNotEmpty) {
          _requestStatusFilter = requestStatus;
        }
        if (entryStatus != null && entryStatus.isNotEmpty) {
          _entryStatusFilter = entryStatus;
        }
        if (completionStatus != null && completionStatus.isNotEmpty) {
          _completionStatusFilter = completionStatus;
        }
        if (eventStatus != null && eventStatus.isNotEmpty) {
          _eventStatusFilter = eventStatus;
        }
        if (eventScope != null && eventScope.isNotEmpty) {
          _eventScopeFilter = eventScope;
        }
        if (eventDate != null) {
          _eventDateFilter = eventDate;
        }
        _analysisEventIdFilter = int.tryParse(analysisEventId ?? '');
        if (completionEventDate != null) {
          _completionEventDateFilter = completionEventDate;
        }
        _completionEventIdFilter = int.tryParse(completionEventId ?? '');
        _showLegacyEntriesTab = savedShowLegacy;
      });

      if (shouldRebuildController) {
        _rebuildTabController(preferredIndex: 0);
      }
    } catch (_) {
      // Keep defaults if persisted state cannot be loaded.
    }
  }

  Future<void> _persistUiState() async {
    try {
      await _storage.write(key: _kRequestStatus, value: _requestStatusFilter);
      await _storage.write(key: _kEntryStatus, value: _entryStatusFilter);
      await _storage.write(
        key: _kCompletionStatus,
        value: _completionStatusFilter,
      );
      await _storage.write(key: _kEventStatus, value: _eventStatusFilter);
      await _storage.write(key: _kEventScope, value: _eventScopeFilter);
      await _storage.write(key: _kEventDate, value: _eventDateFilter);
      await _storage.write(
        key: _kAnalysisEventId,
        value: _analysisEventIdFilter?.toString() ?? '',
      );
      await _storage.write(
        key: _kCompletionEventId,
        value: _completionEventIdFilter?.toString() ?? '',
      );
      await _storage.write(
        key: _kCompletionEventDate,
        value: _completionEventDateFilter,
      );
      await _storage.write(
        key: _kShowLegacyEntries,
        value: _showLegacyEntriesTab.toString(),
      );
    } catch (_) {
      // Ignore state persistence errors.
    }
  }

  void _startLiveRefresh() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer.periodic(_liveRefreshInterval, (_) {
      _runLiveRefreshSilently();
    });
  }

  Future<void> _runLiveRefreshSilently() async {
    if (!mounted || _isLiveRefreshInProgress) return;

    _isLiveRefreshInProgress = true;
    try {
      final futures = <Future<void>>[
        _refreshInventorySilently(),
        _refreshRequestsSilently(),
        _refreshEventsSilently(),
        _refreshCompletionRequestsSilently(),
        _refreshInstrumentMaintenanceDataSilently(),
      ];

      if (widget.canManageInventory) {
        futures.addAll([_refreshEntriesSilently(), _refreshAnalysisSilently()]);
      }

      await Future.wait<void>(futures);
    } catch (_) {
      // Keep silent for periodic sync failures.
    } finally {
      _isLiveRefreshInProgress = false;
    }
  }

  Future<void> _refreshInventorySilently() async {
    final items = await _withApiLoader(MaintenanceService.fetchInventory);
    if (!mounted) return;
    setState(() {
      _inventory = items;
    });
  }

  Future<void> _refreshRequestsSilently() async {
    final items = await _withApiLoader(
      MaintenanceService.fetchInventoryRequests,
    );
    if (!mounted) return;
    setState(() {
      _requests = items;
    });
  }

  Future<void> _refreshEventsSilently() async {
    final items = await _withApiLoader(
      () => MaintenanceService.fetchMaintenanceEvents(
        status: _eventStatusFilter == 'all' ? null : _eventStatusFilter,
        scope: _eventScopeFilter == 'all' ? null : _eventScopeFilter,
        date: _eventDateFilter.trim().isEmpty ? null : _eventDateFilter,
      ),
    );
    if (!mounted) return;
    setState(() {
      _events = items;
    });
  }

  Future<void> _refreshCompletionRequestsSilently() async {
    if (_isGatPramukhCompletionApprover) {
      await _refreshCompletionApprovalEventLookupSilently();
    }

    var items = await _withApiLoader(
      () => MaintenanceService.fetchCompletionRequests(
        eventId: _completionEventIdFilter,
        eventDate: _completionEventDateFilter.trim().isEmpty
            ? null
            : _completionEventDateFilter,
        myActionable: _isGatPramukhCompletionApprover,
      ),
    );

    if (_isGatPramukhCompletionApprover && items.isEmpty) {
      items = await _withApiLoader(
        () => MaintenanceService.fetchCompletionRequests(
          eventId: _completionEventIdFilter,
          eventDate: _completionEventDateFilter.trim().isEmpty
              ? null
              : _completionEventDateFilter,
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _completionRequests = items;
    });
  }

  Future<void> _refreshEntriesSilently() async {
    final items = await _withApiLoader(
      () => MaintenanceService.fetchEntries(
        gatId: !widget.isPathakAdminApprover ? widget.approverGatId : null,
      ),
    );
    if (!mounted) return;
    setState(() {
      _entries = items;
    });
  }

  Future<void> _refreshAnalysisSilently() async {
    final analysis = await _withApiLoader(MaintenanceService.fetchAnalysis);
    if (!mounted) return;
    setState(() {
      _analysis = analysis;
    });
  }

  Future<void> _refreshInstrumentMaintenanceDataSilently() async {
    final maintenances = await _withApiLoader(
      MaintenanceService.fetchInstrumentMaintenancesForReview,
    );
    final pathakDhols = await _withApiLoader(
      MaintenanceService.fetchPathakDhols,
    );
    List<PathakDhol> damagedDhols = _damagedMaintenanceDhols;
    List<CheckedInMaintenancePartner> partners = _eligibleMaintenancePartners;

    if (!_canReviewInstrumentMaintenances) {
      damagedDhols = await _withApiLoader(
        MaintenanceService.fetchDamagedPathakDhols,
      );
      partners = await _withApiLoader(
        MaintenanceService.fetchCheckedInMaintenancePartners,
      );
    }

    List<PathakDhol> goodConditionDhols = _goodConditionDhols;
    try {
      goodConditionDhols = await _withApiLoader(
        MaintenanceService.fetchGoodConditionPathakDhols,
      );
      goodConditionDhols = _filterAlreadyMarkedToday(goodConditionDhols);
    } catch (_) {
      // Keep stale list on silent refresh failure.
    }

    if (!mounted) return;
    setState(() {
      _activeInstrumentMaintenances = maintenances;
      _pathakDhols = pathakDhols;
      _goodConditionDhols = goodConditionDhols;
      _damagedMaintenanceDhols = !_canReviewInstrumentMaintenances
          ? damagedDhols
          : pathakDhols
                .where((item) => item.normalizedStatus == 'damaged')
                .toList();
      if (!_canReviewInstrumentMaintenances) {
        _eligibleMaintenancePartners = partners;
      }
    });
  }

  Future<void> _initialLoad() async {
    final commonLoads = <Future<void>>[
      _loadInventory(),
      _loadRequests(),
      _loadEvents(),
      _loadCompletionRequests(),
      _loadInstrumentMaintenanceData(),
    ];

    if (widget.canManageInventory) {
      commonLoads.addAll([_loadEntries(), _loadAnalysis()]);
    }

    await Future.wait<void>(commonLoads);
    if (!mounted) return;
    if (widget.canManageInventory) {
      _applyAdminDefaultTabIfNeeded();
    }
  }

  void _applyAdminDefaultTabIfNeeded() {
    if (!widget.canManageInventory || _hasAppliedAdminDefaultTab) {
      return;
    }

    _hasAppliedAdminDefaultTab = true;
    final requestedSection = widget.initialAdminSection?.trim().toLowerCase();
    if (requestedSection == 'approvals') {
      _tabController.animateTo(_approvalsTabIndex());
      return;
    }
    if (requestedSection == 'analysis') {
      _tabController.animateTo(_analysisTabIndex());
      return;
    }
    if (requestedSection == 'instrument_maintenance' ||
        requestedSection == 'dhol_maintenance') {
      _tabController.animateTo(_instrumentMaintenanceTabIndex());
      return;
    }

    final pendingRequests = _requests.where(_isPendingInventoryRequest).length;
    final pendingEntries = _entries
        .where((item) => item.status.toLowerCase() == 'pending')
        .length;
    final pendingCompletionRequests = _completionRequests
        .where((item) => item.status.toLowerCase() == 'pending')
        .length;
    if (_showAdminCompletionTab && pendingCompletionRequests > 0) {
      _tabController.animateTo(_completionTabIndex());
      return;
    }
    if (pendingRequests > 0) {
      _tabController.animateTo(_approvalsTabIndex());
      return;
    }
    if (pendingEntries > 0 && _showLegacyEntriesTab) {
      _tabController.animateTo(_entriesTabIndex());
    }
  }

  Future<void> _loadInventory() async {
    setState(() {
      _isLoadingInventory = true;
    });

    try {
      final items = await _withApiLoader(MaintenanceService.fetchInventory);
      if (!mounted) return;
      setState(() {
        _inventory = items;
      });
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInventory = false;
        });
      }
    }
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoadingRequests = true;
    });

    try {
      final items = await _withApiLoader(
        MaintenanceService.fetchInventoryRequests,
      );
      if (!mounted) return;
      setState(() {
        _requests = items;
      });
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRequests = false;
        });
      }
    }
  }

  Future<void> _loadEntries() async {
    setState(() {
      _isLoadingEntries = true;
    });

    try {
      final items = await _withApiLoader(
        () => MaintenanceService.fetchEntries(
          gatId: !widget.isPathakAdminApprover ? widget.approverGatId : null,
        ),
      );
      if (!mounted) return;
      setState(() {
        _entries = items;
      });
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingEntries = false;
        });
      }
    }
  }

  Future<void> _loadAnalysis() async {
    if (!widget.canManageInventory) return;

    setState(() {
      _isLoadingAnalysis = true;
    });

    try {
      final analysis = await _withApiLoader(MaintenanceService.fetchAnalysis);
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
      });
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAnalysis = false;
        });
      }
    }
  }

  Future<void> _loadEvents() async {
    setState(() {
      _isLoadingEvents = true;
    });

    try {
      final items = await _withApiLoader(
        () => MaintenanceService.fetchMaintenanceEvents(
          status: _eventStatusFilter == 'all' ? null : _eventStatusFilter,
          scope: _eventScopeFilter == 'all' ? null : _eventScopeFilter,
          date: _eventDateFilter.trim().isEmpty ? null : _eventDateFilter,
        ),
      );
      if (!mounted) return;
      setState(() {
        _events = items;
      });
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingEvents = false;
        });
      }
    }
  }

  Future<void> _loadCompletionRequests() async {
    setState(() {
      _isLoadingCompletionRequests = true;
    });

    try {
      if (_isGatPramukhCompletionApprover) {
        await _refreshCompletionApprovalEventLookupSilently();
      }

      var items = await _withApiLoader(
        () => MaintenanceService.fetchCompletionRequests(
          eventId: _completionEventIdFilter,
          eventDate: _completionEventDateFilter.trim().isEmpty
              ? null
              : _completionEventDateFilter,
          myActionable: _isGatPramukhCompletionApprover,
        ),
      );

      if (_isGatPramukhCompletionApprover && items.isEmpty) {
        items = await _withApiLoader(
          () => MaintenanceService.fetchCompletionRequests(
            eventId: _completionEventIdFilter,
            eventDate: _completionEventDateFilter.trim().isEmpty
                ? null
                : _completionEventDateFilter,
          ),
        );
      }

      if (_isGatPramukhCompletionApprover &&
          _completionEventIdFilter != null &&
          items.isEmpty) {
        _completionEventIdFilter = null;
        unawaited(_persistUiState());

        items = await _withApiLoader(
          () => MaintenanceService.fetchCompletionRequests(
            eventDate: _completionEventDateFilter.trim().isEmpty
                ? null
                : _completionEventDateFilter,
            myActionable: _isGatPramukhCompletionApprover,
          ),
        );
      }

      items = await _hydrateCompletionRequestParticipants(items);

      if (!mounted) return;
      setState(() {
        _completionRequests = items;
      });
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCompletionRequests = false;
        });
      }
    }
  }

  Future<List<MaintenanceCompletionRequest>>
  _hydrateCompletionRequestParticipants(
    List<MaintenanceCompletionRequest> requests,
  ) async {
    final idsToFetch = <int>{};

    for (final request in requests) {
      if (request.participants.isNotEmpty) {
        continue;
      }

      final maintenanceId = request.maintenanceId;
      if (maintenanceId == null || maintenanceId <= 0) {
        continue;
      }

      final cached = _instrumentMaintenanceDetails[maintenanceId];
      if (cached != null && cached.participants.isNotEmpty) {
        continue;
      }

      idsToFetch.add(maintenanceId);
    }

    if (idsToFetch.isNotEmpty) {
      await Future.wait<void>(
        idsToFetch.map((maintenanceId) async {
          try {
            final detail =
                await MaintenanceService.fetchInstrumentMaintenanceDetail(
                  maintenanceId,
                );
            _instrumentMaintenanceDetails[maintenanceId] = detail;
          } catch (_) {
            // Keep completion requests visible even when optional hydration fails.
          }
        }),
      );
    }

    return requests.map((request) {
      if (request.participants.isNotEmpty) {
        return request;
      }

      final maintenanceId = request.maintenanceId;
      if (maintenanceId == null || maintenanceId <= 0) {
        return request;
      }

      final linked = _instrumentMaintenanceDetails[maintenanceId];
      final participants =
          linked?.participants ?? const <InstrumentMaintenanceParticipant>[];
      if (participants.isEmpty) {
        return request;
      }

      return request.copyWith(participants: participants);
    }).toList();
  }

  Future<void> _loadPathakDhols() async {
    setState(() {
      _isLoadingPathakDhols = true;
    });

    try {
      final items = await _withApiLoader(MaintenanceService.fetchPathakDhols);
      if (!mounted) return;
      setState(() {
        _pathakDhols = items;
        _damagedMaintenanceDhols = items
            .where((item) => item.normalizedStatus == 'damaged')
            .toList();
      });
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPathakDhols = false;
        });
      }
    }
  }

  Future<void> _loadGoodConditionDhols() async {
    try {
      final items = await _withApiLoader(
        MaintenanceService.fetchGoodConditionPathakDhols,
      );
      if (!mounted) return;
      setState(() {
        _goodConditionDhols = _filterAlreadyMarkedToday(items);
      });
    } catch (_) {
      // Non-fatal: card will show 0 but button remains available.
    }
  }

  Future<void> _loadDamagedMaintenanceDhols() async {
    setState(() {
      _isLoadingPathakDhols = true;
    });

    try {
      final items = await _withApiLoader(
        MaintenanceService.fetchDamagedPathakDhols,
      );
      if (!mounted) return;
      setState(() {
        _damagedMaintenanceDhols = items;
      });
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPathakDhols = false;
        });
      }
    }
  }

  Future<void> _loadEligibleMaintenancePartners() async {
    setState(() {
      _isLoadingMaintenancePartners = true;
    });

    try {
      final items = await _withApiLoader(
        MaintenanceService.fetchCheckedInMaintenancePartners,
      );
      if (!mounted) return;
      setState(() {
        _eligibleMaintenancePartners = items;
      });
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMaintenancePartners = false;
        });
      }
    }
  }

  Future<void> _loadActiveInstrumentMaintenances() async {
    setState(() {
      _isLoadingActiveInstrumentMaintenances = true;
    });

    try {
      final items = await _withApiLoader(
        MaintenanceService.fetchInstrumentMaintenancesForReview,
      );
      if (!mounted) return;
      setState(() {
        _activeInstrumentMaintenances = items;
      });
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingActiveInstrumentMaintenances = false;
        });
      }
    }
  }

  Future<void> _loadInstrumentMaintenanceData() async {
    final futures = <Future<void>>[
      _loadActiveInstrumentMaintenances(),
      _loadPathakDhols(),
      _loadGoodConditionDhols(),
    ];

    if (!_canReviewInstrumentMaintenances) {
      futures.addAll([
        _loadDamagedMaintenanceDhols(),
        _loadEligibleMaintenancePartners(),
      ]);
    }

    await Future.wait<void>(futures);
  }

  Future<void> _refreshActiveTab() async {
    final activeIndex = _tabController.index;

    if (widget.canManageInventory) {
      if (activeIndex < _allCategoryTabs.length) {
        await _loadInventory();
        return;
      }
      if (activeIndex == _approvalsTabIndex()) {
        await _loadRequests();
        return;
      }
      if (activeIndex == _eventsTabIndex()) {
        await _loadEvents();
        return;
      }
      if (activeIndex == _instrumentMaintenanceTabIndex()) {
        await _loadInstrumentMaintenanceData();
        return;
      }
      if (activeIndex == _dholRangeTabIndex() ||
          activeIndex == _dholStatusTabIndex()) {
        await _loadPathakDhols();
        return;
      }
      if (_completionTabIndex() != -1 && activeIndex == _completionTabIndex()) {
        await _loadCompletionRequests();
        return;
      }
      if (_showLegacyEntriesTab && activeIndex == _entriesTabIndex()) {
        await _loadEntries();
        return;
      }
      await _loadAnalysis();
      return;
    }

    final categoryTabCount = _visibleCategoryTabs.length;
    if (activeIndex < categoryTabCount) {
      await _loadInventory();
      return;
    }
    if (activeIndex == categoryTabCount) {
      await _loadRequests();
      return;
    }
    if (activeIndex == categoryTabCount + 1) {
      await _loadEvents();
      return;
    }
    if (activeIndex == categoryTabCount + 2) {
      await _loadInstrumentMaintenanceData();
      return;
    }
    await _loadCompletionRequests();
  }

  Future<void> _openInventoryForm({String? preselectedCategory}) async {
    final formKey = GlobalKey<FormState>();
    late String selectedCategory;
    final nameController = TextEditingController();
    final quantityController = TextEditingController();
    final otherCategoryController = TextEditingController();

    void disposeControllers() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameController.dispose();
        quantityController.dispose();
        otherCategoryController.dispose();
      });
    }

    if (preselectedCategory != null) {
      selectedCategory = preselectedCategory;
    } else {
      selectedCategory = MaintenanceService.inventoryCategories.first;
    }

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Create Stock'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 460,
                  maxHeight: 420,
                ),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (preselectedCategory == null)
                          DropdownButtonFormField<String>(
                            initialValue: selectedCategory,
                            isExpanded: true,
                            items: MaintenanceService.inventoryCategories
                                .map(
                                  (cat) => DropdownMenuItem(
                                    value: cat,
                                    child: Text(
                                      cat[0].toUpperCase() + cat.substring(1),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  selectedCategory = val;
                                });
                              }
                            },
                            decoration: const InputDecoration(
                              labelText: 'Category',
                            ),
                          ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Item Name',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Item name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        if (selectedCategory == 'others')
                          TextFormField(
                            controller: otherCategoryController,
                            decoration: const InputDecoration(
                              labelText: 'Category Name',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Category name is required for Others';
                              }
                              return null;
                            },
                          )
                        else
                          const SizedBox.shrink(),
                        if (selectedCategory == 'others')
                          const SizedBox(height: 12)
                        else
                          const SizedBox.shrink(),
                        TextFormField(
                          controller: quantityController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Initial Quantity',
                          ),
                          validator: (value) {
                            final qty = int.tryParse(value ?? '');
                            if (qty == null || qty <= 0) {
                              return 'Enter a valid quantity';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSubmit != true) {
      disposeControllers();
      return;
    }

    try {
      final response = await _withApiLoader(
        () => MaintenanceService.createOrUpdateInventory(
          category: selectedCategory,
          otherCategoryName: otherCategoryController.text.trim(),
          name: nameController.text.trim(),
          quantity: int.parse(quantityController.text.trim()),
        ),
      );

      _showSnack(response['message']?.toString() ?? 'Stock created.');
      await _loadInventory();
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      disposeControllers();
    }
  }

  Future<void> _openUpdateStockForm(InventoryItem item) async {
    final formKey = GlobalKey<FormState>();
    final quantityController = TextEditingController();

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update Stock'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Item: ${item.name}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Current Quantity: ${item.quantityAvailable}',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity to Add',
                  ),
                  validator: (value) {
                    final qty = int.tryParse(value ?? '');
                    if (qty == null || qty <= 0) {
                      return 'Enter a valid quantity';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(context).pop(true);
                }
              },
              style: ElevatedButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Update'),
            ),
          ],
        );
      },
    );

    if (shouldSubmit != true) {
      quantityController.dispose();
      return;
    }

    try {
      final response = await _withApiLoader(
        () => MaintenanceService.createOrUpdateInventory(
          category: item.category,
          otherCategoryName: item.otherCategoryName,
          name: item.name,
          quantity: int.parse(quantityController.text.trim()),
        ),
      );
      _showSnack(response['message']?.toString() ?? 'Stock updated.');
      await _loadInventory();
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      quantityController.dispose();
    }
  }

  Future<void> _openRenameStockForm(InventoryItem item) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: item.name);
    final otherCategoryController = TextEditingController(
      text: item.otherCategoryName,
    );

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Stock'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Item Name'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Item name is required';
                    }
                    return null;
                  },
                ),
                if (item.category.toLowerCase() == 'others') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: otherCategoryController,
                    decoration: const InputDecoration(
                      labelText: 'Category Name',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Category name is required for Others';
                      }
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(context).pop(true);
                }
              },
              style: ElevatedButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    if (shouldSubmit != true) {
      nameController.dispose();
      otherCategoryController.dispose();
      return;
    }

    try {
      final response = await _withApiLoader(
        () => MaintenanceService.renameInventoryItem(
          inventoryItemId: item.id,
          name: nameController.text.trim(),
          otherCategoryName: otherCategoryController.text.trim(),
        ),
      );
      _showSnack(response['message']?.toString() ?? 'Stock renamed.');
      await _loadInventory();
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      nameController.dispose();
      otherCategoryController.dispose();
    }
  }

  Future<void> _confirmDeleteStock(InventoryItem item) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Stock'),
          content: Text('Delete ${item.name}? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    try {
      final response = await _withApiLoader(
        () => MaintenanceService.deleteInventoryItem(inventoryItemId: item.id),
      );
      _showSnack(response['message']?.toString() ?? 'Stock deleted.');
      await _loadInventory();
    } catch (e) {
      _showSnack(e.toString());
    }
  }

  Future<void> _openStockUpdateProposalForm(InventoryItem item) async {
    final formKey = GlobalKey<FormState>();
    final quantityController = TextEditingController();
    final noteController = TextEditingController();

    // Update stock proposals are never linked to a maintenance event.
    const int? selectedEventId = null;

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Update Stock Request: ${item.name}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Current Available: ${item.quantityAvailable}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity to Add',
                  ),
                  validator: (value) {
                    final qty = int.tryParse(value ?? '');
                    if (qty == null || qty <= 0) {
                      return 'Enter a valid quantity';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(context).pop(true);
                }
              },
              style: ElevatedButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );

    if (shouldSubmit != true) {
      quantityController.dispose();
      noteController.dispose();
      return;
    }

    try {
      final response = await _withApiLoader(
        () => MaintenanceService.createInventoryRequest(
          inventoryItemId: item.id,
          requestedQuantity: int.parse(quantityController.text.trim()),
          note: noteController.text.trim(),
          eventId: selectedEventId,
        ),
      );
      _showSnack(
        response['message']?.toString() ??
            'Stock update request submitted for approval.',
      );
      await _loadRequests();
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      quantityController.dispose();
      noteController.dispose();
    }
  }

  Future<void> _openSingleStockRequestForm(InventoryItem item) async {
    final latestClosed = await _isLatestMaintenanceEventClosed();
    if (latestClosed) {
      _showSnack('Maintenance event is closed.');
      return;
    }

    final formKey = GlobalKey<FormState>();
    final noteController = TextEditingController();

    // Auto-select the latest active maintenance event, if any.
    final int? selectedEventId = latestActiveMaintenanceEventId(_events);
    final MaintenanceEvent? selectedEvent = selectedEventId == null
        ? null
        : _events.where((event) => event.id == selectedEventId).firstOrNull;
    final selectedMaintenance = selectedEvent == null
        ? null
        : _currentUserMaintenanceForEvent(selectedEvent);

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Request Stock: ${item.name}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Current Available: ${item.quantityAvailable}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                if (selectedEvent != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryMaroon.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.event,
                          size: 14,
                          color: AppColors.primaryMaroon,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${selectedEvent.title} (${selectedEvent.eventDate})',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.primaryMaroon,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: '1',
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Requested Quantity',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(context).pop(true);
                }
              },
              style: ElevatedButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Request'),
            ),
          ],
        );
      },
    );

    if (shouldSubmit != true) {
      noteController.dispose();
      return;
    }

    final blockedByCompletion = await _isStockRequestBlockedByCompletion(
      eventId: selectedEventId,
    );
    if (blockedByCompletion) {
      _showSnack(
        'Completion already submitted (pending/approved) for this maintenance day. You cannot send stock request now.',
      );
      noteController.dispose();
      return;
    }

    try {
      final response = await _withApiLoader(
        () => MaintenanceService.createInventoryRequest(
          inventoryItemId: item.id,
          requestedQuantity: 1,
          note: noteController.text.trim(),
          maintenanceId: selectedMaintenance?.maintenanceId,
          eventId: selectedEventId,
        ),
      );
      _showSnack(
        response['message']?.toString() ??
            'Stock request submitted for approval.',
      );
      await _loadRequests();
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      noteController.dispose();
    }
  }

  Future<bool> _isLatestMaintenanceEventClosed() async {
    try {
      final events = await _withApiLoader(
        MaintenanceService.fetchMaintenanceEvents,
      );
      final latestEventId = latestMaintenanceEventId(events);
      if (latestEventId == null) {
        return false;
      }

      final latestEvent = events
          .where((event) => event.id == latestEventId)
          .firstOrNull;
      return latestEvent?.isClosedStatus ?? false;
    } catch (_) {
      // If status cannot be determined, do not hard-block locally.
      return false;
    }
  }

  Future<void> _actOnRequest(InventoryRequestItem item, String action) async {
    if (!widget.canManageInventory) {
      _showSnack('You are not allowed to approve or reject stock requests.');
      return;
    }

    final noteController = TextEditingController();
    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            '${action == 'approve' ? 'Approve' : 'Reject'} Stock Update Proposal',
          ),
          content: TextField(
            controller: noteController,
            decoration: const InputDecoration(
              labelText: 'Decision Note (optional)',
            ),
            maxLines: 2,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: Text(action == 'approve' ? 'Approve' : 'Reject'),
            ),
          ],
        );
      },
    );

    if (shouldSubmit != true) {
      noteController.dispose();
      return;
    }

    try {
      final response = await _withApiLoader(
        () => MaintenanceService.actOnInventoryRequest(
          requestId: item.id,
          action: action,
          adminNote: noteController.text.trim(),
        ),
      );
      _showSnack(response['message']?.toString() ?? 'Request updated.');
      await Future.wait<void>([_loadRequests(), _loadInventory()]);
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      noteController.dispose();
    }
  }

  Future<bool> _openCreateEventForm() async {
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String? successMessage;
    List<Map<String, dynamic>> availableGats = <Map<String, dynamic>>[];
    int? selectedGatId;
    var isSubmitting = false;

    try {
      availableGats = await _withApiLoader(ApiService.fetchGats);
    } catch (_) {
      // Keep form usable for pathak scope even if gats cannot be fetched.
    }

    DateTime selectedDate = DateTime.now();
    String selectedScope = 'pathak';

    if (!mounted) return false;

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create Maintenance Day'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleController,
                        decoration: const InputDecoration(labelText: 'Title'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Title is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: selectedScope,
                        decoration: const InputDecoration(labelText: 'Scope'),
                        items: const [
                          DropdownMenuItem(
                            value: 'pathak',
                            child: Text('Pathak'),
                          ),
                          DropdownMenuItem(value: 'gat', child: Text('Gat')),
                        ],
                        onChanged: isSubmitting
                            ? null
                            : (value) {
                                if (value == null) return;
                                setDialogState(() {
                                  selectedScope = value;
                                });
                              },
                      ),
                      if (selectedScope == 'gat') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          initialValue: selectedGatId,
                          decoration: const InputDecoration(
                            labelText: 'Assigned Gat',
                          ),
                          items: availableGats
                              .map(
                                (gat) => DropdownMenuItem<int>(
                                  value: int.tryParse(
                                    gat['id']?.toString() ?? '',
                                  ),
                                  child: Text(
                                    gat['name']?.toString().trim().isNotEmpty ==
                                            true
                                        ? gat['name'].toString().trim()
                                        : 'Gat #${gat['id']}',
                                  ),
                                ),
                              )
                              .where((item) => item.value != null)
                              .cast<DropdownMenuItem<int>>()
                              .toList(),
                          onChanged: isSubmitting
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    selectedGatId = value;
                                  });
                                },
                          validator: (value) {
                            if (selectedScope == 'gat') {
                              if (value == null || value <= 0) {
                                return 'Select a gat';
                              }
                            }
                            return null;
                          },
                        ),
                        if (availableGats.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'No gats available. Please check gats setup.',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: isSubmitting
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime.now().subtract(
                                    const Duration(days: 1),
                                  ),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    selectedDate = picked;
                                  });
                                }
                              },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Event Date',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                          });

                          try {
                            final dateString =
                                '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                            final response = await _withApiLoader(
                              () => MaintenanceService.createMaintenanceEvent(
                                title: titleController.text.trim(),
                                description: descriptionController.text.trim(),
                                eventDate: dateString,
                                scope: selectedScope,
                                assignedGatId: selectedScope == 'gat'
                                    ? selectedGatId
                                    : null,
                              ),
                            );
                            successMessage =
                                response['message']?.toString() ??
                                'Maintenance event created successfully.';
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          } catch (e) {
                            _showSnack(e.toString());
                            if (context.mounted) {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSubmit != true) {
      titleController.dispose();
      descriptionController.dispose();
      return false;
    }

    try {
      if (successMessage != null && successMessage!.isNotEmpty) {
        _showSnack(successMessage!);
      }
      await _loadEvents();
      return true;
    } finally {
      titleController.dispose();
      descriptionController.dispose();
    }
  }

  Future<void> _closeMaintenanceEvent(MaintenanceEvent event) async {
    if (!widget.canCreateMaintenanceEvents) {
      _showSnack('You are not allowed to close maintenance events.');
      return;
    }

    if (event.isClosedStatus) {
      _showSnack('Maintenance event is already closed.');
      return;
    }

    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Close Maintenance Event'),
          content: const Text(
            'Are you sure you want to close this maintenance event?\n\nThis will stop all new maintenance activities for this event.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Close Maintenance Event'),
            ),
          ],
        );
      },
    );

    if (shouldClose != true) return;

    try {
      final response = await _withApiLoader(
        () => MaintenanceService.closeMaintenanceEvent(eventId: event.id),
      );
      _showSnack(
        response['message']?.toString() ?? 'Maintenance event closed.',
      );
      await Future.wait<void>([
        _loadEvents(),
        _loadCompletionRequests(),
        _loadInstrumentMaintenanceData(),
      ]);
    } catch (e) {
      _showSnack(e.toString());
    }
  }

  Future<void> _openCompletionRequestForm(MaintenanceEvent event) async {
    if (event.isClosedStatus) {
      _showSnack('Maintenance event is closed.');
      return;
    }

    if (!isLatestActiveMaintenanceEvent(event, _events)) {
      _showSnack(
        'This maintenance day is closed. It stays open until a newer maintenance day is created.',
      );
      return;
    }

    List<MaintenanceCompletionRequest> dayScopedRequests;
    try {
      dayScopedRequests = await _withApiLoader(
        () => MaintenanceService.fetchCompletionRequests(eventId: event.id),
      );
    } catch (_) {
      dayScopedRequests = _completionRequests
          .where((request) => request.event == event.id)
          .toList();
    }

    final userScopedDayRequests = _filterCompletionsForCurrentUser(
      dayScopedRequests,
    );

    final hasPendingOrApprovedCompletion = userScopedDayRequests.any((request) {
      final status = request.status.toLowerCase();
      return status == 'pending' || status == 'approved';
    });

    if (hasPendingOrApprovedCompletion) {
      final hasPending = userScopedDayRequests.any(
        (request) => request.status.toLowerCase() == 'pending',
      );
      _showSnack(
        hasPending
            ? 'Completion already submitted and pending approval for this day.'
            : 'Completion already approved for this day.',
      );
      return;
    }

    final selectedMaintenance = _currentUserMaintenanceForEvent(event);
    final selectedMaintenanceId = selectedMaintenance?.maintenanceId ?? 0;

    final maintenanceScopedStockRequests = _requests;

    final eventScopedRequests = maintenanceScopedStockRequests.where((request) {
      if (request.maintenanceId != null && selectedMaintenanceId > 0) {
        return request.maintenanceId == selectedMaintenanceId;
      }

      if (request.maintenanceEventId != null) {
        return request.maintenanceEventId == event.id;
      }

      final linkedEventDay = request.linkedEventDay;
      final eventDay = event.parsedEventDate;
      if (linkedEventDay != null && eventDay != null) {
        return linkedEventDay == eventDay;
      }

      return false;
    }).toList();

    final hasPendingStockRequest = selectedMaintenanceId > 0
        ? _hasPendingStockRequestForMaintenance(
            selectedMaintenanceId,
            eventScopedRequests,
          )
        : eventScopedRequests.any(_isPendingInventoryRequest);
    if (hasPendingStockRequest) {
      _showSnack(
        'Some stock requests are still pending approval. Please wait for approval or rejection before submitting maintenance.',
      );
      return;
    }

    // Stock usage is optional. If the user has approved stock requests for this
    // maintenance day, include only those as used_items.
    final approvedRequests = eventScopedRequests
        .where((req) => req.normalizedStatus == 'approved')
        .toList();

    final usedItems = buildCompletionUsedItems(approvedRequests);
    if (!mounted) return;
    final submission = await showMaintenanceCompletionDialog(
      context: context,
      eventTitle: event.title,
      usedItems: usedItems,
    );

    if (submission == null) {
      return;
    }

    try {
      final response = await _withApiLoader(
        () => MaintenanceService.createCompletionRequest(
          maintenanceId: selectedMaintenanceId,
          eventId: event.id,
          workNotes: submission.workNotes,
          usedItems: submission.usedItems,
        ),
      );
      _showSnack(
        response['message']?.toString() ??
            'Completion request submitted successfully.',
      );
      await Future.wait<void>([_loadCompletionRequests(), _loadInventory()]);
    } catch (e) {
      _showSnack(e.toString());
    }
  }

  Future<void> _actOnCompletionRequest(
    MaintenanceCompletionRequest item,
    String action,
  ) async {
    if (!widget.canApproveCompletionRequests) {
      _showSnack('You are not allowed to approve or reject completion.');
      return;
    }

    if (!_canApproveCompletionRequestItem(item)) {
      _showSnack(
        widget.isPathakAdminApprover
            ? 'You are not allowed to approve this completion request.'
            : 'You can approve completion only for your assigned gat events.',
      );
      return;
    }

    final noteController = TextEditingController();
    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            '${action == 'approve' ? 'Approve' : 'Reject'} Completion Request',
          ),
          content: TextField(
            controller: noteController,
            decoration: const InputDecoration(
              labelText: 'Approver Note (optional)',
            ),
            maxLines: 2,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: Text(action == 'approve' ? 'Approve' : 'Reject'),
            ),
          ],
        );
      },
    );

    if (shouldSubmit != true) {
      noteController.dispose();
      return;
    }

    try {
      final response = await _withApiLoader(
        () => MaintenanceService.actOnCompletionRequest(
          requestId: item.id,
          action: action,
          approverNote: noteController.text.trim(),
        ),
      );
      _showSnack(
        response['message']?.toString() ?? 'Completion request updated.',
      );
      await Future.wait<void>([
        _loadCompletionRequests(),
        _loadInventory(),
        _loadEvents(),
        _loadActiveInstrumentMaintenances(),
      ]);
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      noteController.dispose();
    }
  }

  bool _canApproveCompletionRequestItem(MaintenanceCompletionRequest item) {
    if (!widget.canApproveCompletionRequests) {
      return false;
    }

    // Pathak admins can approve any request in their pathak.
    if (widget.isPathakAdminApprover) {
      return true;
    }

    // Non-pathak-admin approvers (e.g. gat_pramukh) are restricted to
    // requests tied to their assigned gat only.
    final approverGatId = widget.approverGatId;
    final currentUserId = widget.currentUserId;

    if (item.isActionableForCurrentUser) {
      return true;
    }

    if (currentUserId != null && item.assignedGatPramukhId != null) {
      return item.assignedGatPramukhId == currentUserId;
    }

    final normalizedCurrentName =
        widget.currentUserName?.trim().toLowerCase() ?? '';
    if (normalizedCurrentName.isNotEmpty) {
      final assignedName =
          item.assignedGatPramukhName?.trim().toLowerCase() ?? '';
      final submitterGatPramukhName =
          item.submitterGatPramukhName?.trim().toLowerCase() ?? '';
      if (assignedName == normalizedCurrentName ||
          submitterGatPramukhName == normalizedCurrentName) {
        return true;
      }
    }

    if (approverGatId == null) {
      return false;
    }

    if (item.assignedGatId != null) {
      return item.assignedGatId == approverGatId;
    }

    final lookupAssignedGat = _completionEventAssignedGatById[item.event];
    if (lookupAssignedGat != null) {
      return lookupAssignedGat == approverGatId;
    }

    final relatedEvent = _events.where((event) => event.id == item.event);
    if (relatedEvent.isEmpty) {
      // Keep request visible/actionable when event lookup is unavailable.
      // Backend still enforces exact approver permissions.
      return true;
    }

    final event = relatedEvent.first;
    return event.assignedGat == approverGatId;
  }

  bool get _isGatPramukhCompletionApprover {
    return widget.canApproveCompletionRequests &&
        !widget.isPathakAdminApprover &&
        (widget.approverGatId != null || widget.currentUserId != null);
  }

  bool _canViewCompletionRequestItem(MaintenanceCompletionRequest item) {
    if (widget.canApproveCompletionRequests) {
      if (_isGatPramukhCompletionApprover && item.isActionableForCurrentUser) {
        return true;
      }
      if (_isGatPramukhCompletionApprover) {
        final normalizedCurrentName =
            widget.currentUserName?.trim().toLowerCase() ?? '';
        final assignedName =
            item.assignedGatPramukhName?.trim().toLowerCase() ?? '';
        final submitterGatPramukhName =
            item.submitterGatPramukhName?.trim().toLowerCase() ?? '';
        if (normalizedCurrentName.isNotEmpty &&
            (assignedName == normalizedCurrentName ||
                submitterGatPramukhName == normalizedCurrentName)) {
          return true;
        }
      }
      return _canApproveCompletionRequestItem(item);
    }

    return _isCompletionRequestOwnedByCurrentUser(item);
  }

  bool _isCompletionRequestOwnedByCurrentUser(
    MaintenanceCompletionRequest item,
  ) {
    final currentUserId = widget.currentUserId;
    if (currentUserId != null && item.submittedBy == currentUserId) {
      return true;
    }

    final normalizedCurrentName =
        widget.currentUserName?.trim().toLowerCase() ?? '';
    final normalizedSubmittedByName = item.submittedByName.trim().toLowerCase();
    if (normalizedCurrentName.isEmpty || normalizedSubmittedByName.isEmpty) {
      return false;
    }

    return normalizedCurrentName == normalizedSubmittedByName;
  }

  bool _isPendingInventoryRequest(InventoryRequestItem item) {
    final normalizedStatus = item.normalizedStatus.trim().toLowerCase();
    if (normalizedStatus == 'pending' ||
        normalizedStatus.startsWith('pending') ||
        normalizedStatus.contains('pending')) {
      return true;
    }

    final rawStatus = item.status.trim().toLowerCase();
    return rawStatus == 'pending' ||
        rawStatus.startsWith('pending') ||
        rawStatus.contains('pending');
  }

  bool _hasPendingStockRequestForMaintenance(
    int maintenanceId,
    Iterable<InventoryRequestItem> requests,
  ) {
    if (maintenanceId <= 0) {
      return false;
    }

    return requests.any((request) {
      if (request.maintenanceId != maintenanceId) {
        return false;
      }
      return _isPendingInventoryRequest(request);
    });
  }

  Future<bool> _isStockRequestBlockedByCompletion({int? eventId}) async {
    if (eventId == null) {
      return false;
    }

    List<MaintenanceCompletionRequest> dayScopedRequests;
    try {
      dayScopedRequests = await _withApiLoader(
        () => MaintenanceService.fetchCompletionRequests(eventId: eventId),
      );
    } catch (_) {
      dayScopedRequests = _completionRequests
          .where((request) => request.event == eventId)
          .toList();
    }

    final userScopedDayRequests = _filterCompletionsForCurrentUser(
      dayScopedRequests,
    );

    return userScopedDayRequests.any((request) {
      final status = request.status.trim().toLowerCase();
      return status == 'pending' || status == 'approved';
    });
  }

  List<MaintenanceCompletionRequest> _filterCompletionsForCurrentUser(
    Iterable<MaintenanceCompletionRequest> requests,
  ) {
    return requests.where(_isCompletionRequestOwnedByCurrentUser).toList();
  }

  bool _isInventoryRequestOwnedByCurrentUser(InventoryRequestItem item) {
    final currentUserId = widget.currentUserId;
    if (currentUserId != null && item.requestedBy == currentUserId) {
      return true;
    }

    final normalizedCurrentName =
        widget.currentUserName?.trim().toLowerCase() ?? '';
    final normalizedRequestedByName = item.requestedByName.trim().toLowerCase();
    if (normalizedCurrentName.isEmpty || normalizedRequestedByName.isEmpty) {
      return false;
    }

    return normalizedCurrentName == normalizedRequestedByName;
  }

  bool get _hasBlockingCompletionForCurrentUser {
    // Only block stock requests when there is a currently active maintenance
    // event. Outside of maintenance days there should be no restriction.
    final activeEventIds = _events
        .where((e) => e.isActiveStatus)
        .map((e) => e.id)
        .toSet();

    if (activeEventIds.isEmpty) return false;

    final userCompletionRequests = _filterCompletionsForCurrentUser(
      _completionRequests,
    );
    return userCompletionRequests.any((request) {
      if (!activeEventIds.contains(request.event)) return false;
      final status = request.status.trim().toLowerCase();
      return status == 'pending' || status == 'approved';
    });
  }

  Future<void> _refreshCompletionApprovalEventLookupSilently() async {
    try {
      final allEvents = await _withApiLoader(
        MaintenanceService.fetchMaintenanceEvents,
      );
      if (!mounted) return;

      setState(() {
        _completionEventAssignedGatById
          ..clear()
          ..addEntries(
            allEvents.map((event) => MapEntry(event.id, event.assignedGat)),
          );
      });
    } catch (_) {
      // Keep completion list usable even if lookup refresh fails.
    }
  }

  Future<void> _actOnEntry(DholMaintenanceEntry item, String action) async {
    if (!widget.canManageInventory) {
      _showSnack('You are not allowed to approve or reject stock requests.');
      return;
    }

    final noteController = TextEditingController();
    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            '${action == 'approve' ? 'Approve' : 'Reject'} Maintenance Entry',
          ),
          content: TextField(
            controller: noteController,
            decoration: const InputDecoration(
              labelText: 'Approver Note (optional)',
            ),
            maxLines: 2,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
              ),
              child: Text(action == 'approve' ? 'Approve' : 'Reject'),
            ),
          ],
        );
      },
    );

    if (shouldSubmit != true) {
      noteController.dispose();
      return;
    }

    try {
      final response = await _withApiLoader(
        () => MaintenanceService.actOnEntry(
          entryId: item.id,
          action: action,
          approverNote: noteController.text.trim(),
        ),
      );
      _showSnack(response['message']?.toString() ?? 'Entry updated.');
      await _loadEntries();
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      noteController.dispose();
    }
  }

  Future<void> _showSnack(String message) async {
    if (!mounted) return;

    final trimmed = message.replaceFirst('Exception: ', '').trim();
    final closedNormalized = trimmed.toLowerCase();
    final displayMessage =
        closedNormalized.contains('maintenance event is closed')
        ? 'Maintenance event is closed.'
        : trimmed;

    final normalized = displayMessage.toLowerCase();
    final isMaintenanceAnalysisAccessMessage =
        normalized.contains('maintenance analysis') &&
        normalized.contains('pathak admin') &&
        (normalized.contains('maintenance admin') ||
            normalized.contains('maintacne admin'));
    if (isMaintenanceAnalysisAccessMessage) {
      return;
    }

    // On web, async callbacks can fire while this route is no longer current.
    // Avoid touching Scaffold/Overlay in that state to prevent engine asserts.
    if (kIsWeb) {
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        return;
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Message'),
        content: Text(displayMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _normalizeStartMaintenanceErrorMessage(String rawMessage) {
    final trimmed = rawMessage.replaceFirst('Exception: ', '').trim();
    final normalized = trimmed.toLowerCase();
    if (normalized.contains('maintenance event is closed')) {
      return 'Maintenance event is closed.';
    }
    if (normalized.contains('no active maintenance event found')) {
      return 'No active maintenance event available.';
    }
    if (normalized.contains('maintenance event is not active')) {
      return 'Maintenance event is no longer active.';
    }
    return trimmed;
  }

  Future<T> _withApiLoader<T>(Future<T> Function() action) async {
    if (mounted) {
      setState(() {
        _activeApiCallCount += 1;
      });
    }

    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() {
          if (_activeApiCallCount > 0) {
            _activeApiCallCount -= 1;
          }
        });
      }
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green.shade700;
      case 'rejected':
        return Colors.red.shade700;
      case 'closed':
        return Colors.blueGrey.shade700;
      default:
        return Colors.orange.shade700;
    }
  }

  String _normalizeDholStatus(String value) {
    return value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
  }

  String _dholStatusLabel(String value) {
    switch (_normalizeDholStatus(value)) {
      case 'good_condition':
        return 'Good Condition';
      case 'under_maintenance':
        return 'Under Maintenance';
      case 'damaged':
      default:
        return 'Damaged';
    }
  }

  Future<void> _createDholRange() async {
    final startText = _dholRangeStartController.text.trim();
    final endText = _dholRangeEndController.text.trim();
    final startNumber = int.tryParse(startText);
    final endNumber = int.tryParse(endText);

    if (startNumber == null || endNumber == null) {
      await _showSnack('Start Number and End Number must be valid numbers.');
      return;
    }
    if (startNumber <= 0 || endNumber <= 0) {
      await _showSnack('Start Number and End Number must be greater than 0.');
      return;
    }
    if (startNumber > endNumber) {
      await _showSnack(
        'Start Number must be less than or equal to End Number.',
      );
      return;
    }

    setState(() {
      _isCreatingDholRange = true;
    });

    try {
      final response = await _withApiLoader(
        () => MaintenanceService.createDholRange(
          startNumber: startNumber,
          endNumber: endNumber,
        ),
      );

      if (!mounted) return;
      _dholRangeStartController.clear();
      _dholRangeEndController.clear();
      await _showSnack(
        response['message']?.toString() ?? 'Dhol range created successfully.',
      );
      await _loadPathakDhols();
    } catch (e) {
      await _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingDholRange = false;
        });
      }
    }
  }

  Future<void> _confirmAndUpdateDholStatus(
    PathakDhol item,
    String nextStatus,
  ) async {
    final normalizedNext = _normalizeDholStatus(nextStatus);
    if (item.normalizedStatus == normalizedNext) {
      return;
    }

    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Status Change'),
        content: Text(
          'Change Dhol #${item.dholNumber} status to ${_dholStatusLabel(normalizedNext)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              foregroundColor: AppColors.primaryMaroon,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (shouldProceed != true) {
      return;
    }

    setState(() {
      _updatingDholStatusIds.add(item.id);
    });

    try {
      final response = await _withApiLoader(
        () => MaintenanceService.updatePathakDholStatus(
          dholId: item.id,
          status: normalizedNext,
        ),
      );
      if (!mounted) return;
      await _showSnack(
        response['message']?.toString() ?? 'Dhol status updated successfully.',
      );
      await _loadPathakDhols();
    } catch (e) {
      await _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _updatingDholStatusIds.remove(item.id);
        });
      }
    }
  }

  Widget _buildFilterRow({
    required String selected,
    required ValueChanged<String> onChanged,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: MaintenanceService.statuses.map((status) {
        final isSelected = selected == status;
        return ChoiceChip(
          label: Text(
            status.toUpperCase(),
            style: TextStyle(
              color: isSelected ? AppColors.primaryMaroon : Colors.black87,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          selected: isSelected,
          selectedColor: AppColors.primaryMaroon.withValues(alpha: 0.14),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isSelected ? AppColors.primaryMaroon : Colors.black26,
            ),
          ),
          showCheckmark: false,
          onSelected: (_) => onChanged(status),
        );
      }).toList(),
    );
  }

  Widget _buildDholRangeManagementTab() {
    return RefreshIndicator(
      onRefresh: _loadPathakDhols,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dhol Range Management',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Define a start and end number to generate pathak dhol records.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final useRow = constraints.maxWidth >= 640;
                      if (useRow) {
                        return Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _dholRangeStartController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Start Number',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _dholRangeEndController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'End Number',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          TextField(
                            controller: _dholRangeStartController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Start Number',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _dholRangeEndController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'End Number',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _isCreatingDholRange ? null : _createDholRange,
                      style: ElevatedButton.styleFrom(
                        foregroundColor: AppColors.primaryMaroon,
                      ),
                      icon: _isCreatingDholRange
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_circle_outline),
                      label: const Text('Create Dhol Range'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Current Dhol Count'),
              subtitle: Text(
                '${_pathakDhols.length} dhol records available',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: IconButton(
                tooltip: 'Refresh dhol list',
                onPressed: _loadPathakDhols,
                icon: const Icon(Icons.refresh),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDholStatusManagementTab() {
    final searchQuery = _dholSearchController.text.trim().toLowerCase();
    final filtered =
        _pathakDhols.where((item) {
          final matchesSearch = searchQuery.isEmpty
              ? true
              : item.dholNumber.toLowerCase().contains(searchQuery);
          final matchesStatus = _dholStatusFilter == 'all'
              ? true
              : item.normalizedStatus == _dholStatusFilter;
          return matchesSearch && matchesStatus;
        }).toList()..sort((a, b) {
          final left = int.tryParse(a.dholNumber);
          final right = int.tryParse(b.dholNumber);
          if (left != null && right != null) {
            return left.compareTo(right);
          }
          return a.dholNumber.compareTo(b.dholNumber);
        });

    return RefreshIndicator(
      onRefresh: _loadPathakDhols,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _dholSearchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search by Dhol Number',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _dholSearchController.text.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _dholSearchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _dholStatusFilter,
                    decoration: const InputDecoration(
                      labelText: 'Filter by Status',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('All')),
                      ..._dholStatusValues.map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(_dholStatusLabel(status)),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _dholStatusFilter = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text('No dhol records found for this filter.'),
              ),
            )
          else
            ...filtered.map((item) {
              final isUpdating = _updatingDholStatusIds.contains(item.id);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 760;

                      final detail = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dhol #${item.dholNumber}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Current Status: ${_dholStatusLabel(item.normalizedStatus)}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      );

                      final actions = Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _dholStatusValues.map((status) {
                          final isCurrent = item.normalizedStatus == status;
                          return OutlinedButton(
                            onPressed: isCurrent || isUpdating
                                ? null
                                : () =>
                                      _confirmAndUpdateDholStatus(item, status),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primaryMaroon,
                            ),
                            child: Text(
                              isCurrent
                                  ? '${_dholStatusLabel(status)} (Current)'
                                  : _dholStatusLabel(status),
                            ),
                          );
                        }).toList(),
                      );

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: detail),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 5,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: actions,
                              ),
                            ),
                            if (isUpdating)
                              const Padding(
                                padding: EdgeInsets.only(left: 8, top: 2),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [detail, const SizedBox(height: 10), actions],
                      );
                    },
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  String _instrumentMaintenanceStatusLabel(String status) {
    switch (status
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_')) {
      case 'pending_approval':
      case 'pending':
      case 'submitted':
        return 'Pending Approval';
      case 'under_maintenance':
        return 'Under Maintenance';
      case 'in_progress':
        return 'In Progress';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'active':
      case 'started':
      default:
        return 'Active';
    }
  }

  int _completionRequestTimestamp(MaintenanceCompletionRequest request) {
    final updated = DateTime.tryParse(request.updatedAt);
    if (updated != null) {
      return updated.millisecondsSinceEpoch;
    }

    final created = DateTime.tryParse(request.createdAt);
    if (created != null) {
      return created.millisecondsSinceEpoch;
    }

    return request.id;
  }

  bool _isCompletionForInstrumentMaintenance(
    MaintenanceCompletionRequest request,
    PathakInstrumentMaintenance maintenance,
  ) {
    final requestMaintenanceId = request.maintenanceId;
    if (requestMaintenanceId != null && requestMaintenanceId > 0) {
      return requestMaintenanceId == maintenance.maintenanceId;
    }

    return false;
  }

  PathakInstrumentMaintenance? _currentUserMaintenanceForEvent(
    MaintenanceEvent event,
  ) {
    final eventDay = event.parsedEventDate;
    final matches = _activeInstrumentMaintenances.where((maintenance) {
      if (!_isInstrumentMaintenanceParticipant(maintenance)) {
        return false;
      }

      if (maintenance.maintenanceEventId != null) {
        return maintenance.maintenanceEventId == event.id;
      }

      if (maintenance.linkedEventDay != null && eventDay != null) {
        return maintenance.linkedEventDay == eventDay;
      }

      return false;
    }).toList();

    if (matches.isEmpty) {
      return null;
    }

    matches.sort((left, right) {
      final leftStarted = DateTime.tryParse(left.startedAt);
      final rightStarted = DateTime.tryParse(right.startedAt);
      if (leftStarted == null && rightStarted == null) {
        return right.maintenanceId.compareTo(left.maintenanceId);
      }
      if (leftStarted == null) return 1;
      if (rightStarted == null) return -1;
      return rightStarted.compareTo(leftStarted);
    });

    return matches.first;
  }

  String _effectiveInstrumentMaintenanceStatus(
    PathakInstrumentMaintenance maintenance,
  ) {
    final matchingRequests =
        _completionRequests
            .where(
              (request) =>
                  _isCompletionForInstrumentMaintenance(request, maintenance),
            )
            .toList()
          ..sort(
            (left, right) => _completionRequestTimestamp(
              right,
            ).compareTo(_completionRequestTimestamp(left)),
          );

    if (matchingRequests.isEmpty) {
      return maintenance.normalizedStatus;
    }

    final completionStatus = matchingRequests.first.normalizedStatus;
    if (completionStatus == 'pending') {
      return 'pending_approval';
    }

    if (completionStatus == 'approved' || completionStatus == 'rejected') {
      return completionStatus;
    }

    return maintenance.normalizedStatus;
  }

  bool _isInstrumentMaintenanceParticipant(PathakInstrumentMaintenance item) {
    final currentUserId = widget.currentUserId;
    if (currentUserId != null &&
        item.participants.any(
          (participant) => participant.userId == currentUserId,
        )) {
      return true;
    }

    final normalizedCurrentName =
        widget.currentUserName?.trim().toLowerCase() ?? '';
    if (normalizedCurrentName.isEmpty) {
      return false;
    }

    return item.participants.any(
      (participant) =>
          participant.fullName.trim().toLowerCase() == normalizedCurrentName,
    );
  }

  bool _canSubmitInstrumentMaintenanceItem(PathakInstrumentMaintenance item) {
    final normalizedStatus = _effectiveInstrumentMaintenanceStatus(item);
    return _isInstrumentMaintenanceParticipant(item) &&
        !_hasPendingStockRequestForMaintenance(item.maintenanceId, _requests) &&
        normalizedStatus != 'pending_approval' &&
        normalizedStatus != 'pending' &&
        normalizedStatus != 'submitted' &&
        normalizedStatus != 'approved' &&
        normalizedStatus != 'rejected';
  }

  bool _isCurrentUserMaintenancePartner(CheckedInMaintenancePartner partner) {
    final currentUserId = widget.currentUserId;
    if (currentUserId != null && partner.userId == currentUserId) {
      return true;
    }

    final normalizedCurrentName =
        widget.currentUserName?.trim().toLowerCase() ?? '';
    if (normalizedCurrentName.isNotEmpty &&
        partner.fullName.trim().toLowerCase() == normalizedCurrentName) {
      return true;
    }

    return false;
  }

  String _completionParticipantDisplay(
    InstrumentMaintenanceParticipant participant,
  ) {
    final name = participant.fullName.trim();
    final phone = participant.phone.trim();

    if (name.isNotEmpty && phone.isNotEmpty) {
      return '$name ($phone)';
    }
    if (name.isNotEmpty) {
      return name;
    }
    return phone;
  }

  String _completionParticipantsText(
    List<InstrumentMaintenanceParticipant> participants,
  ) {
    return participants
        .map(_completionParticipantDisplay)
        .where((value) => value.isNotEmpty)
        .join(', ');
  }

  bool _matchesCompletionEvent(
    InventoryRequestItem request,
    MaintenanceCompletionRequest completion,
  ) {
    final requestMaintenanceId = request.maintenanceId;
    final completionMaintenanceId = completion.maintenanceId;
    if (requestMaintenanceId == null || completionMaintenanceId == null) {
      return false;
    }

    return requestMaintenanceId == completionMaintenanceId;
  }

  List<CompletionUsedItem> _resolvedCompletionUsedItems(
    MaintenanceCompletionRequest completion,
  ) {
    if (completion.approvedStockUsed.isNotEmpty) {
      return completion.approvedStockUsed;
    }

    if (completion.usedItems.isNotEmpty) {
      return completion.usedItems;
    }

    final approvedRequests = _requests.where((request) {
      final status = request.normalizedStatus.trim().toLowerCase();
      if (status != 'approved') {
        return false;
      }

      return _matchesCompletionEvent(request, completion);
    }).toList();

    if (approvedRequests.isEmpty) {
      return <CompletionUsedItem>[];
    }

    final usedItemByInventoryId = <int, CompletionUsedItem>{};
    for (final request in approvedRequests) {
      final existing = usedItemByInventoryId[request.inventoryItem];
      if (existing == null) {
        usedItemByInventoryId[request.inventoryItem] = CompletionUsedItem(
          id: request.id,
          inventoryItem: request.inventoryItem,
          inventoryItemName: request.inventoryItemName,
          quantityUsed: request.requestedQuantity,
          requestedByName: request.requestedByName,
          status: 'approved',
          quantityBeforeUpdate: null,
          quantityAfterUpdate: null,
        );
        continue;
      }

      usedItemByInventoryId[request.inventoryItem] = CompletionUsedItem(
        id: existing.id,
        inventoryItem: existing.inventoryItem,
        inventoryItemName: existing.inventoryItemName,
        quantityUsed: existing.quantityUsed + request.requestedQuantity,
        requestedByName: existing.requestedByName,
        status: 'approved',
        quantityBeforeUpdate: existing.quantityBeforeUpdate,
        quantityAfterUpdate: existing.quantityAfterUpdate,
      );
    }

    return usedItemByInventoryId.values.toList();
  }

  Future<Set<int>?> _openMaintenancePartnerSelector({
    required BuildContext parentContext,
    required Set<int> selectedIds,
  }) async {
    if (!parentContext.mounted) {
      return null;
    }

    final partners =
        List<CheckedInMaintenancePartner>.from(_eligibleMaintenancePartners)
          ..removeWhere(_isCurrentUserMaintenancePartner)
          ..sort(
            (a, b) =>
                a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
          );
    final searchController = TextEditingController();

    if (kIsWeb) {
      final route = ModalRoute.of(parentContext);
      if (route != null && !route.isCurrent) {
        searchController.dispose();
        return null;
      }
    }

    final selected = await showDialog<Set<int>>(
      context: parentContext,
      useRootNavigator: false,
      builder: (dialogContext) {
        final working = Set<int>.from(selectedIds);
        var searchQuery = '';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredPartners = partners.where((partner) {
              final query = searchQuery.trim().toLowerCase();
              if (query.isEmpty) return true;
              final name = partner.fullName.toLowerCase();
              return name.contains(query);
            }).toList();

            return AlertDialog(
              title: const Text('Select Partners'),
              content: SizedBox(
                width: 560,
                height: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        labelText: 'Search by name',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          searchQuery = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: filteredPartners.isEmpty
                          ? const Center(
                              child: Text('No eligible partners found.'),
                            )
                          : Scrollbar(
                              child: ListView.builder(
                                itemCount: filteredPartners.length,
                                itemBuilder: (context, index) {
                                  final partner = filteredPartners[index];
                                  final isSelected = working.contains(
                                    partner.userId,
                                  );
                                  final instrument = partner.instrument.trim();
                                  return CheckboxListTile(
                                    value: isSelected,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: Text(partner.fullName),
                                    subtitle: instrument.isNotEmpty
                                        ? Text(instrument)
                                        : null,
                                    onChanged: (value) {
                                      setDialogState(() {
                                        if (value == true) {
                                          working.add(partner.userId);
                                        } else {
                                          working.remove(partner.userId);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(working),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    searchController.dispose();
    return selected;
  }

  Future<void> _openStartInstrumentMaintenanceDialog() async {
    final latestClosed = await _isLatestMaintenanceEventClosed();
    if (latestClosed) {
      await _showSnack('Maintenance event is closed.');
      return;
    }

    if (_damagedMaintenanceDhols.isEmpty) {
      await _loadDamagedMaintenanceDhols();
    }
    if (_eligibleMaintenancePartners.isEmpty) {
      await _loadEligibleMaintenancePartners();
    }
    if (!mounted) return;

    int? selectedDholId;
    final selectedPartnerIds = <int>{};
    String? successMessage;
    final visiblePartners = _eligibleMaintenancePartners
        .where((partner) => !_isCurrentUserMaintenancePartner(partner))
        .toList();
    final visiblePartnerIds = visiblePartners
        .map((partner) => partner.userId)
        .toSet();

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var isSubmitting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Start Maintenance'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 520,
                  maxHeight: 520,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: selectedDholId,
                        decoration: const InputDecoration(
                          labelText: 'Dhol Number',
                          border: OutlineInputBorder(),
                        ),
                        items: _damagedMaintenanceDhols
                            .map(
                              (item) => DropdownMenuItem<int>(
                                value: item.id,
                                child: Text('Dhol #${item.dholNumber}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedDholId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Partners (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedPartnerIds.isEmpty
                                  ? 'No partners selected'
                                  : '${selectedPartnerIds.length} partner(s) selected',
                              style: const TextStyle(color: Colors.black54),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: visiblePartners
                                  .where(
                                    (partner) => selectedPartnerIds.contains(
                                      partner.userId,
                                    ),
                                  )
                                  .map(
                                    (partner) =>
                                        Chip(label: Text(partner.fullName)),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                if (!dialogContext.mounted) return;
                                final selected =
                                    await _openMaintenancePartnerSelector(
                                      parentContext: dialogContext,
                                      selectedIds: selectedPartnerIds,
                                    );
                                if (selected == null ||
                                    !dialogContext.mounted) {
                                  return;
                                }
                                setDialogState(() {
                                  selectedPartnerIds
                                    ..clear()
                                    ..addAll(
                                      selected.where(
                                        (id) => visiblePartnerIds.contains(id),
                                      ),
                                    );
                                });
                              },
                              icon: const Icon(Icons.group_add_outlined),
                              label: const Text('Select Partners'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (selectedDholId == null) {
                            await _showSnack('Dhol Number is required.');
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                          });

                          try {
                            final response = await _withApiLoader(
                              () =>
                                  MaintenanceService.startInstrumentMaintenance(
                                    instrumentId: selectedDholId!,
                                    participantUserIds: selectedPartnerIds
                                        .where(
                                          (id) =>
                                              visiblePartnerIds.contains(id),
                                        )
                                        .toList(),
                                  ),
                            );
                            successMessage =
                                response['message']?.toString() ??
                                'Maintenance started.';
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                            }
                            await _showSnack(
                              _normalizeStartMaintenanceErrorMessage(
                                e.toString(),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                  child: const Text('Start Maintenance'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created == true) {
      await _showSnack(successMessage ?? 'Maintenance started.');
      await _loadInstrumentMaintenanceData();
    }
  }

  Future<void> _openSubmitInstrumentMaintenanceDialog(
    PathakInstrumentMaintenance item,
  ) async {
    final latestClosed = await _isLatestMaintenanceEventClosed();
    if (latestClosed) {
      await _showSnack('Maintenance event is closed.');
      return;
    }

    final detail = await _withApiLoader(
      () => MaintenanceService.fetchInstrumentMaintenanceDetail(item.id),
    );
    if (!mounted) return;

    List<InventoryItem> dialogInventory = List<InventoryItem>.from(_inventory);
    List<InventoryRequestItem> allRequests = List<InventoryRequestItem>.from(
      _requests,
    );

    if (dialogInventory.isEmpty) {
      try {
        dialogInventory = await _withApiLoader(
          MaintenanceService.fetchInventory,
        );
      } catch (_) {
        dialogInventory = <InventoryItem>[];
      }
    }

    if (allRequests.isEmpty) {
      try {
        allRequests = await _withApiLoader(
          MaintenanceService.fetchInventoryRequests,
        );
      } catch (_) {
        allRequests = <InventoryRequestItem>[];
      }
    }

    final hasPendingStockRequest = _hasPendingStockRequestForMaintenance(
      detail.maintenanceId,
      allRequests,
    );
    if (hasPendingStockRequest) {
      await _showSnack(
        'Some stock requests are still pending approval. Please wait for approval or rejection before submitting maintenance.',
      );
      return;
    }

    final workPerformedController = TextEditingController(
      text: detail.workPerformed,
    );
    final remarksController = TextEditingController(text: detail.remarks);
    final participantsText = detail.participants
        .map((participant) => participant.fullName.trim())
        .where((name) => name.isNotEmpty)
        .join(', ');
    String? successMessage;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var isSubmitting = false;
        var canSubmit = workPerformedController.text.trim().isNotEmpty;
        String? submitErrorMessage;

        List<InventoryRequestItem> eventScopedMaintenanceStockRequests() {
          final approvedOrPendingScoped = List<InventoryRequestItem>.from(
            allRequests,
          );
          final explicitMaintenanceId = detail.maintenanceId;
          final explicitEventId = detail.maintenanceEventId;
          final explicitEventDay = detail.linkedEventDay;
          if (explicitMaintenanceId == 0 &&
              explicitEventId == null &&
              explicitEventDay == null) {
            return approvedOrPendingScoped;
          }

          return approvedOrPendingScoped.where((request) {
            if (explicitMaintenanceId > 0 && request.maintenanceId != null) {
              return request.maintenanceId == explicitMaintenanceId;
            }

            if (explicitEventId != null && request.maintenanceEventId != null) {
              return request.maintenanceEventId == explicitEventId;
            }

            final linkedEventDay = request.linkedEventDay;
            if (linkedEventDay != null && explicitEventDay != null) {
              return linkedEventDay == explicitEventDay;
            }

            return false;
          }).toList();
        }

        List<CompletionUsedItemPreview> stockUsedPreviews() {
          if (detail.approvedStockUsed.isNotEmpty) {
            return detail.approvedStockUsed
                .map(
                  (item) => CompletionUsedItemPreview(
                    inventoryItemId: item.inventoryItem,
                    inventoryItemName: item.inventoryItemName,
                    quantityUsed: item.quantityUsed,
                  ),
                )
                .toList();
          }

          final approvedRequests = eventScopedMaintenanceStockRequests()
              .where((request) => request.normalizedStatus == 'approved')
              .toList();
          return buildCompletionUsedItems(approvedRequests);
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final autoStockUsedItems = stockUsedPreviews();

            return AlertDialog(
              title: Text('Submit Dhol #${detail.dholNumber} Maintenance'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 560,
                  maxHeight: 620,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Dhol Number',
                          border: OutlineInputBorder(),
                        ),
                        child: Text('Dhol #${detail.dholNumber}'),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Participants',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          participantsText.isEmpty ? '-' : participantsText,
                        ),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Maintenance Event',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          detail.maintenanceEventTitle.trim().isEmpty
                              ? '-'
                              : detail.maintenanceEventTitle,
                        ),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Event Date',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          detail.maintenanceEventDate.trim().isEmpty
                              ? '-'
                              : detail.maintenanceEventDate,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: workPerformedController,
                        minLines: 2,
                        maxLines: 4,
                        onChanged: (value) {
                          if (!dialogContext.mounted) {
                            return;
                          }
                          setDialogState(() {
                            canSubmit = value.trim().isNotEmpty;
                            submitErrorMessage = null;
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Work Performed',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: remarksController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Remarks',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Approved Stock Used',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (autoStockUsedItems.isEmpty)
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'No approved stock usage returned for this maintenance.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      else
                        ...autoStockUsedItems.map((usedItem) {
                          final inventoryMatch = dialogInventory
                              .where(
                                (inv) => inv.id == usedItem.inventoryItemId,
                              )
                              .toList();
                          final availableQty = inventoryMatch.isNotEmpty
                              ? inventoryMatch.first.quantityAvailable
                              : null;
                          final itemName =
                              usedItem.inventoryItemName.trim().isNotEmpty
                              ? usedItem.inventoryItemName.trim()
                              : 'Item #${usedItem.inventoryItemId}';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        itemName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        availableQty == null
                                            ? 'Used ${usedItem.quantityUsed}'
                                            : 'Used ${usedItem.quantityUsed} | Available $availableQty',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      if (submitErrorMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          submitErrorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: (!canSubmit || isSubmitting)
                      ? null
                      : () async {
                          setDialogState(() {
                            isSubmitting = true;
                            submitErrorMessage = null;
                          });

                          try {
                            final response =
                                await MaintenanceService.submitInstrumentMaintenance(
                                  maintenanceId: detail.maintenanceId,
                                  workPerformed: workPerformedController.text
                                      .trim(),
                                  remarks: remarksController.text.trim(),
                                );
                            _lastSubmittedCompletionRequestId = int.tryParse(
                              response['completion_request_id']?.toString() ??
                                  '',
                            );
                            successMessage =
                                response['message']?.toString() ??
                                'Maintenance submitted successfully.';
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (e) {
                            if (!dialogContext.mounted) {
                              return;
                            }
                            setDialogState(() {
                              isSubmitting = false;
                              submitErrorMessage = e.toString().replaceFirst(
                                'Exception: ',
                                '',
                              );
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                  child: const Text('Submit Maintenance'),
                ),
              ],
            );
          },
        );
      },
    );

    workPerformedController.dispose();
    remarksController.dispose();

    if (submitted == true) {
      await _showSnack(successMessage ?? 'Maintenance submitted successfully.');
      await Future.wait<void>([
        _loadInstrumentMaintenanceData(),
        _loadCompletionRequests(),
      ]);
      if (mounted && _lastSubmittedCompletionRequestId != null) {
        _tabController.animateTo(_completionTabIndexForCurrentUser());
      }
    }
  }

  Future<void> _openInstrumentMaintenanceDetail(
    PathakInstrumentMaintenance item, {
    bool openSubmitOnStart = false,
  }) async {
    setState(() {
      _loadingInstrumentMaintenanceDetailIds.add(item.id);
    });

    try {
      final detail = await _withApiLoader(
        () => MaintenanceService.fetchInstrumentMaintenanceDetail(item.id),
      );
      if (!mounted) return;
      _instrumentMaintenanceDetails[item.id] = detail;

      if (openSubmitOnStart && _canSubmitInstrumentMaintenanceItem(detail)) {
        await _openSubmitInstrumentMaintenanceDialog(detail);
        return;
      }

      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          final detailStatus = _effectiveInstrumentMaintenanceStatus(detail);
          final participantsText = detail.participants
              .map((participant) => participant.fullName)
              .where((name) => name.trim().isNotEmpty)
              .join(', ');
          final imageSection = (String title, List<String> images) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              if (images.isEmpty)
                const Text('-', style: TextStyle(color: Colors.black54))
              else
                ...images.map(
                  (image) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      image,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                ),
            ],
          );

          return AlertDialog(
            title: Text('Dhol #${detail.dholNumber} Maintenance'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Maintenance Event: ${detail.maintenanceEventTitle.trim().isEmpty ? '-' : detail.maintenanceEventTitle}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Event Date: ${detail.maintenanceEventDate.trim().isEmpty ? '-' : detail.maintenanceEventDate}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Status: ${_instrumentMaintenanceStatusLabel(detailStatus)}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Started By: ${detail.startedByName.isNotEmpty ? detail.startedByName : '-'}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Started At: ${detail.startedAt.isNotEmpty ? detail.startedAt : '-'}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Participants: ${participantsText.isEmpty ? '-' : participantsText}',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Work Performed: ${detail.workPerformed.trim().isEmpty ? '-' : detail.workPerformed}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Remarks: ${detail.remarks.trim().isEmpty ? '-' : detail.remarks}',
                    ),
                    if (detail.approverNote.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Approver Note: ${detail.approverNote}'),
                    ],
                    if (detail.rejectionRemarks.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Rejection Remarks: ${detail.rejectionRemarks}'),
                    ],
                    const SizedBox(height: 12),
                    imageSection('Before Images', detail.beforeImages),
                    const SizedBox(height: 10),
                    imageSection('After Images', detail.afterImages),
                  ],
                ),
              ),
            ),
            actions: [
              if (_canSubmitInstrumentMaintenanceItem(detail))
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop('submit'),
                  child: const Text('Submit Maintenance'),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );

      if (!mounted || action == null) return;
      if (action == 'submit') {
        await _openSubmitInstrumentMaintenanceDialog(detail);
      }
    } catch (e) {
      await _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loadingInstrumentMaintenanceDetailIds.remove(item.id);
        });
      }
    }
  }

  Future<void> _openMarkDholAsDamagedDialog() async {
    // Use the dedicated good-condition list (fetched via ?status=good_condition)
    // so this works for non-admin checked-in users too.
    final goodConditionDhols =
        List<PathakDhol>.from(_goodConditionDhols)
            .where((item) => !_todayMarkedDamagedDholIds.contains(item.id))
            .toList()
          ..sort((left, right) {
            final leftNumber = int.tryParse(left.dholNumber);
            final rightNumber = int.tryParse(right.dholNumber);
            if (leftNumber != null && rightNumber != null) {
              return leftNumber.compareTo(rightNumber);
            }
            return left.dholNumber.compareTo(right.dholNumber);
          });

    if (goodConditionDhols.isEmpty) {
      await _showSnack('No good condition dhol is available.');
      return;
    }

    int? selectedDholId;
    final remarksController = TextEditingController();

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var isSubmitting = false;
        String? validationMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Mark Dhol As Damaged'),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.7,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: selectedDholId,
                        decoration: const InputDecoration(
                          labelText: 'Dhol Number',
                          border: OutlineInputBorder(),
                        ),
                        items: goodConditionDhols
                            .map(
                              (item) => DropdownMenuItem<int>(
                                value: item.id,
                                child: Text('Dhol #${item.dholNumber}'),
                              ),
                            )
                            .toList(),
                        onChanged: isSubmitting
                            ? null
                            : (value) {
                                setDialogState(() {
                                  selectedDholId = value;
                                  validationMessage = null;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: remarksController,
                        minLines: 2,
                        maxLines: 4,
                        enabled: !isSubmitting,
                        decoration: const InputDecoration(
                          labelText: 'Damage Remarks (Optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (validationMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          validationMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 10),
                      const Text(
                        'Are you sure you want to mark this Dhol as damaged?',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          if (selectedDholId == null) {
                            setDialogState(() {
                              validationMessage = 'Please select a dhol.';
                            });
                            return;
                          }

                          isSubmitting = true;

                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                  child: const Text('Mark As Damaged'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSubmit != true) {
      remarksController.dispose();
      return;
    }

    final targetDholId = selectedDholId;
    remarksController.dispose();

    if (targetDholId == null) {
      return;
    }

    try {
      final attendanceState = await _currentAttendanceState();
      final isCheckedIn = attendanceState.$1;
      final isCheckedOut = attendanceState.$2;
      if (!isCheckedIn || isCheckedOut) {
        await _showSnack('Please check in first.');
        return;
      }

      final updateResult = await _withApiLoader(
        () => MaintenanceService.updatePathakDholStatus(
          dholId: targetDholId,
          status: 'damaged',
        ),
      );
      await _cacheTodayMarkedDamagedDhol(targetDholId);

      final message =
          updateResult['message']?.toString() ?? 'Dhol marked as damaged.';
      await _showSnack(message);
      await _withApiLoader(_loadInstrumentMaintenanceData);
    } catch (e) {
      await _showSnack(e.toString());
    }
  }

  Widget _buildInstrumentMaintenanceTab() {
    final sortedMaintenances = List<PathakInstrumentMaintenance>.from(
      _activeInstrumentMaintenances,
    )..sort((left, right) => right.startedAt.compareTo(left.startedAt));

    return RefreshIndicator(
      onRefresh: _loadInstrumentMaintenanceData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Report Dhol Damage',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Mark a good condition dhol as damaged when damage is observed.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        label: Text(
                          '${_goodConditionDhols.length} good condition dhol(s)',
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _isLoadingPathakDhols
                            ? null
                            : _openMarkDholAsDamagedDialog,
                        style: ElevatedButton.styleFrom(
                          foregroundColor: AppColors.primaryMaroon,
                        ),
                        icon: const Icon(Icons.report_problem_outlined),
                        label: const Text('Mark Dhol As Damaged'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _canReviewInstrumentMaintenances
                ? 'Active Maintenance'
                : 'My Active Maintenance',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_isLoadingActiveInstrumentMaintenances &&
              sortedMaintenances.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (sortedMaintenances.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(child: Text('No active dhol maintenance found.')),
            )
          else
            ...sortedMaintenances.map((item) {
              final isLoadingDetail = _loadingInstrumentMaintenanceDetailIds
                  .contains(item.id);
              final participantNames = item.participants
                  .map((participant) => participant.fullName)
                  .where((name) => name.trim().isNotEmpty)
                  .join(', ');

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: isLoadingDetail
                      ? null
                      : () => _openInstrumentMaintenanceDetail(item),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Dhol #${item.dholNumber}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (isLoadingDetail)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              Chip(
                                label: Text(
                                  _instrumentMaintenanceStatusLabel(
                                    _effectiveInstrumentMaintenanceStatus(item),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Started By: ${item.startedByName.isEmpty ? '-' : item.startedByName}',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Started At: ${item.startedAt.isEmpty ? '-' : item.startedAt}',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Participants: ${participantNames.isEmpty ? '-' : participantNames}',
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCategoryTab(String category) {
    final query = (_categorySearch[category] ?? '').trim().toLowerCase();
    final latestEventId = latestMaintenanceEventId(_events);
    final latestEvent = latestEventId == null
        ? null
        : _events.where((event) => event.id == latestEventId).firstOrNull;
    final isLatestEventClosed = latestEvent?.isClosedStatus ?? false;
    final shouldDisableRequestButton =
        !widget.canManageInventory &&
        (_hasBlockingCompletionForCurrentUser || isLatestEventClosed);
    final items = _inventory
        .where((item) => item.category.toLowerCase() == category)
        .where((item) {
          if (query.isEmpty) return true;
          final name = item.name.toLowerCase();
          final other = item.otherCategoryName.toLowerCase();
          return name.contains(query) || other.contains(query);
        })
        .toList();

    return RefreshIndicator(
      onRefresh: _loadInventory,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            onChanged: (value) {
              setState(() {
                _categorySearch[category] = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search stock name',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        setState(() {
                          _categorySearch[category] = '';
                        });
                      },
                      icon: const Icon(Icons.clear),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          if (widget.canManageInventory &&
              widget.embeddedAdminSection == 'approvals')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _openInventoryForm(preselectedCategory: category),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add Stock'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: Text('No items in this category.')),
            )
          else
            ...items.map(
              (item) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      if (item.otherCategoryName.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            item.otherCategoryName,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        'Available: ${item.quantityAvailable}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        alignment: WrapAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              if (widget.canManageInventory) {
                                _openUpdateStockForm(item);
                              } else {
                                _openStockUpdateProposalForm(item);
                              }
                            },
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Update Stock'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primaryMaroon,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: shouldDisableRequestButton
                                ? null
                                : () => _openSingleStockRequestForm(item),
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: const Text('Request Stock'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primaryMaroon,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                            ),
                          ),
                          if (widget.canManageInventory)
                            OutlinedButton.icon(
                              onPressed: () => _openRenameStockForm(item),
                              icon: const Icon(Icons.drive_file_rename_outline),
                              label: const Text('Rename Stock'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primaryMaroon,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          if (widget.canManageInventory)
                            OutlinedButton.icon(
                              onPressed: () => _confirmDeleteStock(item),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete Stock'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primaryMaroon,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMyRequestsTab() {
    final myRequests = _requests
        .where(_isInventoryRequestOwnedByCurrentUser)
        .toList();

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (myRequests.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text('No stock update proposals submitted yet.'),
              ),
            )
          else
            ...myRequests.map(
              (item) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.inventoryItemName} x${item.requestedQuantity}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(item.normalizedStatus.toUpperCase()),
                            labelStyle: TextStyle(
                              color: _statusColor(item.normalizedStatus),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Text('Proposed by: ${item.requestedByName}'),
                      if (item.note.trim().isNotEmpty)
                        Text('Reason: ${item.note}'),
                      if (item.adminNote.trim().isNotEmpty)
                        Text('Decision Note: ${item.adminNote}'),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRequestsTab() {
    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Text('Filter: ', style: Theme.of(context).textTheme.bodyMedium),
                Expanded(
                  child: _buildFilterRow(
                    selected: _requestStatusFilter,
                    onChanged: (status) {
                      setState(() {
                        _requestStatusFilter = status;
                      });
                      unawaited(_persistUiState());
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_requests.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: Text('No stock update proposals pending.')),
            )
          else
            ..._requests
                .where(
                  (r) => r.normalizedStatus.startsWith(_requestStatusFilter),
                )
                .map(
                  (item) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.inventoryItemName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Chip(
                                label: Text(
                                  item.normalizedStatus.toUpperCase(),
                                ),
                                labelStyle: TextStyle(
                                  color: _statusColor(item.normalizedStatus),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Proposed by: ${item.requestedByName}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Quantity to Add: ${item.requestedQuantity}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (item.note.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Reason: ${item.note}',
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ],
                          if (item.adminNote.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Decision Note: ${item.adminNote}',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (_isPendingInventoryRequest(item))
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      _actOnRequest(item, 'reject'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.primaryMaroon,
                                  ),
                                  child: const Text('Reject'),
                                ),
                                ElevatedButton(
                                  onPressed: () =>
                                      _actOnRequest(item, 'approve'),
                                  style: ElevatedButton.styleFrom(
                                    foregroundColor: AppColors.primaryMaroon,
                                  ),
                                  child: const Text('Approve'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildEventsTab() {
    final canCreateEvent = widget.canCreateMaintenanceEvents;
    final userCompletionRequests = _filterCompletionsForCurrentUser(
      _completionRequests,
    );
    final hasPendingStockRequestForUser = _requests
        .where(_isInventoryRequestOwnedByCurrentUser)
        .any(_isPendingInventoryRequest);

    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _eventStatusFilter,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'closed', child: Text('Closed')),
                    DropdownMenuItem(
                      value: 'completed',
                      child: Text('Completed'),
                    ),
                    DropdownMenuItem(
                      value: 'cancelled',
                      child: Text('Cancelled'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _eventStatusFilter = value;
                    });
                    unawaited(_persistUiState());
                    _loadEvents();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _eventScopeFilter,
                  decoration: const InputDecoration(labelText: 'Scope'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'pathak', child: Text('Pathak')),
                    DropdownMenuItem(value: 'gat', child: Text('Gat')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _eventScopeFilter = value;
                    });
                    unawaited(_persistUiState());
                    _loadEvents();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: now,
                      firstDate: DateTime(now.year - 2),
                      lastDate: DateTime(now.year + 2),
                    );
                    if (picked == null) return;
                    final dateString =
                        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                    setState(() {
                      _eventDateFilter = dateString;
                    });
                    unawaited(_persistUiState());
                    _loadEvents();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    _eventDateFilter.isEmpty ? 'Any Date' : _eventDateFilter,
                  ),
                ),
              ),
              if (_eventDateFilter.isNotEmpty)
                IconButton(
                  onPressed: () {
                    setState(() {
                      _eventDateFilter = '';
                    });
                    unawaited(_persistUiState());
                    _loadEvents();
                  },
                  icon: const Icon(Icons.clear),
                  color: AppColors.primaryMaroon,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (canCreateEvent)
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: _openCreateEventForm,
                style: ElevatedButton.styleFrom(
                  foregroundColor: AppColors.primaryMaroon,
                ),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Create Maintenance Day'),
              ),
            ),
          if (canCreateEvent) const SizedBox(height: 10),
          if (_events.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: Text('No maintenance events found.')),
            )
          else
            ..._events.map((event) {
              final isUserActionableEvent = isLatestActiveMaintenanceEvent(
                event,
                _events,
              );
              final hasPendingCompletion = userCompletionRequests.any(
                (item) =>
                    item.event == event.id &&
                    item.status.toLowerCase() == 'pending',
              );
              final hasApprovedCompletion = userCompletionRequests.any(
                (item) =>
                    item.event == event.id &&
                    item.status.toLowerCase() == 'approved',
              );

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(event.status.toUpperCase()),
                            labelStyle: TextStyle(
                              color: _statusColor(event.status),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (event.description.trim().isNotEmpty)
                        Text(
                          event.description,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      const SizedBox(height: 6),
                      Text('Date: ${event.eventDate}'),
                      if (event.assignedGatName.trim().isNotEmpty)
                        Text('Assigned Gat: ${event.assignedGatName}'),
                      if (event.isClosedStatus)
                        Text(
                          'Closed By: ${event.closedByName.trim().isEmpty ? '-' : event.closedByName}',
                        ),
                      if (event.isClosedStatus)
                        Text(
                          'Closed At: ${event.closedAt.trim().isEmpty ? '-' : event.closedAt}',
                        ),
                      if (widget.canCreateMaintenanceEvents &&
                          !event.isClosedStatus) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: () => _closeMaintenanceEvent(event),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                            ),
                            icon: const Icon(Icons.lock_outline),
                            label: const Text('Close Maintenance Event'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (isUserActionableEvent)
                        Align(
                          alignment: Alignment.centerRight,
                          child: hasPendingCompletion
                              ? OutlinedButton.icon(
                                  onPressed: null,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.orange,
                                  ),
                                  icon: const Icon(Icons.hourglass_top),
                                  label: const Text('Pending'),
                                )
                              : hasApprovedCompletion
                              ? OutlinedButton.icon(
                                  onPressed: null,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.green,
                                  ),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Approved'),
                                )
                              : hasPendingStockRequestForUser
                              ? OutlinedButton.icon(
                                  onPressed: null,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.orange,
                                  ),
                                  icon: const Icon(Icons.inventory_2_outlined),
                                  label: const Text('Stock Request Pending'),
                                )
                              : OutlinedButton.icon(
                                  onPressed: () =>
                                      _openCompletionRequestForm(event),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primaryMaroon,
                                  ),
                                  icon: const Icon(
                                    Icons.assignment_turned_in_outlined,
                                  ),
                                  label: const Text('Submit'),
                                ),
                        ),
                      if (!isUserActionableEvent)
                        Text(
                          event.isClosedStatus
                              ? 'Maintenance Closed. Event is read-only.'
                              : 'Closed for users. This maintenance day remains open only until a newer maintenance day is created.',
                          style: const TextStyle(color: Colors.black54),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCompletionRequestsTab() {
    final filtered = _completionRequests
        .where(
          (item) =>
              item.status.toLowerCase().startsWith(_completionStatusFilter),
        )
        .toList();

    final visibleCompletionRequests = filtered
        .where(_canViewCompletionRequestItem)
        .toList();

    final eventTitleById = <int, String>{};
    for (final request in visibleCompletionRequests) {
      final title = request.eventTitle.trim();
      if (title.isEmpty) continue;
      eventTitleById.putIfAbsent(request.event, () => title);
    }

    final eventOptions =
        eventTitleById.entries
            .map(
              (entry) => DropdownMenuItem<int?>(
                value: entry.key,
                child: Text(entry.value),
              ),
            )
            .toList()
          ..sort(
            (a, b) => (a.child as Text).data!.toLowerCase().compareTo(
              (b.child as Text).data!.toLowerCase(),
            ),
          );

    return RefreshIndicator(
      onRefresh: _loadCompletionRequests,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _completionEventIdFilter,
                  decoration: const InputDecoration(labelText: 'Event'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All Events'),
                    ),
                    ...eventOptions,
                  ],
                  onChanged: (value) {
                    setState(() {
                      _completionEventIdFilter = value;
                    });
                    unawaited(_persistUiState());
                    _loadCompletionRequests();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: now,
                      firstDate: DateTime(now.year - 2),
                      lastDate: DateTime(now.year + 2),
                    );
                    if (picked == null) return;
                    final dateString =
                        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                    setState(() {
                      _completionEventDateFilter = dateString;
                    });
                    unawaited(_persistUiState());
                    _loadCompletionRequests();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryMaroon,
                  ),
                  icon: const Icon(Icons.event_note_outlined),
                  label: Text(
                    _completionEventDateFilter.isEmpty
                        ? 'Any Date'
                        : _completionEventDateFilter,
                  ),
                ),
              ),
              if (_completionEventDateFilter.isNotEmpty)
                IconButton(
                  onPressed: () {
                    setState(() {
                      _completionEventDateFilter = '';
                    });
                    unawaited(_persistUiState());
                    _loadCompletionRequests();
                  },
                  icon: const Icon(Icons.clear),
                  color: AppColors.primaryMaroon,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Text('Filter: ', style: Theme.of(context).textTheme.bodyMedium),
                Expanded(
                  child: _buildFilterRow(
                    selected: _completionStatusFilter,
                    onChanged: (status) {
                      setState(() {
                        _completionStatusFilter = status;
                      });
                      unawaited(_persistUiState());
                      _loadCompletionRequests();
                    },
                  ),
                ),
              ],
            ),
          ),
          if (visibleCompletionRequests.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: Text('No completion requests found.')),
            )
          else
            ...visibleCompletionRequests.map((item) {
              final usedItems = _resolvedCompletionUsedItems(item);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.eventTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(item.status.toUpperCase()),
                            labelStyle: TextStyle(
                              color: _statusColor(item.status),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Submitted by: ${item.submittedByName.isNotEmpty ? item.submittedByName : '-'}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      Text(
                        'Event Date: ${item.eventDate}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 6),
                      if (item.maintenanceId != null ||
                          item.dholNumber.trim().isNotEmpty ||
                          item.participants.isNotEmpty ||
                          item.workPerformed.trim().isNotEmpty ||
                          item.remarks.trim().isNotEmpty) ...[
                        const Text(
                          'Instrument Maintenance',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        if (item.maintenanceId != null)
                          Text('Maintenance ID: #${item.maintenanceId}'),
                        if (item.dholNumber.trim().isNotEmpty)
                          Text('Dhol Number: Dhol #${item.dholNumber}'),
                        Text(
                          'Participants: ${_completionParticipantsText(item.participants).isEmpty ? '-' : _completionParticipantsText(item.participants)}',
                        ),
                        Text(
                          'Work Performed: ${item.workPerformed.trim().isNotEmpty ? item.workPerformed : item.workNotes}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          'Remarks: ${item.remarks.trim().isNotEmpty ? item.remarks : '-'}',
                        ),
                      ] else
                        Text(
                          'Work: ${item.workNotes}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      if (item.approverNote.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Approver Note: ${item.approverNote}',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        'Approved Stock Used',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      if (usedItems.isEmpty)
                        const Text(
                          'No stock items recorded.',
                          style: TextStyle(color: Colors.black54),
                        )
                      else
                        ...usedItems.map(
                          (usedItem) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '${usedItem.inventoryItemName.trim().isNotEmpty ? usedItem.inventoryItemName.trim() : 'Item'} × ${usedItem.quantityUsed}${usedItem.requestedByName.trim().isNotEmpty ? ' • ${usedItem.requestedByName.trim()}' : ''}',
                            ),
                          ),
                        ),
                      if (_canApproveCompletionRequestItem(item) &&
                          item.status.toLowerCase() == 'pending') ...[
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  _actOnCompletionRequest(item, 'reject'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primaryMaroon,
                              ),
                              child: const Text('Reject'),
                            ),
                            ElevatedButton(
                              onPressed: () =>
                                  _actOnCompletionRequest(item, 'approve'),
                              style: ElevatedButton.styleFrom(
                                foregroundColor: AppColors.primaryMaroon,
                              ),
                              child: const Text('Approve'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildEntriesTab() {
    return RefreshIndicator(
      onRefresh: _loadEntries,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Text('Filter: ', style: Theme.of(context).textTheme.bodyMedium),
                Expanded(
                  child: _buildFilterRow(
                    selected: _entryStatusFilter,
                    onChanged: (status) {
                      setState(() {
                        _entryStatusFilter = status;
                      });
                      unawaited(_persistUiState());
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_entries.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: Text('No maintenance entries.')),
            )
          else
            ..._entries
                .where(
                  (e) => e.status.toLowerCase().startsWith(_entryStatusFilter),
                )
                .map(
                  (item) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Dhol #${item.dholNumber}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Chip(
                                label: Text(item.status.toUpperCase()),
                                labelStyle: TextStyle(
                                  color: _statusColor(item.status),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Maintained by: ${item.maintainedByName}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Work: ${item.workNotes}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          if (item.approverNote.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Approver Note: ${item.approverNote}',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (widget.canApproveEntries &&
                              item.status.toLowerCase() == 'pending')
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: () => _actOnEntry(item, 'reject'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.primaryMaroon,
                                  ),
                                  child: const Text('Reject'),
                                ),
                                ElevatedButton(
                                  onPressed: () => _actOnEntry(item, 'approve'),
                                  style: ElevatedButton.styleFrom(
                                    foregroundColor: AppColors.primaryMaroon,
                                  ),
                                  child: const Text('Approve'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildAnalysisTab() {
    final analysis = _analysis;
    final categorySummaries = {
      for (final category
          in analysis?.categories ?? <MaintenanceAnalysisCategory>[])
        category.category.toLowerCase(): category,
    };

    final availableCategories = _allCategoryTabs.where((category) {
      return _inventory.any(
            (item) => item.category.toLowerCase() == category,
          ) ||
          categorySummaries.containsKey(category);
    }).toList();

    final eventsWithUsedStock =
        _events.where((event) => event.usedItems.isNotEmpty).toList()
          ..sort((a, b) {
            final left = DateTime.tryParse(a.eventDate);
            final right = DateTime.tryParse(b.eventDate);
            if (left == null && right == null) return 0;
            if (left == null) return 1;
            if (right == null) return -1;
            return right.compareTo(left);
          });

    final availableAnalysisEventOptions = eventsWithUsedStock
        .map(
          (event) => DropdownMenuItem<int?>(
            value: event.id,
            child: Text('${event.title} (${event.eventDate})'),
          ),
        )
        .toList();

    final selectedAnalysisEventStillExists = eventsWithUsedStock.any(
      (event) => event.id == _analysisEventIdFilter,
    );

    final filteredEventsWithUsedStock = _analysisEventIdFilter == null
        ? eventsWithUsedStock
        : eventsWithUsedStock
              .where((event) => event.id == _analysisEventIdFilter)
              .toList();

    if (analysis == null && _inventory.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAnalysis,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: const [
            SizedBox(height: 40),
            Center(child: Text('Analysis data is not available yet.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAnalysis,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Stock Analysis',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Category-wise stock listing with item names and available quantities.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          if (availableCategories.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('No category analysis available.'),
              ),
            )
          else
            ...availableCategories.map((categoryKey) {
              final items =
                  _inventory
                      .where(
                        (item) => item.category.toLowerCase() == categoryKey,
                      )
                      .toList()
                    ..sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    );

              final categoryLabel =
                  categorySummaries[categoryKey]?.categoryDisplay.isNotEmpty ==
                      true
                  ? categorySummaries[categoryKey]!.categoryDisplay
                  : categoryKey[0].toUpperCase() + categoryKey.substring(1);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        categoryLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Stock Names',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (items.isEmpty)
                        const Text(
                          'No stock items in this category.',
                          style: TextStyle(color: Colors.black54),
                        )
                      else
                        ...items.map(
                          (item) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (item.otherCategoryName
                                          .trim()
                                          .isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            item.otherCategoryName,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: item.quantityAvailable <= 2
                                        ? Colors.red.withValues(alpha: 0.08)
                                        : AppColors.primaryMaroon.withValues(
                                            alpha: 0.08,
                                          ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'Qty: ${item.quantityAvailable}',
                                    style: TextStyle(
                                      color: item.quantityAvailable <= 2
                                          ? Colors.red.shade700
                                          : AppColors.primaryMaroon,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),
          const Text(
            'Event-wise Usage Analysis',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'For each maintenance event, see which stock was used category-wise and item-wise.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          if (eventsWithUsedStock.isNotEmpty)
            DropdownButtonFormField<int?>(
              isExpanded: true,
              initialValue: selectedAnalysisEventStillExists
                  ? _analysisEventIdFilter
                  : null,
              decoration: const InputDecoration(labelText: 'Maintenance Event'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('All Events'),
                ),
                ...availableAnalysisEventOptions,
              ],
              onChanged: (value) {
                setState(() {
                  _analysisEventIdFilter = value;
                });
                unawaited(_persistUiState());
              },
            ),
          if (eventsWithUsedStock.isNotEmpty) const SizedBox(height: 12),
          if (eventsWithUsedStock.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('No event-wise stock usage found yet.'),
              ),
            )
          else
            ...filteredEventsWithUsedStock.map((event) {
              final categoryUsage = _buildEventUsageSummaries(event);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Date: ${event.eventDate}',
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryMaroon.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Items: ${event.usedItems.length}',
                              style: const TextStyle(
                                color: AppColors.primaryMaroon,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (categoryUsage.isEmpty)
                        const Text(
                          'No used stock recorded for this event.',
                          style: TextStyle(color: Colors.black54),
                        )
                      else
                        ...categoryUsage.map(
                          (category) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        category.categoryLabel,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Used: ${category.totalQuantityUsed}',
                                      style: const TextStyle(
                                        color: AppColors.primaryMaroon,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...category.items.map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            style: const TextStyle(
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          'x${item.quantityUsed}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  List<_EventUsageCategorySummary> _buildEventUsageSummaries(
    MaintenanceEvent event,
  ) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final usedItem in event.usedItems) {
      final inventoryItem = _inventory
          .where((item) => item.id == usedItem.inventoryItem)
          .cast<InventoryItem?>()
          .firstWhere((item) => item != null, orElse: () => null);

      final categoryKey =
          inventoryItem?.category.trim().toLowerCase().isNotEmpty == true
          ? inventoryItem!.category.trim().toLowerCase()
          : 'others';

      final categoryLabel =
          inventoryItem?.categoryDisplay.trim().isNotEmpty == true
          ? inventoryItem!.categoryDisplay.trim()
          : categoryKey[0].toUpperCase() + categoryKey.substring(1);

      final itemLabel = usedItem.inventoryItemName.trim().isNotEmpty
          ? usedItem.inventoryItemName.trim()
          : inventoryItem?.name.trim().isNotEmpty == true
          ? inventoryItem!.name.trim()
          : 'Item #${usedItem.inventoryItem}';

      final categoryBucket = grouped.putIfAbsent(
        categoryKey,
        () => <String, dynamic>{
          'label': categoryLabel,
          'total': 0,
          'items': <String, int>{},
        },
      );

      categoryBucket['total'] =
          (categoryBucket['total'] as int) + usedItem.quantityUsed;

      final items = categoryBucket['items'] as Map<String, int>;
      items[itemLabel] = (items[itemLabel] ?? 0) + usedItem.quantityUsed;
    }

    final summaries = grouped.entries.map((entry) {
      final itemMap = entry.value['items'] as Map<String, int>;
      final items =
          itemMap.entries
              .map(
                (itemEntry) => _EventUsageItemSummary(
                  name: itemEntry.key,
                  quantityUsed: itemEntry.value,
                ),
              )
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      return _EventUsageCategorySummary(
        categoryKey: entry.key,
        categoryLabel: entry.value['label'] as String,
        totalQuantityUsed: entry.value['total'] as int,
        items: items,
      );
    }).toList()..sort((a, b) => a.categoryKey.compareTo(b.categoryKey));

    return summaries;
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.canManageInventory;
    final embeddedAdminSection = widget.embeddedAdminSection
        ?.trim()
        .toLowerCase();
    final isRequestApprover = widget.canManageInventory;
    final canApproveCompletion = widget.canApproveCompletionRequests;
    final pendingApprovalsCount = _requests
        .where((item) => item.status.toLowerCase() == 'pending')
        .length;
    final pendingCompletionCount = _completionRequests
        .where((item) => item.status.toLowerCase() == 'pending')
        .length;
    final pendingEntriesCount = _entries
        .where((item) => item.status.toLowerCase() == 'pending')
        .length;
    final adminTabLabels = <String>[
      ..._allCategoryTabs.map((c) => c[0].toUpperCase() + c.substring(1)),
      'Approvals${pendingApprovalsCount > 0 ? ' ($pendingApprovalsCount)' : ''}',
      'Events',
      'Instrument Maintenance',
      'Dhol Range Management',
      'Dhol Status Management',
      if (_showAdminCompletionTab)
        'Completion${pendingCompletionCount > 0 ? ' ($pendingCompletionCount)' : ''}',
      if (_showLegacyEntriesTab)
        'Entries${pendingEntriesCount > 0 ? ' ($pendingEntriesCount)' : ''}',
      'Analysis',
    ];

    final categoryTabWidgets = _visibleCategoryTabs
        .map((c) => Tab(text: c[0].toUpperCase() + c.substring(1)))
        .toList();

    final tabs = isAdmin
        ? [
            ..._allCategoryTabs.map(
              (c) => Tab(text: c[0].toUpperCase() + c.substring(1)),
            ),
            Tab(
              text: pendingApprovalsCount > 0
                  ? 'Approvals ($pendingApprovalsCount)'
                  : 'Approvals',
            ),
            const Tab(text: 'Events'),
            const Tab(text: 'Instrument Maintenance'),
            const Tab(text: 'Dhol Range Management'),
            const Tab(text: 'Dhol Status Management'),
            if (_showAdminCompletionTab)
              Tab(
                text: pendingCompletionCount > 0
                    ? 'Completion ($pendingCompletionCount)'
                    : 'Completion',
              ),
            if (_showLegacyEntriesTab)
              Tab(
                text: pendingEntriesCount > 0
                    ? 'Entries ($pendingEntriesCount)'
                    : 'Entries',
              ),
            const Tab(text: 'Analysis'),
          ]
        : [
            ...categoryTabWidgets,
            Tab(text: isRequestApprover ? 'Approvals' : 'My Requests'),
            const Tab(text: 'Events'),
            const Tab(text: 'Dhol Maintenance'),
            Tab(
              text: canApproveCompletion
                  ? 'Completion Approvals'
                  : 'Completion',
            ),
          ];

    final tabViews = isAdmin
        ? [
            ..._allCategoryTabs.map((c) => _buildCategoryTab(c)),
            _buildRequestsTab(),
            _buildEventsTab(),
            _buildInstrumentMaintenanceTab(),
            _buildDholRangeManagementTab(),
            _buildDholStatusManagementTab(),
            if (_showAdminCompletionTab) _buildCompletionRequestsTab(),
            if (_showLegacyEntriesTab) _buildEntriesTab(),
            _buildAnalysisTab(),
          ]
        : [
            ..._visibleCategoryTabs.map((c) => _buildCategoryTab(c)),
            isRequestApprover ? _buildRequestsTab() : _buildMyRequestsTab(),
            _buildEventsTab(),
            _buildInstrumentMaintenanceTab(),
            _buildCompletionRequestsTab(),
          ];

    if (embeddedAdminSection == 'approvals') {
      final showStockApprovalRequests = widget.canApproveEntries;
      final showInventoryManagement = widget.canManageInventory;
      final approvalTabs = <Tab>[
        if (showInventoryManagement)
          ..._allCategoryTabs.map(
            (c) => Tab(text: c[0].toUpperCase() + c.substring(1)),
          ),
        if (showStockApprovalRequests)
          Tab(
            text: pendingApprovalsCount > 0
                ? 'Approvals ($pendingApprovalsCount)'
                : 'Approvals',
          ),
        if (_showAdminCompletionTab)
          Tab(
            text: pendingCompletionCount > 0
                ? 'Completion ($pendingCompletionCount)'
                : 'Completion',
          ),
        const Tab(text: 'Dhol Range Management'),
        const Tab(text: 'Dhol Status Management'),
        if (_showLegacyEntriesTab)
          Tab(
            text: pendingEntriesCount > 0
                ? 'Entries ($pendingEntriesCount)'
                : 'Entries',
          ),
      ];

      final approvalViews = <Widget>[
        if (showInventoryManagement)
          ..._allCategoryTabs.map((c) => _buildCategoryTab(c)),
        if (showStockApprovalRequests) _buildRequestsTab(),
        if (_showAdminCompletionTab) _buildCompletionRequestsTab(),
        _buildDholRangeManagementTab(),
        _buildDholStatusManagementTab(),
        if (_showLegacyEntriesTab) _buildEntriesTab(),
      ];

      if (approvalTabs.isEmpty || approvalViews.isEmpty) {
        return Container(
          color: AppColors.background,
          alignment: Alignment.center,
          child: const Text(
            'You do not have access to maintenance approvals.',
            style: TextStyle(
              color: AppColors.primaryMaroon,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }

      return DefaultTabController(
        length: approvalTabs.length,
        child: Container(
          color: AppColors.background,
          child: Column(
            children: [
              Material(
                color: AppColors.primaryMaroon,
                child: TabBar(
                  isScrollable: true,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                  labelColor: AppColors.accentYellow,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: AppColors.accentYellow,
                  tabs: approvalTabs,
                ),
              ),
              if (widget.canCreateMaintenanceEvents)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _openCreateEventForm,
                      style: ElevatedButton.styleFrom(
                        foregroundColor: AppColors.primaryMaroon,
                      ),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Create Maintenance Day'),
                    ),
                  ),
                ),
              if (_isGatPramukhCompletionApprover)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'You are gat pramukh of this gat.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primaryMaroon.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              Expanded(child: TabBarView(children: approvalViews)),
            ],
          ),
        ),
      );
    }

    if (embeddedAdminSection == 'analysis') {
      return Container(color: AppColors.background, child: _buildAnalysisTab());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dhol Maintenance'),
        backgroundColor: AppColors.primaryMaroon,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshActiveTab,
            icon: const Icon(Icons.refresh),
          ),
          if (isAdmin) ...[
            IconButton(
              tooltip: _showLegacyEntriesTab
                  ? 'Hide legacy entries tab'
                  : 'Show legacy entries tab',
              onPressed: _toggleLegacyEntriesTab,
              icon: Icon(
                _showLegacyEntriesTab
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
            PopupMenuButton<int>(
              tooltip: 'Jump to tab',
              icon: const Icon(Icons.view_week_outlined),
              onSelected: (index) {
                _tabController.animateTo(index);
              },
              itemBuilder: (context) {
                return List<PopupMenuEntry<int>>.generate(
                  adminTabLabels.length,
                  (index) => PopupMenuItem<int>(
                    value: index,
                    child: Text(adminTabLabels[index]),
                  ),
                );
              },
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelPadding: const EdgeInsets.symmetric(horizontal: 14),
          labelColor: AppColors.accentYellow,
          unselectedLabelColor: Colors.white70,
          indicatorColor: AppColors.accentYellow,
          tabs: tabs,
        ),
      ),
      floatingActionButton: null,
      body: Stack(
        children: [
          Container(
            color: AppColors.background,
            child: Column(
              children: [
                if (_isGatPramukhCompletionApprover)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'You are gat pramukh of this gat.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primaryMaroon.withValues(
                            alpha: 0.85,
                          ),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: tabViews,
                  ),
                ),
              ],
            ),
          ),
          if (_isAnyApiCallInProgress)
            Positioned.fill(
              child: AbsorbPointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.22),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(
                    color: AppColors.accentYellow,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

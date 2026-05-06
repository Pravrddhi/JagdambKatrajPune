import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'dhol_maintenance_screen.dart';
import 'terms_conditions_manage_screen.dart';
import 'all_users_screen.dart';
import '../widgets/attendance_settings_panel.dart';
import '../widgets/document_approval_panel.dart';

class AdminOperationsScreen extends StatelessWidget {
  final int initialTabIndex;
  final bool canGenerateAttendanceQr;
  final bool canSetAttendanceLocation;
  final bool canViewAttendanceByUser;
  final bool canViewDocumentApprovals;
  final bool isPathakAdmin;

  final bool canManageMaintenanceInventory;
  final bool canApproveMaintenanceEntries;
  final bool canCreateMaintenanceEvents;
  final bool canApproveMaintenanceCompletions;
  final bool canViewMaintenanceAnalysis;
  final bool isPathakAdminApprover;
  final int? approverGatId;
  final int? currentUserId;
  final String? currentUserName;
  final String? userInstrument;

  final bool canManageTerms;
  final bool showUsersStatusFilters;
  final bool canUpdateUserGroup;
  final bool isGatPramukh;
  final String? gatPramukhName;

  const AdminOperationsScreen({
    super.key,
    this.initialTabIndex = 0,
    required this.canGenerateAttendanceQr,
    required this.canSetAttendanceLocation,
    required this.canViewAttendanceByUser,
    required this.canViewDocumentApprovals,
    required this.isPathakAdmin,
    required this.canManageMaintenanceInventory,
    required this.canApproveMaintenanceEntries,
    required this.canCreateMaintenanceEvents,
    required this.canApproveMaintenanceCompletions,
    required this.canViewMaintenanceAnalysis,
    required this.isPathakAdminApprover,
    this.approverGatId,
    this.currentUserId,
    this.currentUserName,
    this.userInstrument,
    required this.canManageTerms,
    this.showUsersStatusFilters = true,
    this.canUpdateUserGroup = false,
    this.isGatPramukh = false,
    this.gatPramukhName,
  });

  @override
  Widget build(BuildContext context) {
    final requestedCanonicalIndex = initialTabIndex < 0
        ? 0
        : (initialTabIndex > 5 ? 5 : initialTabIndex);

    final showAttendanceTab =
        canSetAttendanceLocation || canGenerateAttendanceQr;
    final showUsersTab = canUpdateUserGroup;
    final showDocumentApprovalTab = canViewDocumentApprovals;
    final showMaintenanceApprovalsTab =
        canManageMaintenanceInventory ||
        canApproveMaintenanceEntries ||
        canCreateMaintenanceEvents ||
        canApproveMaintenanceCompletions;
    final showMaintenanceAnalysisTab = canViewMaintenanceAnalysis;
    final showManageTermsTab = canManageTerms;

    final tabs = <({int canonicalIndex, Tab tab, Widget view})>[
      if (showAttendanceTab)
        (
          canonicalIndex: 0,
          tab: const Tab(text: 'Attendance'),
          view: AttendanceSettingsPanel(
            canManageSettings: canSetAttendanceLocation,
            canGenerateQr: canGenerateAttendanceQr,
          ),
        ),
      if (showUsersTab)
        (
          canonicalIndex: 1,
          tab: const Tab(text: 'Users'),
          view: AllUsersScreen(
            showStatusFilters: showUsersStatusFilters,
            isPathakAdmin: isPathakAdmin,
            canUpdateUserGroup: canUpdateUserGroup,
            isGatPramukh: isGatPramukh,
            gatPramukhName: gatPramukhName,
          ),
        ),
      if (showDocumentApprovalTab)
        (
          canonicalIndex: 2,
          tab: const Tab(text: 'Document Approvals'),
          view: DocumentApprovalPanel(enabled: canViewDocumentApprovals),
        ),
      if (showMaintenanceApprovalsTab)
        (
          canonicalIndex: 3,
          tab: const Tab(text: 'Maintenance Approvals'),
          view: DholMaintenanceScreen(
            embeddedAdminSection: 'approvals',
            canManageInventory: canManageMaintenanceInventory,
            canApproveEntries: canApproveMaintenanceEntries,
            canCreateMaintenanceEvents: canCreateMaintenanceEvents,
            canApproveCompletionRequests: canApproveMaintenanceCompletions,
            isPathakAdminApprover: isPathakAdminApprover,
            approverGatId: approverGatId,
            currentUserId: currentUserId,
            currentUserName: currentUserName,
            userInstrument: userInstrument,
          ),
        ),
      if (showMaintenanceAnalysisTab)
        (
          canonicalIndex: 4,
          tab: const Tab(text: 'Maintenance Analysis'),
          view: DholMaintenanceScreen(
            embeddedAdminSection: 'analysis',
            canManageInventory: canViewMaintenanceAnalysis,
            canApproveEntries: canApproveMaintenanceEntries,
            canCreateMaintenanceEvents: canCreateMaintenanceEvents,
            canApproveCompletionRequests: canApproveMaintenanceCompletions,
            isPathakAdminApprover: isPathakAdminApprover,
            approverGatId: approverGatId,
            currentUserId: currentUserId,
            currentUserName: currentUserName,
            userInstrument: userInstrument,
          ),
        ),
      if (showManageTermsTab)
        (
          canonicalIndex: 5,
          tab: const Tab(text: 'Manage Terms'),
          view: const TermsConditionsManageScreen(embedded: true),
        ),
    ];

    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primaryMaroon,
          title: const Text('Admin'),
        ),
        body: const Center(
          child: Text(
            'You do not have access to any admin tabs.',
            style: TextStyle(
              color: AppColors.primaryMaroon,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    final requestedVisibleIndex = tabs.indexWhere(
      (entry) => entry.canonicalIndex == requestedCanonicalIndex,
    );
    final resolvedInitialVisibleIndex = requestedVisibleIndex >= 0
        ? requestedVisibleIndex
        : 0;

    return DefaultTabController(
      length: tabs.length,
      initialIndex: resolvedInitialVisibleIndex,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primaryMaroon,
          title: const Text('Admin'),
          bottom: TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFFE7E7E7),
            indicatorColor: AppColors.accentYellow,
            tabs: tabs.map((entry) => entry.tab).toList(),
          ),
        ),
        body: TabBarView(children: tabs.map((entry) => entry.view).toList()),
      ),
    );
  }
}

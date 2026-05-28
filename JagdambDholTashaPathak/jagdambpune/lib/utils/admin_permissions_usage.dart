// Example: How to use AdminPermissions from the login API

// In home_screen.dart or any screen that needs to call AdminOperationsScreen:

import 'package:jagdambpune/utils/admin_permissions.dart';
import 'package:jagdambpune/screens/admin_operations_screen.dart';

// Option 1: Using permissions from the login API (NEW - RECOMMENDED)
// When you have the user details from the login response:
Future<void> _openAdminScreen() {
  final adminPermissions = AdminPermissions.fromUserDetails(_userDetails);
  
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AdminOperationsScreen(
        permissions: adminPermissions, // Pass the permissions from login API
        currentUserId: _currentUserId,
        currentUserName: _currentUserName,
        userInstrument: _userDetails?['instrument']?.toString(),
        approverGatId: _currentUserGatId,
        gatPramukhName: _userDetails?['gat_pramukh_name']?.toString(),
        isGatPramukh: _isGatPramukh,
        showUsersStatusFilters: _isPathakAdmin || !_isGatPramukh,
      ),
    ),
  );
}

// Option 2: Using individual permission flags (OLD - BACKWARD COMPATIBLE)
// For existing code, you can still pass individual flags:
Future<void> _openAdminScreenLegacy() {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AdminOperationsScreen(
        canGenerateAttendanceQr: _canGenerateAttendanceQr,
        canDownloadAttendanceQr: _canDownloadAttendanceQr,
        canSetAttendanceLocation: _canSetAttendanceLocation,
        // ... other flags
      ),
    ),
  );
}

// Option 3: Using permissions map directly from login API response
// If you have the permissions JSON directly from the login API:
Future<void> _openAdminScreenFromLoginResponse() {
  final loginResponse = ...; // Your login API response
  final permissionsFromApi = loginResponse['permissions'] as Map<String, dynamic>?;
  final adminPermissions = AdminPermissions.fromPermissionsMap(permissionsFromApi);
  
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AdminOperationsScreen(
        permissions: adminPermissions,
        // ... other parameters
      ),
    ),
  );
}

// Advantages of using AdminPermissions from login API:
// 1. Single source of truth - permissions come directly from login API
// 2. No need to manually pass 15+ individual boolean flags
// 3. Automatically handles all permission mapping and variations
// 4. Backward compatible - old code still works
// 5. Easier to maintain - permission keys are centralized in AdminPermissions
// 6. Dynamic UI - admin screens only show options user has permission for

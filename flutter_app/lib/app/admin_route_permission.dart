import '../core/constants/admin_permissions.dart';
import 'routes.dart';

/// Returns the permission required by an administrative child route.
/// The panel root intentionally remains public so configured administrators
/// can use the dedicated login form.
String? requiredAdminPermission(String location) {
  if (location == AppRoutes.admin || !location.startsWith(AppRoutes.admin)) {
    return null;
  }
  if (location.startsWith(AppRoutes.adminOrders)) {
    return AdminPermissions.orders;
  }
  if (location.startsWith(AppRoutes.adminTransfers)) {
    return AdminPermissions.transfers;
  }
  if (location.startsWith(AppRoutes.adminScanner)) {
    return AdminPermissions.scanner;
  }
  if (location.startsWith(AppRoutes.adminBotMessages)) {
    return AdminPermissions.botMessages;
  }
  if (location.startsWith(AppRoutes.adminProducts)) {
    return AdminPermissions.products;
  }
  if (location.startsWith(AppRoutes.adminPromos)) {
    return AdminPermissions.promos;
  }
  if (location.startsWith(AppRoutes.adminStats)) {
    return AdminPermissions.stats;
  }
  if (location.startsWith('${AppRoutes.admin}/event/')) {
    return AdminPermissions.events;
  }
  return null;
}

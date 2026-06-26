import '../config/app_config.dart';
import '../constants/admin_permissions.dart';
import '../models/user.dart';

/// canAccessAdminPanel reports whether the user can open the admin panel.
bool canAccessAdminPanel(User? user, AppConfig config) {
  if (user == null) return false;
  if (config.adminTelegramIds.contains(user.telegramId)) return true;
  return user.canAccessAdminPanel;
}

/// hasAdminPermission reports whether the user has the requested admin permission.
bool hasAdminPermission(User? user, AppConfig config, String permission) {
  final permissions = resolveAdminPermissions(user, config);
  return permissions.contains(permission.trim().toLowerCase());
}

/// resolveAdminPermissions resolves the effective admin permissions for the user.
Set<String> resolveAdminPermissions(User? user, AppConfig config) {
  if (user == null) return <String>{};
  final permissions = <String>{};
  if (config.adminTelegramIds.contains(user.telegramId)) {
    permissions.addAll(AdminPermissions.all);
  }
  permissions.addAll(
    user.adminPermissions
        .map((permission) => permission.trim().toLowerCase())
        .where((permission) => permission.isNotEmpty),
  );
  return permissions;
}

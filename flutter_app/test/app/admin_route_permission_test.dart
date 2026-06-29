import 'package:flutter_test/flutter_test.dart';
import 'package:gigme_flutter/app/admin_route_permission.dart';
import 'package:gigme_flutter/app/routes.dart';
import 'package:gigme_flutter/core/constants/admin_permissions.dart';

/// Verifies the frontend permission boundary for every protected admin route.
void main() {
  test('admin child routes resolve the expected permissions', () {
    expect(requiredAdminPermission(AppRoutes.admin), isNull);
    expect(
      requiredAdminPermission('${AppRoutes.admin}/event/42'),
      AdminPermissions.events,
    );
    expect(
      requiredAdminPermission(AppRoutes.adminOrders),
      AdminPermissions.orders,
    );
    expect(
      requiredAdminPermission(AppRoutes.adminTransfers),
      AdminPermissions.transfers,
    );
    expect(
      requiredAdminPermission(AppRoutes.adminScanner),
      AdminPermissions.scanner,
    );
    expect(requiredAdminPermission(AppRoutes.feed), isNull);
  });
}

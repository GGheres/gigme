import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/providers.dart';
import '../core/notifications/providers.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/auth_state.dart';

/// PushBootstrap represents push bootstrap.

class PushBootstrap extends ConsumerWidget {
  /// PushBootstrap handles push bootstrap.
  const PushBootstrap({
    required this.child,
    super.key,
  });

  final Widget child;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).state;
    final config = ref.watch(appConfigProvider);

    unawaited(ref.read(localReminderServiceProvider).initialize());

    if (auth.status == AuthStatus.authenticated &&
        (auth.token ?? '').trim().isNotEmpty) {
      unawaited(
        ref.read(pushNotificationServiceProvider).initialize(
              config: config,
              accessToken: auth.token!,
              apiClient: ref.read(apiClientProvider),
            ),
      );
    }

    return child;
  }
}

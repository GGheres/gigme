import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/providers.dart';
import '../core/notifications/providers.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/auth_state.dart';

class PushBootstrap extends ConsumerWidget {
  const PushBootstrap({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).state;
    final config = ref.watch(appConfigProvider);

    if (auth.status == AuthStatus.authenticated && (auth.token ?? '').trim().isNotEmpty) {
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

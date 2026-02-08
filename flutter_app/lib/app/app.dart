import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'push_bootstrap.dart';
import 'theme.dart';

class GigMeApp extends ConsumerWidget {
  const GigMeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return PushBootstrap(
      child: MaterialApp.router(
        title: 'GigMe Flutter',
        theme: buildGigMeTheme(),
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

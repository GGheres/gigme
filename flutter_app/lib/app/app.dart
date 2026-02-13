import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'push_bootstrap.dart';
import 'theme.dart';
import '../ui/layout/app_background.dart';

class GigMeApp extends ConsumerWidget {
  const GigMeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return PushBootstrap(
      child: MaterialApp.router(
        title: 'SPACE',
        theme: buildGigMeTheme(),
        locale: const Locale('ru', 'RU'),
        supportedLocales: const [
          Locale('ru', 'RU'),
          Locale('en', 'US'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
        builder: (context, child) => AppBackground(
          child: child ?? const SizedBox.shrink(),
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

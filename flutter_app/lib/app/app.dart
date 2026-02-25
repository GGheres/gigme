import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'push_bootstrap.dart';
import 'theme_mode_provider.dart';
import 'theme.dart';
import '../ui/layout/app_background.dart';

/// GigMeApp represents gig me app.

class GigMeApp extends ConsumerWidget {
  /// GigMeApp handles gig me app.
  const GigMeApp({super.key});

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(appThemeModeProvider);

    return PushBootstrap(
      child: MaterialApp.router(
        title: 'SPACE',
        theme: buildGigMeLightTheme(),
        darkTheme: buildGigMeDarkTheme(),
        themeMode: themeMode,
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
        builder: (context, child) => SelectionArea(
          child: AppBackground(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

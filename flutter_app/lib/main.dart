import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';

/// main is the application entry point.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU');
  if (kIsWeb) {
    // Telegram WebApp passes runtime params in URL fragment.
    // Force path strategy so fragment is not treated as the app route.
    usePathUrlStrategy();
  }
  runApp(const ProviderScope(child: GigMeApp()));
}

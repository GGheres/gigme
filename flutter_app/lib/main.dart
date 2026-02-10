import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Telegram WebApp passes runtime params in URL fragment.
    // Force path strategy so fragment is not treated as the app route.
    usePathUrlStrategy();
  }
  runApp(const ProviderScope(child: GigMeApp()));
}

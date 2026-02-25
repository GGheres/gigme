import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/event_access_key_store.dart';
import '../storage/token_storage.dart';
import 'api_client.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  return ApiClient(baseUrl: config.apiUrl);
});

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final eventAccessKeyStoreProvider =
    Provider<EventAccessKeyStore>((ref) => EventAccessKeyStore());

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/iskry_models.dart';

/// IskryRepository loads public ISKRY landing data.
class IskryRepository {
  /// IskryRepository creates the public landing repository.
  IskryRepository(this._ref);

  final Ref _ref;

  /// getLanding returns the public /iskry payload.
  Future<IskryLandingModel> getLanding() {
    return _ref
        .read(apiClientProvider)
        .get<IskryLandingModel>(
          '/landing/iskry',
          decoder: IskryLandingModel.fromJson,
        );
  }
}

final iskryRepositoryProvider =
/// iskryRepositoryProvider exposes the public ISKRY repository.
Provider<IskryRepository>((ref) => IskryRepository(ref));

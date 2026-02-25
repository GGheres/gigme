import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user.dart';
import '../../../core/models/user_event.dart';
import '../../auth/application/auth_controller.dart';
import '../data/profile_repository.dart';

/// ProfileState represents profile state.

class ProfileState {
  /// ProfileState handles profile state.

  factory ProfileState.initial() => const ProfileState(
        loading: false,
        error: null,
        notice: null,
        user: null,
        events: <UserEvent>[],
        total: 0,
      );

  /// ProfileState handles profile state.
  const ProfileState({
    required this.loading,
    required this.error,
    required this.notice,
    required this.user,
    required this.events,
    required this.total,
  });

  final bool loading;
  final String? error;
  final String? notice;
  final User? user;
  final List<UserEvent> events;
  final int total;

  /// copyWith handles copy with.

  ProfileState copyWith({
    bool? loading,
    String? error,
    String? notice,
    User? user,
    List<UserEvent>? events,
    int? total,
  }) {
    return ProfileState(
      loading: loading ?? this.loading,
      error: error,
      notice: notice,
      user: user ?? this.user,
      events: events ?? this.events,
      total: total ?? this.total,
    );
  }
}

/// ProfileController represents profile controller.

class ProfileController extends ChangeNotifier {
  /// ProfileController handles profile controller.
  ProfileController({
    required this.ref,
    required this.repository,
  });

  final Ref ref;
  final ProfileRepository repository;

  ProfileState _state = ProfileState.initial();

  /// state exposes the current state value.
  ProfileState get state => _state;

  /// _token handles internal token behavior.

  String? get _token => ref.read(authControllerProvider).state.token;

  /// load loads data from the underlying source.

  Future<void> load() async {
    final token = _token;
    if (token == null || token.trim().isEmpty) return;

    _state = _state.copyWith(loading: true, error: null, notice: null);
    notifyListeners();

    try {
      final results = await Future.wait<dynamic>([
        repository.getMe(token: token),
        repository.getMyEvents(token: token, limit: 50, offset: 0),
      ]);

      final user = results[0] as User;
      final eventsResponse = results[1] as UserEventsResponse;

      _state = _state.copyWith(
        loading: false,
        user: user,
        events: eventsResponse.items,
        total: eventsResponse.total,
        error: null,
      );
      notifyListeners();

      unawaited(ref.read(authControllerProvider).refreshMe());
    } catch (error) {
      _state = _state.copyWith(
        loading: false,
        error: '$error',
      );
      notifyListeners();
    }
  }

  /// topupTokens handles topup tokens.

  Future<void> topupTokens(int amount) async {
    final token = _token;
    if (token == null || token.trim().isEmpty) return;

    _state = _state.copyWith(loading: true, error: null, notice: null);
    notifyListeners();

    try {
      final response =
          await repository.topupToken(token: token, amount: amount);
      final current = _state.user;
      final updated = current?.copyWith(balanceTokens: response.balanceTokens);

      _state = _state.copyWith(
        loading: false,
        user: updated,
        notice: 'Balance updated.',
      );
      notifyListeners();
    } catch (error) {
      _state = _state.copyWith(loading: false, error: '$error');
      notifyListeners();
    }
  }
}

final profileControllerProvider =
    ChangeNotifierProvider<ProfileController>((ref) {
  final controller = ProfileController(
    ref: ref,
    repository: ref.watch(profileRepositoryProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

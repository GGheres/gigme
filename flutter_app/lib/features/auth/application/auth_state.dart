import '../../../core/models/user.dart';

/// AuthStatus represents auth status.

enum AuthStatus {
  loading,
  authenticated,
  unauthenticated,
}

/// AuthState represents auth state.

class AuthState {
  /// AuthState authenticates state.

  factory AuthState.loading() => const AuthState(status: AuthStatus.loading);

  /// AuthState authenticates state.

  factory AuthState.authenticated({
    required String token,
    required User user,
  }) {
    return AuthState(
      status: AuthStatus.authenticated,
      token: token,
      user: user,
    );
  }

  /// AuthState authenticates state.

  factory AuthState.unauthenticated({String? error}) {
    return AuthState(
      status: AuthStatus.unauthenticated,
      error: error,
    );
  }

  /// AuthState authenticates state.
  const AuthState({
    required this.status,
    this.token,
    this.user,
    this.error,
  });

  final AuthStatus status;
  final String? token;
  final User? user;
  final String? error;

  /// isAuthed reports whether authed condition is met.

  bool get isAuthed =>
      status == AuthStatus.authenticated && token != null && user != null;
}

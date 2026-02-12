import '../../../core/models/user.dart';

enum AuthStatus {
  loading,
  authenticated,
  unauthenticated,
}

class AuthState {

  factory AuthState.loading() => const AuthState(status: AuthStatus.loading);

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

  factory AuthState.unauthenticated({String? error}) {
    return AuthState(
      status: AuthStatus.unauthenticated,
      error: error,
    );
  }
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

  bool get isAuthed => status == AuthStatus.authenticated && token != null && user != null;
}

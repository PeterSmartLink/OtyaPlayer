import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'fcm_service.dart';

class AuthState {
  final String? userId;
  final String? displayName;
  final String? email;
  final String? photoUrl;

  const AuthState({
    this.userId,
    this.displayName,
    this.email,
    this.photoUrl,
  });

  bool get isSignedIn => userId != null && userId!.isNotEmpty;

  AuthState copyWith({
    String? userId,
    String? displayName,
    String? email,
    String? photoUrl,
  }) =>
      AuthState(
        userId: userId ?? this.userId,
        displayName: displayName ?? this.displayName,
        email: email ?? this.email,
        photoUrl: photoUrl ?? this.photoUrl,
      );
}

/// UI auth state mirrors the real OTYA Auth session.
///
/// It must never manufacture a local "signed in" identity. A visible account
/// is accepted only when AuthService has a valid/refreshed Bearer token and the
/// requested user id matches the authenticated backend profile.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _loadValidatedSession();
    return const AuthState();
  }

  Future<void> _loadValidatedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await AuthService.instance.getValidToken();
    final authenticatedUserId = AuthService.instance.userId;
    final storedUserId = prefs.getString('otya_user_id');

    if (token == null ||
        authenticatedUserId == null ||
        storedUserId == null ||
        storedUserId != authenticatedUserId) {
      await _clearLocalState(prefs);
      state = const AuthState();
      return;
    }

    state = AuthState(
      userId: authenticatedUserId,
      displayName: prefs.getString('otya_user_name'),
      email: prefs.getString('otya_user_email') ?? AuthService.instance.userEmail,
      photoUrl: prefs.getString('otya_user_avatar'),
    );
    FcmService.instance.syncRegistration().ignore();
  }

  Future<void> signIn({
    required String userId,
    required String displayName,
    String? email,
    String? photoUrl,
  }) async {
    final token = await AuthService.instance.getValidToken();
    final authenticatedUserId = AuthService.instance.userId;
    if (token == null ||
        authenticatedUserId == null ||
        authenticatedUserId != userId) {
      // Reject fake/local identities. The caller must complete the real auth
      // flow first; this prevents Hub shortcuts from bypassing backend auth.
      state = const AuthState();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('otya_user_id', authenticatedUserId);
    await prefs.setString('otya_user_name', displayName);

    final resolvedEmail = email ?? AuthService.instance.userEmail;
    if (resolvedEmail != null && resolvedEmail.trim().isNotEmpty) {
      await prefs.setString('otya_user_email', resolvedEmail.trim());
    } else {
      // Never inherit identity metadata from a previously signed-in account.
      await prefs.remove('otya_user_email');
    }

    final resolvedPhotoUrl = photoUrl?.trim();
    if (resolvedPhotoUrl != null && resolvedPhotoUrl.isNotEmpty) {
      await prefs.setString('otya_user_avatar', resolvedPhotoUrl);
    } else {
      // A new account without an avatar must not display the previous user's.
      await prefs.remove('otya_user_avatar');
    }

    state = AuthState(
      userId: authenticatedUserId,
      displayName: displayName,
      email: resolvedEmail?.trim().isNotEmpty == true ? resolvedEmail!.trim() : null,
      photoUrl: resolvedPhotoUrl?.isNotEmpty == true ? resolvedPhotoUrl : null,
    );

    // Rebind this installation to the newly authenticated account. This is
    // recoverable background work; sign-in UI must not wait on FCM/network.
    FcmService.instance.syncRegistration().ignore();
  }

  Future<void> signOut() async {
    await AuthService.instance.logout();
    final prefs = await SharedPreferences.getInstance();
    await _clearLocalState(prefs);
    state = const AuthState();

    // AuthService has already cleared the local bearer session. Re-registering
    // the same installation anonymously now detaches its previous user_id on
    // the server, without delaying the local-first sign-out boundary.
    FcmService.instance.syncRegistration().ignore();
  }

  Future<void> _clearLocalState(SharedPreferences prefs) async {
    await prefs.remove('otya_user_id');
    await prefs.remove('otya_user_name');
    await prefs.remove('otya_user_email');
    await prefs.remove('otya_user_avatar');
  }
}

final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

final isSignedInProvider =
    Provider<bool>((ref) => ref.watch(authNotifierProvider).isSignedIn);

final displayNameProvider = Provider<String?>((ref) {
  final n = ref.watch(authNotifierProvider).displayName;
  return (n?.isNotEmpty == true) ? n : null;
});

final userEmailProvider = Provider<String?>((ref) {
  final e = ref.watch(authNotifierProvider).email;
  return (e?.isNotEmpty == true) ? e : null;
});

final photoUrlProvider = Provider<String?>((ref) {
  final u = ref.watch(authNotifierProvider).photoUrl;
  return (u?.isNotEmpty == true) ? u : null;
});

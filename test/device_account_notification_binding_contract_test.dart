import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/core/services/auth_provider.dart').readAsStringSync();

  test('valid sign-in rebinds FCM registration to the authenticated account', () {
    final signInStart = source.indexOf('Future<void> signIn({');
    final signOutStart = source.indexOf('Future<void> signOut() async');
    expect(signInStart, greaterThanOrEqualTo(0));
    expect(signOutStart, greaterThan(signInStart));
    final signIn = source.substring(signInStart, signOutStart);
    expect(signIn, contains('FcmService.instance.syncRegistration().ignore()'));
  });

  test('local-first sign out schedules anonymous FCM registration after clearing auth', () {
    final signOutStart = source.indexOf('Future<void> signOut() async');
    final clearStart = source.indexOf('Future<void> _clearLocalState', signOutStart);
    expect(signOutStart, greaterThanOrEqualTo(0));
    expect(clearStart, greaterThan(signOutStart));
    final signOut = source.substring(signOutStart, clearStart);
    final logout = signOut.indexOf('await AuthService.instance.logout()');
    final emptyState = signOut.indexOf('state = const AuthState()');
    final resync = signOut.indexOf('FcmService.instance.syncRegistration().ignore()');
    expect(logout, greaterThanOrEqualTo(0));
    expect(emptyState, greaterThan(logout));
    expect(resync, greaterThan(emptyState));
    expect(signOut, isNot(contains('await FcmService.instance.syncRegistration()')));
  });

  test('expired or revoked persisted sessions also resync device ownership anonymously', () {
    final loadStart = source.indexOf('Future<void> _loadValidatedSession() async');
    final signInStart = source.indexOf('Future<void> signIn({', loadStart);
    expect(loadStart, greaterThanOrEqualTo(0));
    expect(signInStart, greaterThan(loadStart));
    final load = source.substring(loadStart, signInStart);
    expect(load, contains('state = const AuthState()'));
    expect(load, contains('FcmService.instance.syncRegistration().ignore()'));
  });
}

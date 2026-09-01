import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_client.dart';
import 'auth/driver_session_store.dart';

class SessionController extends ChangeNotifier {
  SessionController(this._api, {SessionTokenStore? tokenStore})
    : _tokenStore = tokenStore ?? SecureDriverSessionStore();

  static const _userKey = 'transitops_user';
  static const _legacyTokenKey = 'transitops_token';
  final ApiClient _api;
  final SessionTokenStore _tokenStore;

  AppUser? user;
  bool restoring = true;
  bool busy = false;
  String? error;
  Future<void> Function()? beforeLogout;

  Future<void> restore() async {
    final stopwatch = Stopwatch()..start();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyTokenKey);
      final savedToken = await _tokenStore.read();
      if (savedToken == null) return;
      _api.token = savedToken;
      final savedUser = prefs.getString(_userKey);
      if (savedUser != null) {
        try {
          user = AppUser.fromJson(
            jsonDecode(savedUser) as Map<String, dynamic>,
          );
        } catch (_) {}
      }
      try {
        final data = await _api.get('/auth/me') as Map<String, dynamic>;
        user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
        await _persistUser(prefs);
      } on ApiException catch (exception) {
        if (exception.statusCode != 401) return;
        _api.token = null;
        user = null;
        await _tokenStore.clear();
        await prefs.remove(_userKey);
      }
    } finally {
      const minimumSplash = Duration(milliseconds: 1200);
      final remaining = minimumSplash - stopwatch.elapsed;
      if (remaining.inMilliseconds > 0) await Future<void>.delayed(remaining);
      restoring = false;
      notifyListeners();
    }
  }

  Future<bool> login({
    required String email,
    required String password,
    bool driverLogin = false,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final data =
          await _api.post(driverLogin ? '/driver/auth/login' : '/auth/login', {
                'email': email.trim().toLowerCase(),
                'password': password,
              })
              as Map<String, dynamic>;
      await _applyAuthenticatedSession(data, requireDriver: driverLogin);
      final prefs = await SharedPreferences.getInstance();
      await _persistSession(prefs);
      return true;
    } catch (exception) {
      error = exception.toString();
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> registerCompany({
    required String name,
    required String companyName,
    required String email,
    required String password,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final data =
          await _api.post('/auth/register', {
                'name': name.trim(),
                'companyName': companyName.trim(),
                'email': email.trim().toLowerCase(),
                'password': password,
              })
              as Map<String, dynamic>;
      await _applyAuthenticatedSession(data);
      final prefs = await SharedPreferences.getInstance();
      await _persistSession(prefs);
      return true;
    } catch (exception) {
      error = exception.toString();
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final data =
          await _api.post('/auth/change-password', {
                'currentPassword': currentPassword,
                'newPassword': newPassword,
              })
              as Map<String, dynamic>;
      final replacementToken = data['token']?.toString().trim();
      if (replacementToken != null && replacementToken.isNotEmpty) {
        await _tokenStore.write(replacementToken);
        _api.token = replacementToken;
      }
      user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      await _persistUser(await SharedPreferences.getInstance());
      return true;
    } catch (exception) {
      error = exception.toString();
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void updateProfile(AppUser profile) {
    user = profile;
    SharedPreferences.getInstance().then(_persistUser);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await beforeLogout?.call();
    } finally {
      _api.token = null;
      user = null;
      await _tokenStore.clear();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
      notifyListeners();
    }
  }

  Future<void> _persistSession(SharedPreferences prefs) async {
    await _tokenStore.write(_api.token!);
    await _persistUser(prefs);
  }

  Future<void> invalidateSession() async {
    _api.token = null;
    user = null;
    await _tokenStore.clear();
    await (await SharedPreferences.getInstance()).remove(_userKey);
    notifyListeners();
  }

  Future<void> _applyAuthenticatedSession(
    Map<String, dynamic> data, {
    bool requireDriver = false,
  }) async {
    final token = data['token']?.toString().trim();
    final rawUser = data['user'];
    if (token == null || token.isEmpty) {
      throw const ApiException(
        'The backend did not return a mobile session token. Restart the '
        'TransitOps backend and try signing in again.',
      );
    }
    if (rawUser is! Map<String, dynamic>) {
      throw const ApiException(
        'The backend returned an invalid account response. Please try again.',
      );
    }
    final authenticatedUser = AppUser.fromJson(rawUser);
    if (requireDriver &&
        (authenticatedUser.role != UserRole.driver ||
            authenticatedUser.driverId == null)) {
      throw const ApiException(
        'This account is not linked to a Driver profile.',
        statusCode: 403,
      );
    }
    await _tokenStore.write(token);
    _api.token = token;
    user = authenticatedUser;
  }

  Future<void> _persistUser(SharedPreferences prefs) async {
    if (user != null) {
      await prefs.setString(_userKey, jsonEncode(user!.toJson()));
    }
  }
}

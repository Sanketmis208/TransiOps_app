import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_client.dart';

class SessionController extends ChangeNotifier {
  SessionController(this._api);

  static const _tokenKey = 'transitops_token';
  static const _userKey = 'transitops_user';
  final ApiClient _api;

  AppUser? user;
  bool busy = false;
  String? error;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_tokenKey);
    if (savedToken == null) return;
    _api.token = savedToken;
    final savedUser = prefs.getString(_userKey);
    if (savedUser != null) {
      try {
        user = AppUser.fromJson(jsonDecode(savedUser) as Map<String, dynamic>);
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
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
    }
  }

  Future<bool> login({required String email, required String password}) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final data =
          await _api.post('/auth/login', {
                'email': email.trim().toLowerCase(),
                'password': password,
              })
              as Map<String, dynamic>;
      _api.token = data['token'] as String;
      final authenticatedUser = AppUser.fromJson(
        data['user'] as Map<String, dynamic>,
      );
      user = authenticatedUser;
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
      _api.token = data['token'] as String;
      user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
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
    _api.token = null;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    notifyListeners();
  }

  Future<void> _persistSession(SharedPreferences prefs) async {
    await prefs.setString(_tokenKey, _api.token!);
    await _persistUser(prefs);
  }

  Future<void> _persistUser(SharedPreferences prefs) async {
    if (user != null) {
      await prefs.setString(_userKey, jsonEncode(user!.toJson()));
    }
  }
}

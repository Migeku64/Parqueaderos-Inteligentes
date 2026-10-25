import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'format.dart';
import 'realtime.dart';

class AppUser {
  AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.residentId,
    this.mustChangePassword = false,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: asInt(j['id']),
        username: asStr(j['username']),
        fullName: asStr(j['full_name']),
        role: asStr(j['role']),
        residentId: j['resident_id'] == null ? null : asInt(j['resident_id']),
        mustChangePassword: asBool(j['must_change_password']),
      );

  final int id;
  final String username;
  final String fullName;
  final String role;
  final int? residentId;
  bool mustChangePassword;

  bool get isAdmin => role == 'admin';
  bool get isGuard => role == 'guarda';
  bool get isResident => role == 'residente';
  String get displayName => fullName.isNotEmpty ? fullName : username;
}

/// Estado global de la sesión: servidor, token, usuario y tiempo real.
class Session extends ChangeNotifier {
  Session._();

  static final Session instance = Session._();

  static const _kServer = 'server_url';
  static const _kToken = 'token';

  late SharedPreferences _prefs;
  late ApiClient api;
  final realtime = Realtime();

  AppUser? user;
  int unreadNotifications = 0;
  bool ready = false;
  StreamSubscription<RtEvent>? _sub;

  /// Dirección por defecto del servidor.
  /// En el emulador de Android, 10.0.2.2 apunta al computador donde corre el backend.
  static String get defaultServer {
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://localhost:3000';
  }

  String get serverUrl => api.baseUrl;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    api = ApiClient(
      baseUrl: _prefs.getString(_kServer) ?? defaultServer,
      token: _prefs.getString(_kToken),
      onUnauthorized: () => logout(),
    );
    if (api.token != null) {
      try {
        final me = await api.get('/auth/me');
        user = AppUser.fromJson(asMap(asMap(me)['user']));
        _afterLogin();
      } catch (e) {
        if (e is ApiException && e.isUnauthorized) {
          await _clearToken();
        }
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> setServer(String url) async {
    var u = url.trim();
    if (u.isEmpty) u = defaultServer;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    u = u.replaceAll(RegExp(r'/+$'), '');
    api.baseUrl = u;
    await _prefs.setString(_kServer, u);
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final res = asMap(await api.post('/auth/login', {'username': username.trim(), 'password': password}));
    api.token = asStr(res['token']);
    await _prefs.setString(_kToken, api.token!);
    user = AppUser.fromJson(asMap(res['user']));
    _afterLogin();
    notifyListeners();
  }

  void _afterLogin() {
    realtime.connect(api.baseUrl, api.token!);
    _sub?.cancel();
    _sub = realtime.events.listen((e) {
      if (e.event == 'notification') refreshUnread();
    });
    refreshUnread();
  }

  Future<void> refreshUnread() async {
    if (user == null) return;
    try {
      final res = asMap(await api.get('/notifications'));
      unreadNotifications = asInt(res['unread']);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> logout() async {
    if (user == null && api.token == null) return;
    realtime.disconnect();
    _sub?.cancel();
    user = null;
    unreadNotifications = 0;
    await _clearToken();
    notifyListeners();
  }

  Future<void> _clearToken() async {
    api.token = null;
    await _prefs.remove(_kToken);
  }
}

Session get session => Session.instance;

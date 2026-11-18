// A2 Connect cabinet API: login (Telegram deep link / e-mail) and subscription link.

import 'dart:async';

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/views/a2_build.dart';
import 'package:shared_preferences/shared_preferences.dart';

const a2CabinetUrl = 'https://lk.a2-connect.com';
const _api = '$a2CabinetUrl/api/cabinet';

class A2AuthException implements Exception {
  A2AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class A2Api {
  A2Api._();

  static final A2Api instance = A2Api._();

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _api,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
      validateStatus: (_) => true,
    ),
  );

  String? _accessToken;

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    final access = data['access_token'] as String?;
    final refresh = data['refresh_token'] as String?;
    if (access == null) {
      throw A2AuthException('Сервер не вернул ключ входа');
    }
    _accessToken = access;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('a2_refresh_token', refresh ?? '');
    } catch (_) {}
  }

  /// Telegram: returns the t.me link to open and a future that completes
  /// once the user pressed Start in the bot.
  Future<({String link, Future<void> done})> startTelegramLogin() async {
    final res = await _dio.post('/auth/deeplink/request', data: {});
    if (res.statusCode != 200 || res.data is! Map) {
      throw A2AuthException('Не удалось начать вход через Telegram');
    }
    final data = Map<String, dynamic>.from(res.data as Map);
    final token = data['token'] as String;
    final bot = (data['bot_username'] as String?) ?? 'A2_connect_bot';
    final expires = (data['expires_in'] as num?)?.toInt() ?? 300;
    final link = 'https://t.me/$bot?start=webauth_$token';
    final done = _pollDeepLink(token, Duration(seconds: expires));
    return (link: link, done: done);
  }

  Future<void> _pollDeepLink(String token, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final res = await _dio.post(
        '/auth/deeplink/poll',
        data: {'token': token},
      );
      if (res.statusCode == 200 && res.data is Map) {
        await _saveTokens(Map<String, dynamic>.from(res.data as Map));
        return;
      }
      if (res.statusCode == 410) break;
    }
    throw A2AuthException('Время входа истекло. Нажмите «Войти через Telegram» ещё раз');
  }

  Future<void> loginEmail(String email, String password) async {
    final res = await _dio.post(
      '/auth/email/login',
      data: {'email': email.trim(), 'password': password},
    );
    if (res.statusCode == 200 && res.data is Map) {
      await _saveTokens(Map<String, dynamic>.from(res.data as Map));
      return;
    }
    throw A2AuthException(_errorText(res, 'Неверная почта или пароль'));
  }

  /// Login handed over from the browser cabinet (Google, Telegram widget…).
  Future<void> loginWithRefreshToken(String refreshToken) async {
    final res = await _dio.post(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    if (res.statusCode == 200 && res.data is Map) {
      final data = Map<String, dynamic>.from(res.data as Map);
      data['refresh_token'] ??= refreshToken;
      await _saveTokens(data);
      return;
    }
    throw A2AuthException('Не удалось войти. Попробуйте ещё раз');
  }

  /// Browser page that logs in on the cabinet and hands the session back.
  String get browserLoginUrl => '$a2CabinetUrl/?a2app=1';

  Options get _auth =>
      Options(headers: {'Authorization': 'Bearer ${_accessToken ?? ''}'});

  /// Subscription link of the logged-in user, or null if there is none.
  Future<String?> subscriptionUrl() async {
    for (final path in ['/subscription', '/subscriptions']) {
      final res = await _dio.get(path, options: _auth);
      if (res.statusCode == 200) {
        final url = _findUrl(res.data);
        if (url != null) return url;
      }
    }
    return null;
  }

  /// Activates the free trial; returns true on success.
  Future<bool> activateTrial() async {
    final res = await _dio.post('/subscription/trial', data: {}, options: _auth);
    return res.statusCode != null && res.statusCode! < 300;
  }

  static String? _findUrl(Object? data) {
    if (data is Map) {
      final direct = data['subscription_url'];
      if (direct is String && direct.startsWith('http')) return direct;
      for (final value in data.values) {
        final found = _findUrl(value);
        if (found != null) return found;
      }
    } else if (data is List) {
      for (final item in data) {
        final found = _findUrl(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  static String _errorText(Response<dynamic> res, String fallback) {
    final data = res.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    }
    return fallback;
  }
}

/// A newer A2 Connect build published on GitHub, if any.
Future<String?> a2UpdateUrl() async {
  if (a2Build <= 0) return null;
  try {
    final res = await Dio().get<dynamic>(
      'https://api.github.com/repos/areshetov89/a2-connect-app/releases/latest',
      options: Options(validateStatus: (_) => true),
    );
    if (res.statusCode != 200 || res.data is! Map) return null;
    final tag = (res.data as Map)['tag_name'] as String? ?? '';
    final latest = int.tryParse(tag.replaceFirst('build-', '')) ?? 0;
    if (latest <= a2Build) return null;
    final file = Platform.isAndroid
        ? 'A2Connect.apk'
        : Platform.isWindows
            ? 'A2Connect-Setup.exe'
            : 'A2Connect-Mac-Intel.dmg';
    return 'https://a2-connect.com/download/$file';
  } catch (_) {
    return null;
  }
}

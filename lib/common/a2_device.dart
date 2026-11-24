import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

// The A2 panel limits devices by HWID and answers a subscription request
// without these headers with an «App not supported» placeholder.
Future<Map<String, String>>? _headers;

Future<Map<String, String>> a2DeviceHeaders() => _headers ??= _load();

Future<Map<String, String>> _load() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('a2_hwid') ?? '';
    if (id.isEmpty) {
      final random = Random.secure();
      id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await prefs.setString('a2_hwid', id);
    }
    final os = Platform.operatingSystem;
    return {
      'x-hwid': id,
      'x-device-os': os,
      'x-ver-os': _ascii(Platform.operatingSystemVersion),
      'x-device-model': 'A2 Connect $os',
    };
  } catch (_) {
    return const {};
  }
}

String _ascii(String value) =>
    value.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();

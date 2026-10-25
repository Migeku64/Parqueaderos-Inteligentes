import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.details});

  final String message;
  final int status;
  final dynamic details;

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Cliente HTTP de la API REST (Node.js).
class ApiClient {
  ApiClient({required this.baseUrl, this.token, this.onUnauthorized});

  String baseUrl;
  String? token;
  void Function()? onUnauthorized;

  // 60 s: en el plan gratuito de Render el servidor tarda ~50 s en "despertar".
  static const _timeout = Duration(seconds: 60);

  Uri uri(String path, [Map<String, dynamic>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) q[k] = v.toString();
    });
    final u = Uri.parse('$base$path');
    return q.isEmpty ? u : u.replace(queryParameters: q);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => http.get(uri(path, query), headers: _headers));

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _send(() => http.post(uri(path), headers: _headers, body: jsonEncode(body ?? {})));

  Future<dynamic> put(String path, Map<String, dynamic> body) =>
      _send(() => http.put(uri(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> patch(String path, Map<String, dynamic> body) =>
      _send(() => http.patch(uri(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> delete(String path) => _send(() => http.delete(uri(path), headers: _headers));

  /// Descarga texto plano (por ejemplo, reportes CSV).
  Future<String> getText(String path, {Map<String, dynamic>? query}) async {
    final res = await _raw(() => http.get(uri(path, query), headers: _headers));
    return utf8.decode(res.bodyBytes);
  }

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    final res = await _raw(call);
    final text = utf8.decode(res.bodyBytes);
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }

  Future<http.Response> _raw(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      res = await call().timeout(_timeout);
    } on TimeoutException {
      throw ApiException('El servidor no respondió a tiempo. Verifique su conexión.');
    } catch (_) {
      throw ApiException(
          'No se pudo conectar con el servidor ($baseUrl). Verifique la dirección y que el servidor esté encendido.');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;

    String message = 'Error ${res.statusCode}';
    dynamic details;
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['error'] != null) message = body['error'].toString();
      if (body is Map) details = body['details'];
    } catch (_) {}
    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    throw ApiException(message, status: res.statusCode, details: details);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'json.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message, [this.data = const {}]);
  final int status;
  final String message;
  final Json data;
  String? get code => data['code']?.toString();
  @override
  String toString() => message;
}

String errorText(Object error, [String fallback = 'Something went wrong.']) {
  if (error is ApiException) return error.message;
  if (error is TimeoutException) return 'The request timed out. Try again.';
  if (error is FormatException) return error.message;
  final text = '$error';
  if (text.contains('SocketException') || text.contains('ClientException')) {
    return 'Could not reach KTU Assist. Check your connection.';
  }
  return fallback;
}

/// Thin JSON client for `https://api.ktuassist.in/api/`. Paths are relative,
/// e.g. `admin/events`. Responses are returned decoded and unmodified.
class Api {
  Api({http.Client? client}) : _client = client ?? http.Client();
  static final Api instance = Api();

  static const base = 'https://api.ktuassist.in/api/';
  String? token;
  /// Called on HTTP 401 while a token is set. Receives the API message when present.
  void Function(String? message)? onUnauthorized;
  final http.Client _client;

  Map<String, String> _headers({bool json = true}) => {
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json',
    if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  Uri uri(String path, [Map<String, dynamic>? query]) {
    final q = <String, String>{};
    query?.forEach((key, value) {
      if (value != null && '$value'.isNotEmpty) q[key] = '$value';
    });
    final full = path.startsWith('http') ? path : '$base$path';
    final parsed = Uri.parse(full);
    return q.isEmpty
        ? parsed
        : parsed.replace(queryParameters: {...parsed.queryParameters, ...q});
  }

  String _encode(Object? body) => jsonEncode(
    body,
    toEncodable: (value) {
      if (value is DateTime) return value.toUtc().toIso8601String();
      throw FormatException(
        'Cannot encode ${value.runtimeType} in an API request.',
      );
    },
  );

  Future<dynamic> upload(
    String path,
    String field,
    String name,
    Uint8List bytes,
  ) => _send(() async {
    final request = http.MultipartRequest('POST', uri(path))
      ..headers.addAll(_headers(json: false))
      ..files.add(http.MultipartFile.fromBytes(field, bytes, filename: name));
    return http.Response.fromStream(await _client.send(request));
  });

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    Duration? timeout,
  }) =>
      _send(() => _client.get(uri(path, query), headers: _headers()), timeout);

  Future<dynamic> post(String path, [Object? body]) => _send(
    () =>
        _client.post(uri(path), headers: _headers(), body: _encode(body ?? {})),
  );

  Future<dynamic> put(String path, [Object? body]) => _send(
    () =>
        _client.put(uri(path), headers: _headers(), body: _encode(body ?? {})),
  );

  Future<dynamic> patch(String path, [Object? body]) => _send(
    () => _client.patch(
      uri(path),
      headers: _headers(),
      body: _encode(body ?? {}),
    ),
  );

  Future<dynamic> delete(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
  }) => _send(
    () => _client.delete(
      uri(path, query),
      headers: _headers(),
      body: body == null ? null : _encode(body),
    ),
  );

  Future<dynamic> multipart(String path, Map<String, String> fields) =>
      _send(() async {
        final request = http.MultipartRequest('POST', uri(path))
          ..headers.addAll(_headers(json: false))
          ..fields.addAll(fields);
        return http.Response.fromStream(await _client.send(request));
      });

  /// Raw bytes (images, PDFs). The bearer token is only sent to our own API host.
  Future<Uint8List> bytes(String url, {String accept = '*/*'}) async {
    final target = uri(url);
    final own = target.host == Uri.parse(base).host;
    final response = await _client
        .get(
          target,
          headers: {
            'Accept': accept,
            if (own && token != null) 'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode >= 400) {
      final json = _decode(response.body);
      throw ApiException(
        response.statusCode,
        _messageOf(json, 'Could not load the file.'),
        asMap(json),
      );
    }
    return response.bodyBytes;
  }

  Future<dynamic> _send(
    Future<http.Response> Function() run, [
    Duration? timeout,
  ]) async {
    final response = await run().timeout(
      timeout ?? const Duration(seconds: 45),
    );
    final json = _decode(response.body);
    if (response.statusCode >= 400) {
      final message = _messageOf(
        json,
        response.statusCode == 403
            ? 'You do not have permission to do this.'
            : 'Request failed (${response.statusCode}).',
      );
      if (response.statusCode == 401 && token != null) {
        onUnauthorized?.call(message);
      }
      throw ApiException(response.statusCode, message, asMap(json));
    }
    return json;
  }

  dynamic _decode(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  String _messageOf(dynamic json, String fallback) {
    if (json is String && json.trim().isNotEmpty && json.length < 300) {
      return json;
    }
    if (json is Map) {
      final errors = json['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) return '${first.first}';
        if (first is String) return first;
      }
      for (final key in const ['message', 'error']) {
        if (json[key] is String && (json[key] as String).isNotEmpty) {
          return json[key];
        }
      }
    }
    return fallback;
  }
}

Api api = Api.instance;

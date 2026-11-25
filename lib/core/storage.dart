import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'json.dart';

/// Firebase Storage over its REST API, using the same bucket as the web admin.
/// Access is governed by the bucket's security rules, exactly like the web SDK.
class CloudStorage {
  static const bucket = 'ktu-assist-4db4a.appspot.com';
  static const _root = 'https://firebasestorage.googleapis.com/v0/b/$bucket/o';

  static String downloadUrl(String path, String? token) =>
      '$_root/${Uri.encodeComponent(path)}?alt=media${token == null ? '' : '&token=$token'}';

  /// Uploads [bytes] to [path] and returns the public download URL.
  static Future<String> upload(
    String path,
    Uint8List bytes, {
    String contentType = 'application/octet-stream',
    String? cacheControl,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_root?uploadType=media&name=${Uri.encodeQueryComponent(path)}'),
          headers: {
            'Content-Type': contentType,
            'Cache-Control': ?cacheControl,
          },
          body: bytes,
        )
        .timeout(const Duration(minutes: 5));
    final json = asMap(_decode(response.body));
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        str(dig(json, 'error.message'), 'Upload failed (${response.statusCode}).'),
      );
    }
    final token = str(json['downloadTokens']).split(',').first;
    return downloadUrl(str(json['name'], path), token.isEmpty ? null : token);
  }

  static Future<({List<String> folders, List<Json> files})> list(String prefix) async {
    final response = await http.get(
      Uri.parse('$_root?delimiter=/&prefix=${Uri.encodeQueryComponent(prefix)}'),
    );
    final json = asMap(_decode(response.body));
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, str(dig(json, 'error.message'), 'Could not list storage.'));
    }
    return (
      folders: (json['prefixes'] as List? ?? []).map((e) => '$e').toList(),
      files: rowsOf(json['items'] ?? []),
    );
  }

  static Future<String> resolveUrl(String path) async {
    final response = await http.get(Uri.parse('$_root/${Uri.encodeComponent(path)}'));
    final json = asMap(_decode(response.body));
    final token = str(json['downloadTokens']).split(',').first;
    return downloadUrl(path, token.isEmpty ? null : token);
  }

  static Future<void> remove(String path) async {
    final response = await http.delete(Uri.parse('$_root/${Uri.encodeComponent(path)}'));
    if (response.statusCode >= 400) {
      final json = asMap(_decode(response.body));
      throw ApiException(response.statusCode, str(dig(json, 'error.message'), 'Delete failed.'));
    }
  }

  static dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return {};
    }
  }

  static String mimeOf(String name) {
    final ext = name.split('.').last.toLowerCase();
    return const {
          'pdf': 'application/pdf',
          'png': 'image/png',
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'gif': 'image/gif',
          'webp': 'image/webp',
          'svg': 'image/svg+xml',
          'doc': 'application/msword',
          'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'ppt': 'application/vnd.ms-powerpoint',
          'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
          'xls': 'application/vnd.ms-excel',
          'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'txt': 'text/plain',
          'zip': 'application/zip',
          'mp3': 'audio/mpeg',
          'mp4': 'video/mp4',
        }[ext] ??
        'application/octet-stream';
  }

  /// Category names the API expects in `addfile.type`.
  static String categoryOf(String name) {
    final mime = mimeOf(name);
    if (mime.startsWith('image/')) return 'Images';
    if (mime.startsWith('audio/')) return 'Audio';
    if (mime.startsWith('video/')) return 'Video';
    if (mime.contains('zip')) return 'Archives';
    if (mime == 'application/octet-stream') return 'Unknown type';
    return 'Documents';
  }
}

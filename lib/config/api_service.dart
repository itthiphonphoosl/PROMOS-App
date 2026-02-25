import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/auth_storage.dart';
import '../services/app_nav.dart';

class ApiService {
  static const String baseUrl = 'http://172.16.102.82:4030/api';

  // Use a single client type everywhere to avoid middleware mismatch.
  // Your backend routes expect "HH" for some endpoints (start/finish).
  static const String _defaultClientType = 'HH';

  // ── URI helper ─────────────────────────────────────────────
  static Uri _u(String path, [Map<String, String>? qp]) {
    final uri = Uri.parse('$baseUrl$path');
    return (qp == null || qp.isEmpty) ? uri : uri.replace(queryParameters: qp);
  }

  // ── headers ────────────────────────────────────────────────
  static Map<String, String> _headers({
    required String token,
    String clientType = _defaultClientType,
  }) => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
    'x-client-type': clientType,
  };

  static Future<void> _guard(http.Response res) async {
    if (res.statusCode == 401 || res.statusCode == 403) {
      await forceToLogin();
    }
  }

  static Future<String?> _token() async {
    final t = await AuthStorage.getToken();
    if (t == null) {
      await forceToLogin();
      return null;
    }
    return t;
  }

  // ── Auth ───────────────────────────────────────────────────
  static Future<http.Response> login(
    String username,
    String password, {
    String? opStaId,
  }) async {
    final body = <String, dynamic>{'username': username, 'password': password};
    if (opStaId != null && opStaId.isNotEmpty) body['op_sta_id'] = opStaId;

    // IMPORTANT: use "HH" to match requireClientType(["HH"])
    return http.post(
      _u('/auth/login'),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'x-client-type': _defaultClientType,
      },
      body: jsonEncode(body),
    );
  }

  static Future<http.Response> logout() async {
    final token = await _token();
    if (token == null) return http.Response('{"message":"No token"}', 401);

    final res = await http.post(
      _u('/auth/logout'),
      headers: _headers(token: token),
    );
    await _guard(res);
    return res;
  }

  // ── Machines ───────────────────────────────────────────────
  static Future<http.Response> getMachinesInStation() async {
    final token = await _token();
    if (token == null) return http.Response('{"message":"No token"}', 401);

    final res = await http.get(
      _u('/machines/in-station'),
      headers: _headers(token: token),
    );
    await _guard(res);
    return res;
  }

  // ── Parts ──────────────────────────────────────────────────
  /// GET /api/parts?q=...&limit=...
  /// Backend should return: { "parts": [ {part_id, part_no, part_name}, ... ] }
  static Future<http.Response> getParts({String? q, int limit = 500}) async {
    final token = await _token();
    if (token == null) return http.Response('{"message":"No token"}', 401);

    final qp = <String, String>{
      'limit': limit.toString(),
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    };

    final res = await http.get(
      _u('/parts', qp),
      headers: _headers(token: token),
    );
    await _guard(res);
    return res;
  }

  // ── TK Documents ───────────────────────────────────────────
  static Future<http.Response> getTkDocById(String tkId) async {
    final token = await _token();
    if (token == null) return http.Response('{"message":"No token"}', 401);

    final res = await http.get(
      _u('/TKDocs/$tkId'),
      headers: _headers(token: token),
    );
    await _guard(res);
    return res;
  }

  // ── Op Scan ────────────────────────────────────────────────
  static Future<http.Response> startScan({
    required String tkId,
    required String mcId,
  }) async {
    final token = await _token();
    if (token == null) return http.Response('{"message":"No token"}', 401);

    final res = await http.post(
      _u('/op-scan/start'),
      headers: _headers(token: token),
      body: jsonEncode({'tk_id': tkId, 'MC_id': mcId}),
    );
    await _guard(res);
    return res;
  }

  static Future<http.Response> finishScan({
    required String opScId,
    required int goodQty,
    required int scrapQty,
    required List<Map<String, dynamic>> groups,
  }) async {
    final token = await _token();
    if (token == null) return http.Response('{"message":"No token"}', 401);

    final res = await http.post(
      _u('/op-scan/finish'),
      headers: _headers(token: token),
      body: jsonEncode({
        'op_sc_id': opScId,
        'good_qty': goodQty,
        'scrap_qty': scrapQty,
        'groups': groups,
      }),
    );
    await _guard(res);
    return res;
  }

  static Future<http.Response> getActiveScans() async {
    final token = await _token();
    if (token == null) return http.Response('{"message":"No token"}', 401);

    final res = await http.get(
      _u('/op-scan/active'),
      headers: _headers(token: token),
    );
    await _guard(res);
    return res;
  }

  static Future<http.Response> getActiveScanByTkId(String tkId) async {
    final token = await _token();
    if (token == null) return http.Response('{"message":"No token"}', 401);

    final res = await http.get(
      _u('/op-scan/active/$tkId'),
      headers: _headers(token: token),
    );
    await _guard(res);
    return res;
  }

  static Future<http.Response> getSummaryByTkId(String tkId) async {
    final token = await _token();
    if (token == null) return http.Response('{"message":"No token"}', 401);

    final res = await http.get(
      _u('/op-scan/summary/$tkId'),
      headers: _headers(token: token),
    );
    await _guard(res);
    return res;
  }
}

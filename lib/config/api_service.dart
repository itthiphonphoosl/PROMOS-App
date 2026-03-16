import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/auth_storage.dart';
import '../services/app_nav.dart';

class ApiService {
  static const String baseUrl = 'http://172.16.12.154:4030/api';
  static const String _defaultClientType = 'HH';

  static Uri _u(String path, [Map<String, String>? qp]) {
    final uri = Uri.parse('$baseUrl$path');
    return (qp == null || qp.isEmpty) ? uri : uri.replace(queryParameters: qp);
  }

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
    if (res.statusCode == 401) {
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

  // ── Colors ────────────────────────────────────────────────────
  static Future<http.Response> getColors() async {
    final token = await _token();
    if (token == null) return http.Response('{"message":"No token"}', 401);
    final res = await http.get(_u('/colors'), headers: _headers(token: token));
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
    int? colorId,
    List<String> crossTkUnselectedLots =
        const [], // ✅ cross-TK lots ที่ไม่ได้เลือก
  }) async {
    final token = await _token();
    if (token == null) return http.Response('{"message":"No token"}', 401);
    final bodyMap = <String, dynamic>{
      'op_sc_id': opScId,
      'good_qty': goodQty,
      'scrap_qty': scrapQty,
      'groups': groups,
      if (colorId != null) 'color_id': colorId,
      if (crossTkUnselectedLots.isNotEmpty)
        'cross_tk_unselected_lots': crossTkUnselectedLots,
    };
    final res = await http.post(
      _u('/op-scan/finish'),
      headers: _headers(token: token),
      body: jsonEncode(bodyMap),
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

  // ── Parked Lots ────────────────────────────────────────────
  static Future<http.Response> getParkedLots({String? opStaId}) async {
    final token = await _token();
    if (token == null) return http.Response('{"message":"No token"}', 401);
    final qp = <String, String>{
      if (opStaId != null && opStaId.isNotEmpty) 'op_sta_id': opStaId,
    };
    final res = await http.get(
      _u('/op-scan/parked', qp),
      headers: _headers(token: token),
    );
    await _guard(res);
    return res;
  }
}

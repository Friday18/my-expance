import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/expense.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;
}

class Profile {
  const Profile({required this.email, required this.monthlyBudget, required this.currency});
  final String? email;
  final double? monthlyBudget;
  final String currency;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        email: j['email'] as String?,
        monthlyBudget: (j['monthly_budget'] as num?)?.toDouble(),
        currency: (j['currency'] as String?) ?? 'INR',
      );
}

class ChatResult {
  const ChatResult(this.reply, this.actions);
  final String reply;
  final List<Map<String, dynamic>> actions;
}

class ApiClient {
  ApiClient(this._auth, {http.Client? client, String? baseUrl})
      : _http = client ?? http.Client(),
        _base = baseUrl ?? AppConfig.apiBaseUrl;

  final AuthService _auth;
  final http.Client _http;
  final String _base;

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration timeout = const Duration(seconds: 20),
    bool retried = false,
  }) async {
    final token = await _auth.token(forceRefresh: retried);
    final uri = Uri.parse('$_base$path').replace(queryParameters: (query == null || query.isEmpty) ? null : query);
    final req = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }

    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on TimeoutException {
      throw const ApiException('The server took too long to answer. Please try again.');
    } on SocketException {
      throw const ApiException('Can\'t reach the server. Check your internet connection.');
    } on http.ClientException {
      throw const ApiException('Can\'t reach the server. Check your internet connection.');
    }

    // Firebase tokens last an hour; refresh once and retry.
    if (res.statusCode == 401 && !retried && !_auth.devMode) {
      return _send(method, path, query: query, body: body, timeout: timeout, retried: true);
    }

    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 400) {
      String message = 'Something went wrong (${res.statusCode}).';
      try {
        final j = jsonDecode(text);
        if (j is Map && j['error'] is String) message = j['error'] as String;
      } catch (_) {}
      throw ApiException(message, status: res.statusCode);
    }
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }

  // ---------- profile ----------

  Future<Profile> me() async => Profile.fromJson(await _send('GET', '/api/me') as Map<String, dynamic>);

  Future<Profile> updateMe({double? monthlyBudget, bool clearBudget = false, String? currency}) async {
    final body = <String, dynamic>{
      if (clearBudget) 'monthly_budget': null else if (monthlyBudget != null) 'monthly_budget': monthlyBudget,
      if (currency != null) 'currency': currency,
    };
    return Profile.fromJson(await _send('PATCH', '/api/me', body: body) as Map<String, dynamic>);
  }

  Future<void> deleteAccount() => _send('DELETE', '/api/me');

  // ---------- expenses ----------

  Future<List<Expense>> listExpenses({DateTime? start, DateTime? end, String? category}) async {
    final data = await _send('GET', '/api/expenses', query: {
      if (start != null) 'start': formatDay(start),
      if (end != null) 'end': formatDay(end),
      if (category != null) 'category': category,
      'limit': '1000',
    }) as Map<String, dynamic>;
    return (data['expenses'] as List).map((e) => Expense.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Expense> addExpense({
    required double amount,
    required String category,
    String note = '',
    DateTime? spentOn,
  }) async {
    final data = await _send('POST', '/api/expenses', body: {
      'amount': amount,
      'category': category,
      'note': note,
      if (spentOn != null) 'spent_on': formatDay(spentOn),
    });
    return Expense.fromJson(data as Map<String, dynamic>);
  }

  Future<Expense> updateExpense(Expense e) async {
    final data = await _send('PATCH', '/api/expenses/${e.id}', body: {
      'amount': e.amount,
      'category': e.category,
      'note': e.note,
      'spent_on': formatDay(e.spentOn),
    });
    return Expense.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteExpense(int id) => _send('DELETE', '/api/expenses/$id');

  // ---------- assistant ----------

  Future<ChatResult> chat(List<Map<String, String>> messages) async {
    final data = await _send('POST', '/api/chat',
        body: {'messages': messages}, timeout: const Duration(seconds: 90)) as Map<String, dynamic>;
    return ChatResult(
      (data['reply'] as String?) ?? '',
      ((data['actions'] as List?) ?? const []).cast<Map<String, dynamic>>(),
    );
  }
}

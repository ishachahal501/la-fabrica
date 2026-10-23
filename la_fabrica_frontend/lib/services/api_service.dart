import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthVerificationResult {
  final bool isAuthenticated;
  final bool isSessionExpired; // HTTP 401 or 403
  final bool isNetworkOrServerError; // 5xx, socket, timeout
  final Map<String, dynamic>? user;

  const AuthVerificationResult({
    required this.isAuthenticated,
    this.isSessionExpired = false,
    this.isNetworkOrServerError = false,
    this.user,
  });
}

class ApiService {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5000/api',
  );

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt');
  }

  Future<String?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userRole');
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userName');
  }

  Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userEmail');
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userId');
  }

  Future<void> saveUserSession(String token, Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt', token);
    await prefs.setString('userId', (user['id'] ?? user['_id'] ?? '').toString());
    await prefs.setString('userName', user['name'] ?? '');
    await prefs.setString('userEmail', user['email'] ?? '');
    await prefs.setString('userRole', user['role'] ?? 'designer');
    if (user['assignedDesignerId'] != null) {
      await prefs.setString('assignedDesignerId', user['assignedDesignerId'].toString());
    }
  }

  Future<void> logout() async {
    final token = await getToken();
    if (token != null && token.isNotEmpty) {
      try {
        await http.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: {'Authorization': 'Bearer $token'},
        );
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt');
    await prefs.remove('userId');
    await prefs.remove('userName');
    await prefs.remove('userEmail');
    await prefs.remove('userRole');
    await prefs.remove('assignedDesignerId');
  }

  /// Verifies current session against backend, explicitly distinguishing HTTP 401
  /// from network outages or server-side issues so temporary outages don't wipe local sessions.
  Future<AuthVerificationResult> verifyCurrentSession() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return const AuthVerificationResult(isAuthenticated: false, isSessionExpired: true);
    }
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['id'] != null || data['_id'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('userId', (data['id'] ?? data['_id']).toString());
          await prefs.setString('userName', data['name'] ?? '');
          await prefs.setString('userEmail', data['email'] ?? '');
          await prefs.setString('userRole', data['role'] ?? 'designer');
          if (data['assignedDesignerId'] != null) {
            await prefs.setString('assignedDesignerId', data['assignedDesignerId'].toString());
          }
          return AuthVerificationResult(isAuthenticated: true, user: data);
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return const AuthVerificationResult(isAuthenticated: false, isSessionExpired: true);
      } else {
        return const AuthVerificationResult(isAuthenticated: false, isNetworkOrServerError: true);
      }
    } catch (e) {
      print('verifyCurrentSession error: $e');
      return const AuthVerificationResult(isAuthenticated: false, isNetworkOrServerError: true);
    }
    return const AuthVerificationResult(isAuthenticated: false, isNetworkOrServerError: true);
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final result = await verifyCurrentSession();
    return result.user;
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String role,
    String? inviteCode,
    String? assignedDesignerId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'email': email,
          'password': password,
          'role': role,
          if (inviteCode != null && inviteCode.isNotEmpty) 'inviteCode': inviteCode,
          if (assignedDesignerId != null && assignedDesignerId.isNotEmpty) 'assignedDesignerId': assignedDesignerId,
        }),
      );
      final body = json.decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300 && body['token'] != null) {
        await saveUserSession(body['token'], body['user']);
      }
      return {'statusCode': response.statusCode, ...body};
    } catch (e) {
      return {'statusCode': 500, 'message': 'Network connection error. Is backend running?'};
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? expectedRole,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
          if (expectedRole != null) 'expectedRole': expectedRole,
        }),
      );
      final body = json.decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300 && body['token'] != null) {
        await saveUserSession(body['token'], body['user']);
      }
      return {'statusCode': response.statusCode, ...body};
    } catch (e) {
      return {'statusCode': 500, 'message': 'Network connection error. Is backend running?'};
    }
  }

  Future<List<dynamic>> getDesigners() async {
    final token = await getToken();
    try {
      final headers = <String, String>{};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final response = await http.get(Uri.parse('$baseUrl/auth/designers'), headers: headers);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (_) {}
    return [];
  }

  // --- Invitations API ---

  Future<Map<String, dynamic>> createInvitation({String? invitedEmail}) async {
    final token = await getToken();
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/invitations'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          if (invitedEmail != null && invitedEmail.isNotEmpty) 'invitedEmail': invitedEmail,
        }),
      );
      final body = json.decode(response.body);
      return {'statusCode': response.statusCode, ...body};
    } catch (e) {
      return {'statusCode': 500, 'message': 'Network connection error creating invitation.'};
    }
  }

  Future<List<dynamic>> getInvitations() async {
    final token = await getToken();
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/invitations'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> validateInvitation(String code) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/invitations/validate?code=${Uri.encodeComponent(code)}'),
      );
      final body = json.decode(response.body);
      return {'statusCode': response.statusCode, ...body};
    } catch (e) {
      return {'statusCode': 500, 'message': 'Failed to validate invitation.'};
    }
  }

  // --- Designs API ---

  Future<List<dynamic>> getDesigns() async {
    final token = await getToken();
    if (token == null) return [];
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/designs'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('getDesigns error: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> createDesign({
    required String name,
    required String apparelType,
    int initialStock = 50,
    double unitPrice = 700,
  }) async {
    final token = await getToken();
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/designs'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'name': name,
          'apparelType': apparelType,
          'initialStock': initialStock,
          'unitPrice': unitPrice,
        }),
      );
      return json.decode(response.body);
    } catch (e) {
      return {'message': 'Error creating design'};
    }
  }

  Future<Map<String, dynamic>> updateDesign(
    String id, {
    String? name,
    String? apparelType,
    String? previewImage,
    String? designData,
  }) async {
    final token = await getToken();
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/designs/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          if (name != null) 'name': name,
          if (apparelType != null) 'apparelType': apparelType,
          if (previewImage != null) 'previewImage': previewImage,
          if (designData != null) 'designData': designData,
        }),
      );
      return json.decode(response.body);
    } catch (e) {
      return {'message': 'Error updating design'};
    }
  }

  Future<Map<String, dynamic>?> getDesignById(String id) async {
    final token = await getToken();
    if (token == null) return null;
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/designs/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('getDesignById error: $e');
    }
    return null;
  }

  // --- Inventory API ---

  Future<List<dynamic>> getInventory() async {
    final token = await getToken();
    if (token == null) return [];
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/inventory'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('getInventory error: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> updateInventoryItem(
    String id, {
    int? stockQuantity,
    double? unitPrice,
    String? action,
    int? quantity,
    String? note,
    int? lowStockThreshold,
  }) async {
    final token = await getToken();
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/inventory/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          if (stockQuantity != null) 'stockQuantity': stockQuantity,
          if (unitPrice != null) 'unitPrice': unitPrice,
          if (action != null) 'action': action,
          if (quantity != null) 'quantity': quantity,
          if (note != null) 'note': note,
          if (lowStockThreshold != null) 'lowStockThreshold': lowStockThreshold,
        }),
      );
      return json.decode(response.body);
    } catch (e) {
      return {'message': 'Error updating inventory'};
    }
  }

  Future<Map<String, dynamic>> getInventorySummary() async {
    final token = await getToken();
    if (token == null) return {};
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/inventory/dashboard/summary'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('getInventorySummary error: $e');
    }
    return {};
  }
}
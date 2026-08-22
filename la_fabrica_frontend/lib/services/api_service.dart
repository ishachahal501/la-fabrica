import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:5000/api';

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
    await prefs.setString('userId', user['id'] ?? '');
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

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return null;
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
          return data;
        }
      }
    } catch (e) {
      print('getCurrentUser error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String role,
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
          if (assignedDesignerId != null) 'assignedDesignerId': assignedDesignerId,
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
    try {
      final response = await http.get(Uri.parse('$baseUrl/auth/designers'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (_) {}
    return [];
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
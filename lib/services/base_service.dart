import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class BaseService {
  static const String baseUrl = 'https://advert.softacular.net/api';
  
  // Retry configuration
  static const int maxRetries = 2; // Maximum number of retries for failed requests
  static const Duration retryDelay = Duration(seconds: 1); // Delay between retries
  
  // Default timeouts
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  
  // สร้าง HTTP Client ที่ไม่ตรวจสอบใบรับรอง SSL
  http.Client createUnsecureClient() {
    HttpClient httpClient = HttpClient();
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    httpClient.connectionTimeout = connectionTimeout;
    
    return IOClient(httpClient);
  }
  
  // GET request with retry
  Future<Map<String, dynamic>> get(String endpoint, {Map<String, String>? headers, Map<String, dynamic>? queryParams}) async {
    return _executeWithRetry(() => _performGetRequest(endpoint, headers: headers, queryParams: queryParams));
  }
  
  // POST request with retry
  Future<Map<String, dynamic>> post(String endpoint, dynamic body, {Map<String, String>? headers}) async {
    return _executeWithRetry(() => _performPostRequest(endpoint, body, headers: headers));
  }
  
  // PUT request with retry
  Future<Map<String, dynamic>> put(String endpoint, dynamic body, {Map<String, String>? headers}) async {
    return _executeWithRetry(() => _performPutRequest(endpoint, body, headers: headers));
  }
  
  // Basic GET implementation
  Future<Map<String, dynamic>> _performGetRequest(String endpoint, {Map<String, String>? headers, Map<String, dynamic>? queryParams}) async {
    final client = createUnsecureClient();
    
    try {
      Uri uri = Uri.parse('$baseUrl/$endpoint');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams.map((key, value) => MapEntry(key, value.toString())));
      }
      
      Map<String, String> requestHeaders = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      
      if (headers != null) {
        requestHeaders.addAll(headers);
      }
      
      print('📺 TV - BaseService - GET Request: ${uri.toString()}');
      print('📺 TV - BaseService - Headers: $requestHeaders');
      
      final response = await client.get(uri, headers: requestHeaders);
      return _handleResponse(response);
    } catch (e) {
      print('📺 TV - BaseService - GET Error: $e');
      throw Exception('Failed to perform GET request: $e');
    } finally {
      client.close();
    }
  }
  
  // Basic POST implementation
  Future<Map<String, dynamic>> _performPostRequest(String endpoint, dynamic body, {Map<String, String>? headers}) async {
    final client = createUnsecureClient();
    
    try {
      final uri = Uri.parse('$baseUrl/$endpoint');
      
      Map<String, String> requestHeaders = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      
      if (headers != null) {
        requestHeaders.addAll(headers);
      }
      
      final encodedBody = json.encode(body);
      
      print('📺 TV - BaseService - POST Request: ${uri.toString()}');
      print('📺 TV - BaseService - Headers: $requestHeaders');
      print('📺 TV - BaseService - Body: $encodedBody');
      
      final response = await client.post(uri, headers: requestHeaders, body: encodedBody);
      return _handleResponse(response);
    } catch (e) {
      print('📺 TV - BaseService - POST Error: $e');
      throw Exception('Failed to perform POST request: $e');
    } finally {
      client.close();
    }
  }
  
  // Basic PUT implementation
  Future<Map<String, dynamic>> _performPutRequest(String endpoint, dynamic body, {Map<String, String>? headers}) async {
    final client = createUnsecureClient();
    
    try {
      final uri = Uri.parse('$baseUrl/$endpoint');
      
      Map<String, String> requestHeaders = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      
      if (headers != null) {
        requestHeaders.addAll(headers);
      }
      
      final encodedBody = json.encode(body);
      
      print('📺 TV - BaseService - PUT Request: ${uri.toString()}');
      print('📺 TV - BaseService - Headers: $requestHeaders');
      print('📺 TV - BaseService - Body: $encodedBody');
      
      final response = await client.put(uri, headers: requestHeaders, body: encodedBody);
      return _handleResponse(response);
    } catch (e) {
      print('📺 TV - BaseService - PUT Error: $e');
      throw Exception('Failed to perform PUT request: $e');
    } finally {
      client.close();
    }
  }
  
  // Handle HTTP response
  Map<String, dynamic> _handleResponse(http.Response response) {
    print('📺 TV - BaseService - Response Status: ${response.statusCode}');
    print('📺 TV - BaseService - Response Body: ${response.body}');
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Success response
      try {
        if (response.body.isEmpty) {
          return {'success': true};
        }
        return json.decode(response.body) as Map<String, dynamic>;
      } catch (e) {
        print('📺 TV - BaseService - JSON Parse Error: $e');
        throw Exception('Failed to parse response: $e');
      }
    } else {
      // Error response
      String errorMessage = 'Request failed with status: ${response.statusCode}';
      
      try {
        if (response.body.isNotEmpty) {
          final errorData = json.decode(response.body) as Map<String, dynamic>;
          if (errorData.containsKey('error')) {
            errorMessage = errorData['error'];
          } else if (errorData.containsKey('message')) {
            errorMessage = errorData['message'];
          }
        }
      } catch (e) {
        print('📺 TV - BaseService - Error JSON Parse Failed: $e');
      }
      
      // Handle specific status codes
      if (response.statusCode == 401) {
        throw Exception('Unauthorized: $errorMessage');
      } else if (response.statusCode == 404) {
        throw Exception('Not found: $errorMessage');
      } else if (response.statusCode >= 500) {
        throw Exception('Server error: $errorMessage');
      }
      
      throw Exception(errorMessage);
    }
  }
  
  // Execute with retry logic
  Future<Map<String, dynamic>> _executeWithRetry(Future<Map<String, dynamic>> Function() requestFn) async {
    int attempts = 0;
    
    while (true) {
      attempts++;
      
      try {
        return await requestFn();
      } catch (e) {
        // Only retry on certain conditions (server errors, timeouts)
        final shouldRetry = (e.toString().contains('Server error') || 
                           e.toString().contains('SocketException') ||
                           e.toString().contains('TimeoutException')) && 
                          attempts <= maxRetries;
                          
        if (shouldRetry) {
          print('📺 TV - BaseService - Retrying request (attempt $attempts of $maxRetries)...');
          // Wait before retrying
          await Future.delayed(retryDelay);
          continue;
        }
        
        // If we shouldn't retry or have exceeded max retries, rethrow
        rethrow;
      }
    }
  }
} 
// services/ad_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'device_service.dart';

class AdService {
  final String baseUrl;
  final DeviceService _deviceService = DeviceService();
  
  // For error handling
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;
  DateTime? _lastErrorTime;
  static const int _errorCooldownMinutes = 5;
  
  // For caching
  static const String _cacheKey = 'ad_schedules_cache';
  static const Duration _cacheDuration = Duration(minutes: 15);
  DateTime? _lastFetchTime;
  
  // เพิ่มตัวแปรสำหรับติดตาม resync time
  static DateTime? _lastResyncTime;
  
  // Constructor with default API base URL
  AdService({String? baseUrl}) : baseUrl = baseUrl ?? ApiConfig.baseUrl;
  
  // เมธอดสำหรับบันทึกเวลา resync
  static void recordResyncTime() {
    _lastResyncTime = DateTime.now();
    print('📺 TV - AdService: Recorded resync time: $_lastResyncTime');
  }
  
  // ตรวจสอบว่าเป็น 403 error ที่เกิดขึ้นหลัง resync หรือไม่
  bool _is403AfterResync() {
    if (_lastResyncTime == null) return false;
    final timeSinceResync = DateTime.now().difference(_lastResyncTime!);
    return timeSinceResync.inSeconds < 30; // ถ้าเกิดภายใน 30 วินาทีหลัง resync
  }
  
  // Fetch current schedules from API or cache
  Future<List<Map<String, dynamic>>> getCurrentSchedules() async {
    // ล้างแคชทุกครั้งก่อนเรียกข้อมูลใหม่เพื่อป้องกันการใช้ข้อมูลเก่า
    // ข้อมูลจะถูกแคชใหม่เมื่อเรียก API สำเร็จ
    await clearCache();
    
    // Check if we should use cached data to avoid spamming a failing API
    if (_shouldUseCache()) {
      final cachedData = await _getFromCache();
      if (cachedData.isNotEmpty) {
        print('📺 TV - AdService: Using cached schedules');
        return cachedData;
      }
    }
    
    try {
      // ดึงข้อมูล device credentials
      final credentials = await _deviceService.getDeviceCredentials();
      final Map<String, String> headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      
      // ถ้ามี access token ให้ใส่ในส่วนหัวการเรียก API
      if (credentials != null && credentials.containsKey('access_token')) {
        headers['Authorization'] = 'Bearer ${credentials['access_token']}';
        print('📺 TV - AdService: Using authorization token for API request');
      } else {
        print('📺 TV - AdService: No authorization token available');
      }
      
      // ใช้ URL พื้นฐานสำหรับการดึงตารางเวลา (ไม่ต้องแนบ device ID ในพาธ)
      String apiUrl = '$baseUrl/device/schedules';
      
      // แสดงข้อมูล device ID ที่ใช้ (ถ้ามี) แต่ใช้ token แทนในการส่งข้อมูล
      if (credentials != null && credentials.containsKey('device_id')) {
        // เพิ่ม device_id เป็น query parameter
        apiUrl = '$apiUrl?device_id=${credentials['device_id']}';
        print('📺 TV - AdService: Requesting schedules for device ID: ${credentials['device_id']}');
      }
      
      // Try to fetch fresh data from API
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        // Reset error count on success
        _consecutiveErrors = 0;
        _lastFetchTime = DateTime.now();
        
        // Parse response data
        final data = jsonDecode(response.body);
        print('📺 TV - AdService: Response data: $data');
        
        // ตรวจสอบรูปแบบข้อมูลทั้งแบบเก่า (schedules) และแบบใหม่ (message)
        List<dynamic> schedulesJson = [];
        
        if (data.containsKey('schedules')) {
          // รูปแบบเก่า
          schedulesJson = data['schedules'] ?? [];
          print('📺 TV - AdService: ใช้รูปแบบข้อมูลแบบเก่า (schedules)');
        } else if (data.containsKey('message') && data['message'] is List) {
          // รูปแบบใหม่
          schedulesJson = data['message'] ?? [];
          print('📺 TV - AdService: ใช้รูปแบบข้อมูลแบบใหม่ (message)');
        } else {
          print('📺 TV - AdService: ไม่พบข้อมูลโฆษณาในรูปแบบที่รองรับ');
        }
        
        // แสดงข้อมูลโฆษณาที่ได้รับ
        print('📺 TV - AdService: Schedules JSON: $schedulesJson');
        
        final List<Map<String, dynamic>> schedules = schedulesJson
            .cast<Map<String, dynamic>>()
            .where((schedule) => _isScheduleValid(schedule))
            .toList();
        
        // แสดงข้อมูลโฆษณาที่ผ่านการตรวจสอบความถูกต้อง
        print('📺 TV - AdService: Valid schedules: $schedules');
        
        // Cache this data
        await _saveToCache(schedules);
        
        return schedules;
      } else if (response.statusCode == 401) {
        // กรณี Token หมดอายุ (401 Unauthorized)
        final responseBody = response.body;
        
        print('📺 TV - AdService: API error 401: $responseBody');
        
        // ตรวจสอบว่าเป็น token หมดอายุหรือไม่
        if (responseBody.contains('expired') || 
            responseBody.contains('Unauthenticated') || 
            responseBody.contains('Token has expired')) {
          
          print('📺 TV - AdService: Token has expired, attempting to refresh...');
          
          // ลองเรียก refresh token และดึงข้อมูลอีกครั้ง
          return await _refreshAndRetry();
        } else {
          // กรณีอื่นๆ ที่ไม่ใช่ token หมดอายุ
          _handleApiError();
          return await _getFromCache(); // Fall back to cache
        }
      } else if (response.statusCode == 403) {
        // กรณี Forbidden (403) - อุปกรณ์ถูกเพิกถอนสิทธิ์หรือถูก revoke
        print('📺 TV - AdService: API error 403: ${response.body}');
        
        // ตรวจสอบว่าเป็น 403 error ที่เกิดขึ้นหลัง resync หรือไม่
        if (_is403AfterResync()) {
          print('📺 TV - AdService: 403 error occurred shortly after resync, waiting 5 seconds before retry...');
          
          // รอ 5 วินาทีแล้วลองใหม่
          await Future.delayed(const Duration(seconds: 5));
          
          print('📺 TV - AdService: Retrying API call after 403 error...');
          
          // ลองเรียก API อีกครั้ง
          try {
            final retryResponse = await http.get(
              Uri.parse(apiUrl),
              headers: headers,
            ).timeout(const Duration(seconds: 10));
            
            if (retryResponse.statusCode == 200) {
              print('📺 TV - AdService: Retry successful after 403 error');
              
              // Reset error count on success
              _consecutiveErrors = 0;
              _lastFetchTime = DateTime.now();
              
              final data = jsonDecode(retryResponse.body);
              
              // แปลงข้อมูลเช่นเดียวกับเมธอดหลัก
              List<dynamic> schedulesJson = [];
              if (data.containsKey('schedules')) {
                schedulesJson = data['schedules'] ?? [];
              } else if (data.containsKey('message') && data['message'] is List) {
                schedulesJson = data['message'] ?? [];
              }
              
              final List<Map<String, dynamic>> schedules = schedulesJson
                  .cast<Map<String, dynamic>>()
                  .where((schedule) => _isScheduleValid(schedule))
                  .toList();
              
              // Cache this data
              await _saveToCache(schedules);
              
              return schedules;
            } else {
              print('📺 TV - AdService: Retry failed with status: ${retryResponse.statusCode}');
            }
          } catch (retryError) {
            print('📺 TV - AdService: Retry attempt failed: $retryError');
          }
        }
        
        // ถ้าไม่ใช่กรณีหลัง resync หรือ retry ไม่สำเร็จ ให้ส่งสัญญาณ device_revoked
        throw Exception('device_revoked');
      } else {
        // Handle other API errors
        print('📺 TV - AdService: API error ${response.statusCode}: ${response.body}');
        _handleApiError();
        return await _getFromCache(); // Fall back to cache
      }
    } on TimeoutException {
      print('📺 TV - AdService: API request timed out');
      _handleApiError();
      return await _getFromCache();
    } on SocketException {
      print('📺 TV - AdService: No internet connection');
      _handleApiError();
      return await _getFromCache();
    } catch (e) {
      print('📺 TV - AdService: Error fetching schedules: $e');
      
      // ถ้าเป็น device_revoked exception ให้ throw ต่อไป
      if (e.toString().contains('device_revoked')) {
        print('📺 TV - AdService: Re-throwing device_revoked exception');
        rethrow;
      }
      
      _handleApiError();
      return await _getFromCache();
    }
  }
  
  // Validate a schedule has minimum required fields
  bool _isScheduleValid(Map<String, dynamic> schedule) {
    // Check if it has a URL
    final url = schedule['url']?.toString() ?? '';
    if (url.isEmpty) {
      return false;
    }
    
    // Validate dates if present
    if (schedule['start_date'] != null || schedule['end_date'] != null) {
      try {
        // If start date is specified, check if it's in the future
        if (schedule['start_date'] != null) {
          final startDate = DateTime.parse(schedule['start_date'].toString());
          if (DateTime.now().isBefore(startDate)) {
            return false; // Schedule not yet active
          }
        }
        
        // If end date is specified, check if it's in the past
        if (schedule['end_date'] != null) {
          final endDate = DateTime.parse(schedule['end_date'].toString());
          if (DateTime.now().isAfter(endDate)) {
            return false; // Schedule expired
          }
        }
      } catch (e) {
        print('📺 TV - AdService: Error validating schedule dates: $e');
        return false;
      }
    }
    
    return true;
  }
  
  // Handle API errors with exponential backoff
  void _handleApiError() {
    _consecutiveErrors++;
    _lastErrorTime = DateTime.now();
    print('📺 TV - AdService: Consecutive errors: $_consecutiveErrors');
  }
  
  // Determine if we should use cache based on error history
  bool _shouldUseCache() {
    // Always check cache first
    if (_lastFetchTime == null) {
      return true; // No fetch yet, try cache
    }
    
    // If cache is recent enough, use it first
    if (DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
      return true;
    }
    
    // If we've had too many errors, back off for a while
    if (_consecutiveErrors >= _maxConsecutiveErrors && 
        _lastErrorTime != null &&
        DateTime.now().difference(_lastErrorTime!).inMinutes < _errorCooldownMinutes) {
      return true;
    }
    
    return false;
  }
  
  // Get cached schedules
  Future<List<Map<String, dynamic>>> _getFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_cacheKey);
      
      if (jsonString != null) {
        final List<dynamic> decodedData = jsonDecode(jsonString);
        return decodedData.cast<Map<String, dynamic>>();
      }
      
      return [];
    } catch (e) {
      print('📺 TV - AdService: Error reading from cache: $e');
      return [];
    }
  }
  
  // Save schedules to cache
  Future<void> _saveToCache(List<Map<String, dynamic>> schedules) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(schedules);
      await prefs.setString(_cacheKey, jsonString);
    } catch (e) {
      print('📺 TV - AdService: Error saving to cache: $e');
    }
  }
  
  // Clear the cache
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      print('📺 TV - AdService: Cache cleared');
    } catch (e) {
      print('📺 TV - AdService: Error clearing cache: $e');
    }
  }
  
  // เรียก refresh token และพยายามดึงข้อมูลอีกครั้ง
  Future<List<Map<String, dynamic>>> _refreshAndRetry() async {
    try {
      // เรียกใช้ refresh token
      final refreshResult = await _deviceService.refreshToken();
      
      if (refreshResult['success'] == true) {
        print('📺 TV - AdService: Token refreshed successfully, retrying API call');
        
        // ดึงข้อมูล credentials ใหม่
        final credentials = await _deviceService.getDeviceCredentials();
        
        // สร้าง headers ใหม่พร้อม token ที่ refresh แล้ว
        final Map<String, String> headers = {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        };
        
        if (credentials != null && credentials.containsKey('access_token')) {
          headers['Authorization'] = 'Bearer ${credentials['access_token']}';
        }
        
        // เตรียม URL
        String apiUrl = '$baseUrl/device/schedules';
        if (credentials != null && credentials.containsKey('device_id')) {
          apiUrl = '$apiUrl?device_id=${credentials['device_id']}';
        }
        
        // ลองเรียก API อีกครั้งด้วย token ใหม่
        final response = await http.get(
          Uri.parse(apiUrl),
          headers: headers,
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          // Reset error count on success
          _consecutiveErrors = 0;
          _lastFetchTime = DateTime.now();
          
          final data = jsonDecode(response.body);
          
          // แปลงข้อมูลเช่นเดียวกับเมธอดหลัก
          List<dynamic> schedulesJson = [];
          if (data.containsKey('schedules')) {
            schedulesJson = data['schedules'] ?? [];
          } else if (data.containsKey('message') && data['message'] is List) {
            schedulesJson = data['message'] ?? [];
          }
          
          final List<Map<String, dynamic>> schedules = schedulesJson
              .cast<Map<String, dynamic>>()
              .where((schedule) => _isScheduleValid(schedule))
              .toList();
          
          // Cache this data
          await _saveToCache(schedules);
          
          return schedules;
        } else if (response.statusCode == 403) {
          // กรณี Forbidden (403) - อุปกรณ์ถูกเพิกถอนสิทธิ์หรือถูก revoke แม้หลังจาก refresh token
          print('📺 TV - AdService: API retry failed with 403: ${response.body}');
          
          // ล้างข้อมูล credentials เพื่อให้กลับไปที่หน้า QR code (ในกรณีนี้ล้างได้เพราะลองแล้ว)
          await _deviceService.clearCredentials();
          
          // ต้องส่งสัญญาณกลับไปว่าต้องไปหน้า QR code
          throw Exception('device_revoked');
        } else {
          print('📺 TV - AdService: API retry failed with status: ${response.statusCode}');
          _handleApiError();
          return await _getFromCache();
        }
      } else {
        // Refresh token ไม่สำเร็จ - ตรวจสอบว่าเป็นกรณีที่ต้อง re-pair หรือไม่
        final message = refreshResult['message']?.toString().toLowerCase() ?? '';
        print('📺 TV - AdService: Failed to refresh token: ${refreshResult['message']}');
        
        // ตรวจสอบข้อความที่บอกว่าต้อง re-pair หรือ resync
        if (message.contains('re-pair') || 
            message.contains('resync') || 
            message.contains('token is invalid') ||
            message.contains('token_invalid') ||
            message.contains('please re-pair')) {
          
          print('📺 TV - AdService: Token refresh indicates re-pairing is needed');
          
          // ล้างข้อมูล credentials เพื่อให้กลับไปที่หน้า QR code
          await _deviceService.clearCredentials();
          
          // ส่งสัญญาณว่าอุปกรณ์ต้องถูก re-pair
          throw Exception('device_revoked');
        }
        
        _handleApiError();
        return await _getFromCache();
      }
    } catch (e) {
      // ถ้าเป็น device_revoked exception ให้ throw ต่อไป
      if (e.toString().contains('device_revoked')) {
        print('📺 TV - AdService: Re-throwing device_revoked exception from refresh and retry');
        rethrow;
      }
      
      print('📺 TV - AdService: Error during token refresh and retry: $e');
      _handleApiError();
      return await _getFromCache();
    }
  }
} 
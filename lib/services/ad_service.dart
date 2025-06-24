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
    // 1. พยายามดึงข้อมูลใหม่จาก API ก่อนเสมอ
    try {
      final credentials = await _deviceService.getDeviceCredentials();
      final Map<String, String> headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      if (credentials != null && credentials.containsKey('access_token')) {
        headers['Authorization'] = 'Bearer ${credentials['access_token']}';
      }
      
      String apiUrl = '$baseUrl/device/schedules';
      if (credentials != null && credentials.containsKey('device_id')) {
        apiUrl = '$apiUrl?device_id=${credentials['device_id']}';
      }

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      // 2. ถ้าดึงข้อมูลสำเร็จ
      if (response.statusCode == 200) {
        print('📺 TV - AdService: Successfully fetched new schedules from API.');
        _consecutiveErrors = 0;
        _lastFetchTime = DateTime.now();

        final data = jsonDecode(response.body);
        List<dynamic> schedulesJson = data['schedules'] ?? data['message'] ?? [];
        
        final List<Map<String, dynamic>> schedules = schedulesJson
            .cast<Map<String, dynamic>>()
            .where((schedule) => _isScheduleValid(schedule))
            .toList();
        
        // ล้างแคชเก่า แล้วบันทึกของใหม่
        await _saveToCache(schedules);
        
        return schedules;

      } else if (response.statusCode == 401) {
        // จัดการ Token หมดอายุ
        return await _refreshAndRetry();
      } else if (response.statusCode == 403) {
        // จัดการอุปกรณ์ถูกถอนสิทธิ์
        throw Exception('device_revoked');
      } else {
        // กรณีอื่นๆ ที่ไม่ใช่ 200 ให้ถือว่าล้มเหลว
        throw Exception('API failed with status code: ${response.statusCode}');
      }
    } 
    // 3. ถ้าการดึงข้อมูลจากเน็ตเวิร์กล้มเหลว (เข้าสู่ catch block)
    catch (e) {
      if (e.toString().contains('device_revoked')) {
        rethrow; // ส่งต่อไปให้ BLoC จัดการ
      }

      print('📺 TV - AdService: Failed to fetch from API ($e). Falling back to cache.');
      _handleApiError();

      // ให้ไปดึงข้อมูลจากแคชมาใช้แทน
      return await _getFromCache();
    }
  }  // Validate a schedule has minimum required fields
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
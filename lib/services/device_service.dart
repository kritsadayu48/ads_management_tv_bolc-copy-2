import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/io_client.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'base_service.dart';

class DeviceService {
  static const String _baseUrl = 'https://advert.softacular.net/api';
  static const String _clientIdKey = 'tv_device_client_id';
  static const String _deviceCredentialsKey = 'tv_device_credentials';
  
  final BaseService _baseService = BaseService();
  
  // Generate a unique client ID based on TV properties
  Future<String> getUniqueClientId() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if we already have a stored client ID
    String? storedClientId = prefs.getString(_clientIdKey);
    if (storedClientId != null && storedClientId.isNotEmpty) {
      return storedClientId;
    }

    // Generate new client ID
    String clientId = await _generateUniqueClientId();
    
    // Store for future use
    await prefs.setString(_clientIdKey, clientId);
    
    return clientId;
  }

  // Generate a unique ID for the TV
  Future<String> _generateUniqueClientId() async {
    final deviceInfo = DeviceInfoPlugin();
    String deviceId = '';
    
    try {
      // ดึงข้อมูลอุปกรณ์ตามแพลตฟอร์ม
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // ใช้ทั้งชื่ออุปกรณ์และ Android ID ต่อกัน
        deviceId = '${androidInfo.brand} ${androidInfo.model}_${androidInfo.id}';
        print('📺 TV - Android device: ${androidInfo.brand} ${androidInfo.model}');
        print('📺 TV - Android ID จริงของอุปกรณ์: ${androidInfo.id}');
        print('📺 TV - รวมเป็น Client ID: $deviceId');
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = '${iosInfo.model}_${iosInfo.identifierForVendor}';
        print('📺 TV - iOS device: ${iosInfo.model}');
        print('📺 TV - iOS ID จริงของอุปกรณ์: ${iosInfo.identifierForVendor}');
        print('📺 TV - รวมเป็น Client ID: $deviceId');
      } else if (Platform.isMacOS) {
        final macOSInfo = await deviceInfo.macOsInfo;
        deviceId = '${macOSInfo.model}_${macOSInfo.systemGUID}';
        print('📺 TV - macOS device: ${macOSInfo.model}');
        print('📺 TV - macOS ID จริงของอุปกรณ์: ${macOSInfo.systemGUID}');
        print('📺 TV - รวมเป็น Client ID: $deviceId');
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        deviceId = '${linuxInfo.prettyName ?? "Linux"}_${linuxInfo.machineId}';
        print('📺 TV - Linux device: ${linuxInfo.prettyName}');
        print('📺 TV - Linux ID จริงของอุปกรณ์: ${linuxInfo.machineId}');
        print('📺 TV - รวมเป็น Client ID: $deviceId');
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        deviceId = '${windowsInfo.computerName}_${windowsInfo.deviceId}';
        print('📺 TV - Windows device: ${windowsInfo.computerName}');
        print('📺 TV - Windows ID จริงของอุปกรณ์: ${windowsInfo.deviceId}');
        print('📺 TV - รวมเป็น Client ID: $deviceId');
      }
    } catch (e) {
      print('📺 TV - Error getting device info: $e');
    }
    
    // ถ้าไม่สามารถดึงข้อมูลอุปกรณ์ได้ ให้ใช้ค่าเริ่มต้น
    if (deviceId.isEmpty) {
      print('📺 TV - ไม่สามารถดึงข้อมูลอุปกรณ์ได้ ใช้ค่าเริ่มต้น');
      deviceId = 'Unknown Device ${DateTime.now().millisecondsSinceEpoch}';
    }
    
    print('📺 TV - Generated Client ID: $deviceId');
    return deviceId;
  }
  
  // สร้างตัวอักษรสุ่ม
  String _generateRandomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      List.generate(length, (index) => chars.codeUnitAt(random.nextInt(chars.length)))
    );
  }

  // ประกาศอุปกรณ์ทีวีและรอการจับคู่กับอุปกรณ์มือถือ
  Future<Map<String, dynamic>> announceDevice() async {
    try {
      String clientId = await getUniqueClientId();
      
      print('\n==================================================');
      print('📺 TV - Announcing device with client_id: $clientId');
      
      try {
        final responseData = await _baseService.post(
          'pairing/announce',
          {'client_id': clientId}
        );
        
        // แสดงข้อมูลทั้งหมดที่ได้รับจาก API เพื่อตรวจสอบ
        print('📺 TV - ==================== ANNOUNCE RESPONSE DATA ====================');
        responseData.forEach((key, value) {
          print('📺 TV - $key: $value');
        });
        print('📺 TV - =============================================================');
        print('==================================================\n');
        
        // ตรวจสอบและส่งข้อมูลกลับ
        return {
          'success': true,
          'message': responseData['message'] ?? 'รอการจับคู่กับอุปกรณ์มือถือ',
          'pairing_code_expires_in_seconds': responseData['pairing_code_expires_in_seconds'] ?? 900,
        };
      } catch (e) {
        // ถ้าเกิดข้อผิดพลาด
        print('📺 TV - Error: $e');
        return {
          'success': false,
          'error': 'ไม่สามารถประกาศอุปกรณ์: $e',
        };
      }
    } catch (e) {
      print('📺 TV - Error announcing device: $e');
      return {
        'success': false,
        'error': 'เกิดข้อผิดพลาด: ${e.toString()}',
      };
    }
  }
  
  // บันทึกข้อมูลการเข้าถึง (credentials) ลงใน SharedPreferences
  Future<bool> saveDeviceCredentials(Map<String, dynamic> credentials) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String credentialsJson = json.encode(credentials);
      await prefs.setString(_deviceCredentialsKey, credentialsJson);
      print('📺 TV - บันทึกข้อมูล device_credentials ลงใน SharedPreferences');
      
      if (credentials.containsKey('device_id')) {
        print('📺 TV - 🆔 [SAVED DEVICE ID] = ${credentials['device_id']}');
      }
      
      return true;
    } catch (e) {
      print('📺 TV - ไม่สามารถบันทึกข้อมูล credentials: $e');
      return false;
    }
  }
  
  // ดึงข้อมูลการเข้าถึง (credentials) จาก SharedPreferences
  Future<Map<String, dynamic>?> getDeviceCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? credentialsJson = prefs.getString(_deviceCredentialsKey);
      
      if (credentialsJson != null && credentialsJson.isNotEmpty) {
        final credentials = json.decode(credentialsJson) as Map<String, dynamic>;
        if (credentials.containsKey('device_id')) {
          print('📺 TV - 🆔 [GET DEVICE ID] = ${credentials['device_id']}');
        }
        return credentials;
      }
      return null;
    } catch (e) {
      print('📺 TV - ไม่สามารถดึงข้อมูล credentials: $e');
      return null;
    }
  }
  
  // ตรวจสอบว่ามีการบันทึกข้อมูล credentials หรือไม่
  Future<bool> hasStoredCredentials() async {
    final credentials = await getDeviceCredentials();
    return credentials != null && 
           credentials.containsKey('device_id') && 
           credentials.containsKey('access_token');
  }
  
  // ล้างข้อมูล credentials ที่บันทึกไว้
  Future<bool> clearCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_deviceCredentialsKey);
      print('📺 TV - ล้างข้อมูล credentials สำเร็จ');
      return true;
    } catch (e) {
      print('📺 TV - เกิดข้อผิดพลาดในการล้างข้อมูล credentials: $e');
      return false;
    }
  }

  // ตรวจสอบสถานะการจับคู่กับอุปกรณ์มือถือ
  Future<Map<String, dynamic>> checkPairingStatus({String? clientId}) async {
    try {
      String deviceId = clientId ?? await getUniqueClientId();
      
      print('Checking pairing status for client_id: $deviceId');
      
      try {
        final responseData = await _baseService.get('pairing/status/$deviceId');

        print('==================== STATUS RESPONSE DATA ====================');
        responseData.forEach((key, value) {
          print('$key: $value');
        });
        print('============================================================');
        
        // บันทึกข้อมูล device_credentials ถ้ามีในการตอบกลับ
        if (responseData.containsKey('device_credentials')) {
          if (responseData['device_credentials'] is Map && 
              responseData['device_credentials'].containsKey('device_id')) {
            print('📺 TV - ⭐ [NEW DEVICE ID RECEIVED] = ${responseData['device_credentials']['device_id']}');
          }
          await saveDeviceCredentials(responseData['device_credentials']);
        }
        
        return {
          'status': responseData['status'] ?? 'unknown',
          'success': true,
          'message': responseData['message'],
          'device_credentials': responseData['device_credentials'],
        };
      } catch (e) {
        // ถ้าเกิดข้อผิดพลาด
        return {
          'error': 'ไม่สามารถตรวจสอบสถานะ: $e',
          'status': 'error',
          'success': false,
        };
      }
    } catch (e) {
      print('Error checking pairing status: $e');
      return {
        'error': 'เกิดข้อผิดพลาด: ${e.toString()}',
        'status': 'error',
        'success': false,
      };
    }
  }

  // ตรวจสอบสถานะของอุปกรณ์ว่าได้รับการจับคู่แล้วหรือไม่
  Future<Map<String, dynamic>> checkDeviceStatus() async {
    try {
      String clientId = await getUniqueClientId();
      
      print('Checking device status for client_id: $clientId');
      
      try {
        final responseData = await _baseService.get('devices/status/$clientId');

        // ข้อมูลการตอบกลับจะมีรูปแบบต่างๆ ตามการตอบสนองของเซิร์ฟเวอร์
        return {
          'success': true,
          'is_paired': responseData['is_paired'] ?? false,
          'device_name': responseData['device_name'],
          'device_id': responseData['device_id'],
          'message': responseData['message'] ?? 'ตรวจสอบสถานะอุปกรณ์สำเร็จ',
        };
      } catch (e) {
        // กรณีเกิดข้อผิดพลาด ให้ถือว่ายังไม่มีการจับคู่
        return {
          'success': false,
          'is_paired': false,
          'message': 'ไม่สามารถตรวจสอบสถานะอุปกรณ์ได้ ($e)',
        };
      }
    } catch (e) {
      print('Error checking device status: $e');
      return {
        'success': false,
        'is_paired': false,
        'message': 'เกิดข้อผิดพลาดในการตรวจสอบสถานะอุปกรณ์: $e',
      };
    }
  }

  // ล้าง client ID ที่บันทึกไว้
  Future<bool> clearClientId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_clientIdKey);
      print('📺 TV - ล้าง client ID สำเร็จ');
      return true;
    } catch (e) {
      print('📺 TV - เกิดข้อผิดพลาดในการล้าง client ID: $e');
      return false;
    }
  }

  // เรียกใช้ refresh token เพื่อขอ access token ใหม่
  Future<Map<String, dynamic>> refreshToken() async {
    try {
      // ดึงข้อมูล credentials เดิม
      final credentials = await getDeviceCredentials();
      if (credentials == null || !credentials.containsKey('access_token')) {
        print('📺 TV - ไม่พบข้อมูล token สำหรับการ refresh');
        return {
          'success': false,
          'message': 'ไม่พบข้อมูล token',
        };
      }

      // สร้าง HTTP client แบบไม่ตรวจสอบ SSL certificate
      final client = _baseService.createUnsecureClient();
      String refreshUrl = '$_baseUrl/device/token/refresh';
      
      print('📺 TV - กำลังเรียก refresh token API: $refreshUrl');
      
      try {
        // ใช้ access token ปัจจุบันเพื่อเรียก refresh
        final response = await client.post(
          Uri.parse(refreshUrl),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer ${credentials['access_token']}',
          },
          body: json.encode({
            'device_id': credentials['device_id'],
          }),
        ).timeout(const Duration(seconds: 15));
        
        // ปิด HTTP client
        client.close();
        
        print('�� TV - Refresh token response status: ${response.statusCode}');
        
        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          print('�� TV - Refresh token successful: ${responseData['message'] ?? "Token refreshed"}');
          
          // ตรวจสอบว่ามี token ใหม่ในการตอบกลับหรือไม่
          if (responseData.containsKey('access_token')) {
            // สร้าง credentials ใหม่โดยเก็บข้อมูลอื่นจาก credentials เดิม
            final newCredentials = Map<String, dynamic>.from(credentials);
            newCredentials['access_token'] = responseData['access_token'];
            
            // ถ้ามี refresh_token ใหม่ ให้อัปเดตด้วย
            if (responseData.containsKey('refresh_token')) {
              newCredentials['refresh_token'] = responseData['refresh_token'];
            }
            
            // บันทึก credentials ที่อัปเดตแล้ว
            await saveDeviceCredentials(newCredentials);
            
            return {
              'success': true,
              'access_token': responseData['access_token'],
              'message': 'ต่ออายุ token สำเร็จ',
            };
          } else {
            print('📺 TV - ไม่พบ token ใหม่ในการตอบกลับ');
            return {
              'success': false,
              'message': 'ไม่พบ token ใหม่ในการตอบกลับ',
            };
          }
        } else {
          print('📺 TV - Refresh token failed with status: ${response.statusCode}');
          print('📺 TV - Response body: ${response.body}');
          
          return {
            'success': false,
            'message': 'ต่ออายุ token ไม่สำเร็จ: HTTP ${response.statusCode}',
          };
        }
      } catch (e) {
        print('📺 TV - เกิดข้อผิดพลาดขณะเรียก refresh token API: $e');
        return {
          'success': false,
          'message': 'เกิดข้อผิดพลาดขณะเรียก refresh token: $e',
        };
      }
    } catch (e) {
      print('📺 TV - เกิดข้อผิดพลาดในการ refresh token: $e');
      return {
        'success': false,
        'message': 'เกิดข้อผิดพลาดในการ refresh token: $e',
      };
    }
  }
} 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/device_service.dart';
import '../services/ad_service.dart';
import 'home_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/ad_bloc.dart';

class QrGeneratorScreen extends StatefulWidget {
  const QrGeneratorScreen({super.key});

  @override
  State<QrGeneratorScreen> createState() => _QrGeneratorScreenState();
}

class _QrGeneratorScreenState extends State<QrGeneratorScreen> {
  final DeviceService _deviceService = DeviceService();
  String _clientId = '';
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _expirationTimer;
  int _remainingSeconds = 0;
  
  // สถานะการประกาศอุปกรณ์และการรอจับคู่
  bool _isAnnounced = false;
  String? _announceMessage;
  int _pairingRemainingSeconds = 0;
  Timer? _pairingTimer;
  
  // สถานะการจับคู่
  String _pairingStatus = 'unknown';
  Timer? _statusCheckTimer;
  
  // ตัวแปรสำหรับตั้งเวลา QR code หมดอายุ (902 วินาที)
  static const int qrCodeExpirySeconds = 902;
  Timer? _qrRefreshTimer;

  @override
  void initState() {
    super.initState();
    
    // บังคับให้แสดงแนวนอนเสมอสำหรับทีวี (เฉพาะหน้านี้)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    // ซ่อน system UI สำหรับทีวี
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    
    _loadDeviceData();
  }
  
  @override
  void dispose() {
    _expirationTimer?.cancel();
    _pairingTimer?.cancel();
    _statusCheckTimer?.cancel();
    _qrRefreshTimer?.cancel(); // เพิ่มการยกเลิก timer ใหม่
    
    // คืนค่า system UI เมื่อออกจากหน้า (ให้หน้าอื่นทำงานปกติ)
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: [],
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    super.dispose();
  }

  Future<void> _loadDeviceData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _expirationTimer?.cancel();
      _statusCheckTimer?.cancel();
      _qrRefreshTimer?.cancel(); // ยกเลิก timer เมื่อโหลดข้อมูลใหม่
    });

    try {
      // ดึง client_id จากอุปกรณ์โดยตรง
      _clientId = await _deviceService.getUniqueClientId();
      
      print('\n==================================================');
      print('📺 TV - Client ID ของอุปกรณ์: $_clientId');
      print('📺 TV - ใช้ client_id นี้โดยตรงสำหรับสร้าง QR code');
      print('==================================================\n');
      
      setState(() {
        _isLoading = false;
      });
      
      // ประกาศอุปกรณ์ทันที
      _announceDevice();
      
      // เริ่มนับถอยหลังสำหรับ QR code หมดอายุ (902 วินาที)
      _startQrRefreshTimer();
    } catch (e) {
      setState(() {
        _errorMessage = 'เกิดข้อผิดพลาด: ${e.toString()}';
        _isLoading = false;
      });
    }
  }
  
  // เริ่มนับถอยหลังเพื่อรีเฟรช QR code
  void _startQrRefreshTimer() {
    _qrRefreshTimer?.cancel();
    int remainingQrSeconds = qrCodeExpirySeconds;
    
    print('📺 TV - เริ่มนับถอยหลังสำหรับรีเฟรช QR code: $remainingQrSeconds วินาที');
    
    _qrRefreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remainingQrSeconds--;
      setState(() {
        // อัปเดตค่า _remainingSeconds ให้สัมพันธ์กับเวลาที่เหลือของ QR code
        _remainingSeconds = remainingQrSeconds;
      });
      
      if (remainingQrSeconds <= 0) {
        print('📺 TV - QR code หมดอายุหลังจาก $qrCodeExpirySeconds วินาที กำลังสร้างใหม่...');
        timer.cancel();
        
        // ล้าง client ID เพื่อสร้างใหม่
        _regenerateClientId();
      }
    });
  }

  // ประกาศอุปกรณ์และรอการจับคู่
  Future<void> _announceDevice() async {
    try {
      final announceResult = await _deviceService.announceDevice();
      
      if (mounted) {
        // เก็บข้อมูลโดยไม่เปลี่ยนหน้าจอ
        _isAnnounced = announceResult['success'] ?? false;
        
        if (_isAnnounced) {
          _announceMessage = announceResult['message'];
          int pairingSeconds = announceResult['pairing_code_expires_in_seconds'] ?? 900;
          
          // เพิ่มเวลาอีก 2 วินาทีตามที่ต้องการ
          pairingSeconds += 2;
          
          print('📺 TV - ได้รับเวลาหมดอายุจาก API: ${pairingSeconds-2} วินาที (เพิ่มอีก 2 วินาที = $pairingSeconds วินาที)');
          
          // เปลี่ยนให้ใช้เวลาจาก API แทนค่าคงที่ 15 นาที
          _startExpirationTimer(pairingSeconds ~/ 60); // แปลงวินาทีเป็นนาที
          _startPairingTimer(pairingSeconds);
          
          // เริ่มตรวจสอบสถานะการจับคู่
          _startStatusCheck();
        } else {
          _announceMessage = announceResult['error'] ?? 'เกิดข้อผิดพลาดในการประกาศอุปกรณ์';
          
          // ถ้าประกาศไม่สำเร็จ ให้ใช้เวลาคงที่ 15 นาที
          _startExpirationTimer(15);
        }
      }
    } catch (e) {
      print('Error announcing device: ${e.toString()}');
      
      // ถ้าเกิดข้อผิดพลาด ให้ใช้เวลาคงที่ 15 นาที
      _startExpirationTimer(15);
    }
  }
  
  // เริ่มตรวจสอบสถานะการจับคู่เป็นระยะ
  void _startStatusCheck() {
    // ล้าง timer เดิมถ้ามี
    _statusCheckTimer?.cancel();
    
    // ตรวจสอบทันที
    _checkPairingStatus();
    
    // ตั้ง timer สำหรับตรวจสอบทุก 2 วินาที (เดิมเป็น 5 วินาที)
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkPairingStatus();
    });
  }
  
  // ตรวจสอบสถานะการจับคู่จาก API
  Future<void> _checkPairingStatus() async {
    try {
      final statusResult = await _deviceService.checkPairingStatus(clientId: _clientId);
      
      if (mounted && statusResult['success'] == true) {
        final status = statusResult['status'] as String;
        
        print('📺 TV - ตรวจสอบสถานะ: $status');
        print('📺 TV - ข้อมูลสถานะเต็ม: $statusResult');
        
        // อัปเดตสถานะเฉพาะเมื่อมีการเปลี่ยนแปลง
        if (_pairingStatus != status) {
          print('📺 TV - พบการเปลี่ยนแปลงสถานะจาก $_pairingStatus เป็น $status');
          
          setState(() {
            _pairingStatus = status;
            
            // บันทึกข้อความที่ได้รับจาก API (ถ้ามี)
            if (statusResult.containsKey('message')) {
              _announceMessage = statusResult['message'];
            }
          });
          
          // ถ้าจับคู่สำเร็จหรือมีการเรียกร้องจับคู่
          if (status == 'claimed' || status == 'paired' || status == 'credentials_delivered' || status == 'resynced') {
            // หยุด timer สำหรับตรวจสอบสถานะและนับถอยหลัง
            _statusCheckTimer?.cancel();
            _pairingTimer?.cancel();
            
            // แสดงข้อความสำเร็จ
            setState(() {
              _announceMessage = statusResult['message'] ?? 'การจับคู่สำเร็จ! อุปกรณ์นี้ถูกเชื่อมต่อกับแอปพลิเคชันมือถือแล้ว';
            });
            
            // ตรวจสอบและบันทึกข้อมูล device_credentials ถ้ามี
            String deviceId = '';
            if (statusResult.containsKey('device_credentials')) {
              print('📺 TV - ได้รับข้อมูล credentials ใหม่');
              
              // ดึง device_id จาก credentials
              if (statusResult['device_credentials'] is Map &&
                  statusResult['device_credentials'].containsKey('device_id')) {
                deviceId = statusResult['device_credentials']['device_id'];
                print('📺 TV - Device ID from credentials: $deviceId');
              }
            } else {
              // ถ้าไม่มี device_credentials ในการตอบกลับ ให้พยายามดึงจากที่บันทึกไว้
              deviceId = await _getStoredDeviceId() ?? '';
              print('📺 TV - ใช้ Device ID ที่บันทึกไว้แล้ว: $deviceId');
            }
            
            // ให้เปลี่ยนหน้าเมื่อสถานะเป็น claimed, paired, credentials_delivered หรือ resynced
            if ((status == 'claimed' || status == 'paired' || status == 'credentials_delivered' || status == 'resynced') && mounted) {
              print('📺 TV - การจับคู่สำเร็จ กำลังเตรียมเปลี่ยนไปยังหน้าหลัก');
              
              // บันทึกเวลา resync สำหรับ AdService
              AdService.recordResyncTime();
              
              // รอ 2 วินาทีเพื่อให้ผู้ใช้เห็นข้อความก่อน (ลดจาก 3 วินาทีเป็น 2 วินาที)
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  print('📺 TV - กำลังเปลี่ยนไปยังหน้าหลักด้วย Device ID: $deviceId');
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => MultiBlocProvider(
                        providers: [
                          BlocProvider<AdBloc>(
                            create: (context) => AdBloc(
                              deviceId: deviceId,
                              adService: AdService(),
                              deviceService: DeviceService(),
                            ),
                          ),
                        ],
                        child: AdPlayerScreen(deviceId: deviceId),
                      ),
                    ),
                  );
                }
              });
            }
          }
        }
      }
    } catch (e) {
      print('📺 TV - Error checking pairing status: ${e.toString()}');
    }
  }
  
  void _startExpirationTimer(int minutes) {
    // แปลงเป็นวินาที
    _remainingSeconds = minutes * 60;
    setState(() {});  // เพียงแค่อัปเดตครั้งแรก
    
    _expirationTimer?.cancel();
    _expirationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
      } else {
        _expirationTimer?.cancel();
        // สร้าง QR code ใหม่เมื่อหมดอายุ
        _loadDeviceData();
      }
    });
  }
  
  void _startPairingTimer(int seconds) {
    _pairingRemainingSeconds = seconds;
    
    _pairingTimer?.cancel();
    _pairingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_pairingRemainingSeconds > 0) {
        _pairingRemainingSeconds--;
      } else {
        _pairingTimer?.cancel();
        // เมื่อหมดเวลารอการจับคู่ ให้โหลด QR code ใหม่
        _loadDeviceData();
      }
    });
  }
  
  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
  
  // แปลสถานะการจับคู่เป็นข้อความไทย
  // String _getPairingStatusText() {
  //   switch (_pairingStatus) {
  //     case 'waiting_for_claim':
  //       return 'รอการจับคู่จากอุปกรณ์มือถือ';
  //     case 'claimed':
  //       return 'อุปกรณ์มือถือได้ร้องขอการจับคู่แล้ว';
  //     case 'paired':
  //       return 'จับคู่สำเร็จ';
  //     case 'rejected':
  //       return 'การจับคู่ถูกปฏิเสธ';
  //     case 'expired':
  //       return 'การจับคู่หมดอายุ';
  //     case 'unknown':
  //     default:
  //       return 'กำลังตรวจสอบสถานะการจับคู่';
  //   }
  // }
  
  // // แปลสถานะการจับคู่เป็นสี
  Color _getPairingStatusColor() {
    switch (_pairingStatus) {
      case 'waiting_for_claim':
        return Colors.orange;
      case 'claimed':
        return Colors.blue;
      case 'paired':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'expired':
        return Colors.red;
      case 'unknown':
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    // บังคับแนวนอนใน build() ด้วยเพื่อให้แน่ใจว่าไม่ถูก override
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    return Scaffold(
      body: Container(
        // เต็มหน้าจอ สำหรับทีวี
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade900, Colors.blue.shade700],
          ),
        ),
        child: OrientationBuilder(
          builder: (context, orientation) {
            // ถ้าไม่ใช่แนวนอน ให้บังคับเปลี่ยนเป็นแนวนอน
            if (orientation == Orientation.portrait) {
              SystemChrome.setPreferredOrientations([
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]);
            }
            
            return _isLoading 
              ? _buildLoadingView() 
              : _errorMessage != null
                ? _buildErrorView()
                : _buildQrCodeView();
          },
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
          const SizedBox(
            width: 100,
            height: 100,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 8,
            ),
          ),
          const SizedBox(height: 40),
                const Text(
            'กำลังสร้าง QR Code...',
                  style: TextStyle(
              fontSize: 40,
                    fontWeight: FontWeight.bold,
              color: Colors.white,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(50),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.red.shade100,
              size: 120,
            ),
            const SizedBox(height: 40),
            Text(
              _errorMessage ?? 'เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ',
              style: const TextStyle(
                fontSize: 32,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 60),
            ElevatedButton(
              onPressed: _loadDeviceData,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue.shade800,
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                textStyle: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('ลองใหม่'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrCodeView() {
    // ใช้ client_id เป็นข้อมูล QR code โดยตรง
    String qrData = _clientId;
    
    print('ข้อมูลที่จะแสดงใน QR code: $qrData');
    
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
            // ส่วนหัวของหน้าจอ
            const Text(
              'ลงทะเบียนอุปกรณ์ทีวี',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'สแกน QR Code ด้วยโทรศัพท์มือถือหรือแท็บเล็ตเพื่อลงทะเบียนอุปกรณ์นี้',
              style: TextStyle(
                fontSize: 24,
                color: Colors.white,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            
                        // แสดงแนวนอนเสมอสำหรับ TV
            // ใช้ LayoutBuilder เพื่อให้แน่ใจว่าใช้พื้นที่อย่างเหมาะสม
            LayoutBuilder(
              builder: (context, constraints) {
                // คำนวณขนาดที่เหมาะสมสำหรับ QR Code
                double maxQrSize = math.min(constraints.maxWidth * 0.3, 250.0);
                
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ฝั่งซ้าย - QR Code
                    Container(
                      width: maxQrSize,
                      height: maxQrSize,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    // ฝั่งขวา - รายละเอียด
                    Expanded(
                      child: _buildDetailsSection(constraints.maxWidth - maxQrSize - 40),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      );
  }

  // สร้าง section สำหรับแสดงรายละเอียด
  Widget _buildDetailsSection(double? width) {
    return Container(
      width: width,
      constraints: BoxConstraints(
        maxWidth: width ?? double.infinity,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tv, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'รหัสอุปกรณ์: $_clientId',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          ),
          
          if (_remainingSeconds > 0) ...[
            const SizedBox(height: 16),
            _buildTimerDisplay(),
          ],
            
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: Colors.white70, size: 20),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'เมื่อลงทะเบียนแล้ว คุณจะสามารถควบคุมการแสดงผลบนอุปกรณ์นี้ได้ผ่านแอปพลิเคชันบนมือถือ',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // สร้าง Widget สำหรับแสดงเวลานับถอยหลัง
  Widget _buildTimerDisplay() {
    String timeText = _formatTime(_remainingSeconds);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'QR Code หมดอายุใน: $timeText',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
  
  // ล้าง client ID และสร้าง ID ใหม่
  Future<void> _regenerateClientId() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      // ล้าง client ID เก่า
      await _deviceService.clearClientId();
      print('📺 TV - กำลังสร้าง QR code ใหม่โดยใช้ข้อมูลอุปกรณ์จริง');
      
      // โหลดข้อมูลใหม่
      await _loadDeviceData();
    } catch (e) {
      setState(() {
        _errorMessage = 'เกิดข้อผิดพลาดในการสร้าง QR code ใหม่: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ดึง device ID จาก credentials ที่บันทึกไว้
  Future<String?> _getStoredDeviceId() async {
    try {
      final credentials = await _deviceService.getDeviceCredentials();
      if (credentials != null && credentials.containsKey('device_id')) {
        return credentials['device_id'];
      }
      return null;
    } catch (e) {
      print('📺 TV - ไม่สามารถดึง device ID จาก credentials ที่บันทึกไว้: $e');
      return null;
    }
  }
} 
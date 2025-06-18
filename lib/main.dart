// main.dart - BLoC Setup for Android TV
import 'dart:io';
import 'package:ads_management_tv/screens/home_screen.dart';
import 'package:ads_management_tv/widgets/bloc_provider_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import your files
import 'blocs/ad_bloc.dart';
import 'events/ad_events.dart';
import 'services/ad_service.dart';
import 'services/device_service.dart';
import 'screens/qr_generator_screen.dart';

// Custom HTTP override to bypass SSL checks
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

// BLoC Observer for debugging - Type Safe Version
class SimpleBlocObserver extends BlocObserver {
  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    print('📺 BLoC Event: ${bloc.runtimeType} - $event');
  }

  @override
  void onTransition(Bloc bloc, Transition transition) {
    super.onTransition(bloc, transition);
    print('📺 BLoC Transition: ${bloc.runtimeType} - ${transition.currentState.runtimeType} -> ${transition.nextState.runtimeType}');
  }

  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    print('📺 BLoC Change: ${bloc.runtimeType} - ${change.currentState.runtimeType} -> ${change.nextState.runtimeType}');
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    print('📺 BLoC Error: ${bloc.runtimeType} - $error');
    // Only print stack trace in debug mode
    if (error.toString().contains('Critical') || error.toString().contains('Fatal')) {
      print('📺 BLoC StackTrace: $stackTrace');
    }
  }
}

void main() async {
  // ต้องเรียกก่อนใช้ Flutter widgets
  WidgetsFlutterBinding.ensureInitialized();
  
  // ตั้งค่า HTTP overrides เพื่อให้สามารถเชื่อมต่อกับ server ที่มี SSL certificate ที่ไม่ถูกต้องได้
  HttpOverrides.global = MyHttpOverrides();
  
  // Set up BLoC observer
  Bloc.observer = SimpleBlocObserver();
  
  // ตรวจสอบว่ามีการจับคู่อุปกรณ์แล้วหรือไม่
  final deviceService = DeviceService();
  final hasCredentials = await deviceService.hasStoredCredentials();
  
  // รันแอปด้วยหน้าจอเริ่มต้นที่เหมาะสม
  runApp(MyApp(isDevicePaired: hasCredentials));
}

class MyApp extends StatelessWidget {
  final bool isDevicePaired;
  
  const MyApp({Key? key, required this.isDevicePaired}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TV Ad Player - BLoC',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: isDevicePaired 
        ? FutureBuilder<Map<String, dynamic>?>(
            future: DeviceService().getDeviceCredentials(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasData && snapshot.data != null) {
                final deviceId = snapshot.data!['device_id'] ?? '';
                print('📺 TV - Main: Loading AdPlayerScreen with device ID: $deviceId');
                
                return MultiBlocProvider(
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
                );
              } else {
                print('📺 TV - Main: No device credentials found, showing QR screen');
                return const QrGeneratorScreen();
              }
            },
          )
        : const QrGeneratorScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DeviceCheckScreen extends StatefulWidget {
  const DeviceCheckScreen({Key? key}) : super(key: key);

  @override
  State<DeviceCheckScreen> createState() => _DeviceCheckScreenState();
}

class _DeviceCheckScreenState extends State<DeviceCheckScreen> {
  late final DeviceService _deviceService;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _deviceService = DeviceService();
    _checkDeviceCredentials();
  }

  Future<void> _checkDeviceCredentials() async {
    try {
      // เปลี่ยนจาก getDeviceId() เป็น method ที่ถูกต้อง
      final hasCredentials = await _deviceService.hasStoredCredentials();
      
      if (hasCredentials) {
        // ดึง device ID จาก credentials
        final credentials = await _deviceService.getDeviceCredentials();
        final deviceId = credentials?['device_id'] ?? '';
        
        if (deviceId.isNotEmpty) {
          // Device is registered, navigate to ad player with BLoC
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => BlocProvider<AdBloc>(
                  create: (context) => AdBloc(
                    deviceId: deviceId,
                    adService: AdService(),
                    deviceService: _deviceService,
                  ),
                  child: AdPlayerScreen(deviceId: deviceId),
                ),
              ),
            );
          }
        } else {
          _navigateToQRScreen();
        }
      } else {
        // No device registered, show QR screen
        _navigateToQRScreen();
      }
    } catch (e) {
      print('Error checking device credentials: $e');
      _navigateToQRScreen();
    }
  }

  void _navigateToQRScreen() {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const QrGeneratorScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(40),
              ),
              child: const Icon(
                Icons.tv,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            const Text(
              'กำลังตรวจสอบอุปกรณ์...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Performance-optimized BLoC setup
class AdBlocProvider extends StatelessWidget {
  final String deviceId;
  final Widget child;

  const AdBlocProvider({
    Key? key,
    required this.deviceId,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdBloc>(
      create: (context) => AdBloc(
        deviceId: deviceId,
        adService: AdService(),
        deviceService: DeviceService(),
      ),
      lazy: false, // Immediately create for TV performance
      child: child,
    );
  }
}

// Extension for better error handling
extension AdBlocX on AdBloc {
  void handleVideoError(String url) {
    add(HandleError('Video initialization failed for: $url'));
  }
  
  void skipAd() {
    add(SkipToNext());
  }
  
  void refreshAds() {
    add(FetchAdvertisements());
  }
}
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/advertisement.dart';
import '../services/ad_service.dart';
import '../services/device_service.dart';
import '../events/ad_events.dart';
import '../states/ad_states.dart';

class AdBloc extends Bloc<AdEvent, AdState> {
  final String deviceId;
  final AdService _adService;
  final DeviceService _deviceService;

  List<Advertisement> _advertisements = [];
  Advertisement? _currentAd;
  int _currentAdIndex = 0;

  Timer? _adTimer;
  Timer? _scheduleFetchTimer;

  AdBloc({
    required this.deviceId,
    required AdService adService,
    required DeviceService deviceService,
  })  : _adService = adService,
        _deviceService = deviceService,
        super(AdInitial()) {
    on<InitializeAd>(_onInitializeAd);
    on<FetchAdvertisements>(_onFetchAdvertisements);
    on<PlayNextAd>(_onPlayNextAd);
    on<VideoCompleted>(_onVideoCompleted); // นำ event handler กลับมา
    on<SkipToNext>(_onSkipToNext);
    on<HandleError>(_onHandleError);
  }

  // onInitializeAd, onFetchAdvertisements, onSkipToNext, onHandleError เหมือนเดิม
  // ... (ใส่โค้ดส่วนนั้นไว้)

  Future<void> _onPlayNextAd(PlayNextAd event, Emitter<AdState> emit) async {
    _adTimer?.cancel();

    if (_advertisements.isEmpty) {
      emit(AdNoContent());
      return;
    }

    _currentAd = _advertisements[_currentAdIndex];
    print('📺 Android TV - Playing next ad: ${_currentAd!.title ?? _currentAd!.id} (type: ${_currentAd!.type})');
    
    emit(AdPlaying(currentAd: _currentAd!));

    // *** แยก Logic การตั้งเวลาตามประเภทของสื่อ ***
    if (_currentAd!.type == 'image') {
      // ถ้าเป็นรูปภาพ, ใช้ Timer ตาม duration จาก API
      int duration = _currentAd!.durationSeconds > 0 ? _currentAd!.durationSeconds : 10;
      
      _adTimer = Timer(Duration(seconds: duration), () {
        // เมื่อครบเวลา ให้เล่นตัวถัดไป
        if (!isClosed) {
          _moveToNextAd();
          add(PlayNextAd());
        }
      });
    }
    // ถ้าเป็นวิดีโอ, จะไม่ทำอะไรในนี้ แต่จะรอ Event 'VideoCompleted' จาก Player แทน
    // ยกเว้นกรณีมีวิดีโอเดียว จะถูกจัดการด้วย isLooping ใน Player อยู่แล้ว
  }

  // Event handler สำหรับวิดีโอที่เล่นจบ
  Future<void> _onVideoCompleted(VideoCompleted event, Emitter<AdState> emit) async {
    // Event นี้จะถูกเรียกจาก VideoPlayerWidget เมื่อวิดีโอเล่นจบจริงๆ
    // จะไม่ถูกเรียกถ้ามีวิดีโอเดียวและกำลัง Loop อยู่
    print('📺 Android TV - Video completed event received, moving to next ad.');
    _moveToNextAd();
    add(PlayNextAd());
  }

  void _moveToNextAd() {
    if (_advertisements.isNotEmpty) {
      _currentAdIndex = (_currentAdIndex + 1) % _advertisements.length;
    }
  }

  // --- โค้ดส่วนที่เหลือ ---
  Future<void> _onInitializeAd(InitializeAd event, Emitter<AdState> emit) async {
    emit(AdLoading());
    _setupTimers();
    add(FetchAdvertisements());
  }

  Future<void> _onFetchAdvertisements(FetchAdvertisements event, Emitter<AdState> emit) async {
    try {
      final schedules = await _adService.getCurrentSchedules();
      if (schedules.isEmpty) {
        emit(AdNoContent());
        return;
      }
      final newAds = schedules
          .map((schedule) => Advertisement.fromJson(schedule))
          .where((ad) => ad.content.isNotEmpty)
          .toList();

      if (newAds.isEmpty) {
        emit(AdNoContent());
        return;
      }
      final hasChanges = _hasAdvertisementsChanged(_advertisements, newAds);
      if (hasChanges || _advertisements.isEmpty) {
        _advertisements = newAds;
        _currentAdIndex = 0;
        _currentAd = null;
        add(PlayNextAd());
      } else if (_currentAd == null) {
        add(PlayNextAd());
      }
    } catch (e) {
      if (e.toString().contains('device_revoked')) {
        await _deviceService.clearCredentials();
        emit(AdError(message: 'Device revoked', isDeviceRevoked: true));
      } else {
        add(HandleError('Failed to fetch advertisements: $e'));
      }
    }
  }

  Future<void> _onSkipToNext(SkipToNext event, Emitter<AdState> emit) async {
    _adTimer?.cancel();
    _moveToNextAd();
    add(PlayNextAd());
  }
  
  Future<void> _onHandleError(HandleError event, Emitter<AdState> emit) async {
    emit(AdError(message: event.error));
    await Future.delayed(const Duration(seconds: 3));
    if (!isClosed) {
      _moveToNextAd();
      add(PlayNextAd());
    }
  }

  void _setupTimers() {
    _scheduleFetchTimer?.cancel();
    _scheduleFetchTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!isClosed) {
        add(FetchAdvertisements());
      }
    });
  }

  bool _hasAdvertisementsChanged(List<Advertisement> oldAds, List<Advertisement> newAds) {
    if (oldAds.length != newAds.length) return true;
    final oldIds = oldAds.map((ad) => ad.id).toSet();
    final newIds = newAds.map((ad) => ad.id).toSet();
    return !oldIds.containsAll(newIds) || !newIds.containsAll(oldIds);
  }

  @override
  Future<void> close() {
    _adTimer?.cancel();
    _scheduleFetchTimer?.cancel();
    return super.close();
  }
  
  
  List<Advertisement> get advertisements => _advertisements;
  Advertisement? get currentAd => _currentAd;

  int get totalVideoCount =>
      _advertisements.where((ad) => ad.type == 'video').length;
}
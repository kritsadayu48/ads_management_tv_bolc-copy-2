import 'dart:async';
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import '../models/advertisement.dart';
import '../services/ad_service.dart';
import '../services/device_service.dart';
import '../events/ad_events.dart';
import '../states/ad_states.dart';
import '../helpers/http_helper.dart';

class AdBloc extends Bloc<AdEvent, AdState> {
  final String deviceId;
  final AdService _adService;
  final DeviceService _deviceService;

  final log = Logger('');

  // Core data
  List<Advertisement> _advertisements = [];
  Advertisement? _currentAd;
  int _currentAdIndex = 0;

  // Timers
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
    on<VideoCompleted>(_onVideoCompleted);

    // *** เพิ่มบรรทัดนี้กลับเข้าไปใน Constructor ***
    on<HandleError>(_onHandleError);
  }

  Future<void> _onHandleError(HandleError event, Emitter<AdState> emit) async {
    
    print('📺 Android TV - BLoC: Handling error: ${event.error}');
    emit(AdError(message: event.error));

    // หน่วงเวลาเล็กน้อยแล้วข้ามไปโฆษณาตัวถัดไป
    await Future.delayed(const Duration(seconds: 3));
    if (!isClosed) {
      _moveToNextAd();
      add(PlayNextAd());
    }
  }

  // ===== Event Handlers =====

  Future<void> _onInitializeAd(
      InitializeAd event, Emitter<AdState> emit) async {
    emit(AdLoading());
    // ไม่ต้องโหลดแคชแล้ว
    _setupTimers();
    add(FetchAdvertisements());
  }

  Future<void> _onFetchAdvertisements(
      FetchAdvertisements event, Emitter<AdState> emit) async {
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
        print('📺 Android TV - Advertisement list changed, updating...');
        _advertisements = newAds;
        _currentAdIndex = 0;
        _currentAd = null;

        // ไม่ต้อง preload แล้ว ให้เริ่มเล่นเลย
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

  Future<void> _onPlayNextAd(PlayNextAd event, Emitter<AdState> emit) async {
    if (_advertisements.isEmpty) {
      emit(AdNoContent());
      return;
    }

    _currentAd = _findNextPlayableAd();

    if (_currentAd == null) {
      emit(AdNoContent());
      return;
    }

    print(
        '📺 Android TV - Playing next ad: ${_currentAd!.title ?? _currentAd!.id} (type: ${_currentAd!.type})');

    _adTimer?.cancel();

    if (_currentAd!.type == 'video') {
      await _playVideoAd(_currentAd!, emit);
    } else {
      await _playImageAd(_currentAd!, emit);
    }
  }

  Future<void> _playVideoAd(Advertisement ad, Emitter<AdState> emit) async {
    final bool isLooping = _advertisements.length == 1;

    emit(AdPlaying(
      currentAd: ad,
      isVideoReady: true,
    ));

    // ถ้าไม่ได้สั่งให้เล่นวนซ้ำ ให้ใช้ Timer เหมือนเดิม (สำหรับวิดีโอที่อาจไม่มี duration)
    if (!isLooping) {
      final duration = ad.durationSeconds > 0 ? ad.durationSeconds : 30;
      _adTimer = Timer(Duration(seconds: duration), () {
        if (!isClosed) {
          add(VideoCompleted());
        }
      });
    }
  }

  Future<void> _playImageAd(Advertisement ad, Emitter<AdState> emit) async {
  emit(AdPlaying(
    currentAd: ad,
    isVideoReady: true,
  ));
  
  final duration = ad.durationSeconds > 0 ? ad.durationSeconds : 10;
  _adTimer = Timer(Duration(seconds: duration), () {
    if (!isClosed) {
      add(VideoCompleted());
    }
  });
}

  Future<void> _onVideoInitialized(
      VideoInitialized event, Emitter<AdState> emit) async {
    if (state is AdPlaying && _currentAd?.id == event.ad.id) {
      final currentState = state as AdPlaying;

      emit(AdPlaying(
        currentAd: currentState.currentAd,
        isVideoReady: true,
      ));
    }
  }

  Future<void> _onVideoCompleted(VideoCompleted event, Emitter<AdState> emit) async {
  // ถ้ามีโฆษณามากกว่า 1 ตัว ถึงจะให้เล่นตัวถัดไป
  if (_advertisements.length > 1) {
    print('📺 Android TV - Video completed, moving to next');
    _moveToNextAd();
    add(PlayNextAd());
  } else if (_advertisements.first.type == 'image') {
    // กรณีมีรูปเดียว ให้วนรูป
    print('📺 Android TV - Image completed, replaying single image');
    add(PlayNextAd());
  }
  // ถ้ามีวิดีโอเดียว จะไม่ทำอะไรเลย เพราะ Native จะ Loop ให้เอง
}

  // ===== Helper Methods =====

  void _setupTimers() {
    _scheduleFetchTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!isClosed) {
        add(FetchAdvertisements());
      }
    });
  }

  Advertisement? _findNextPlayableAd() {
    if (_advertisements.isEmpty) return null;

    for (int i = 0; i < _advertisements.length; i++) {
      final index = (_currentAdIndex + i) % _advertisements.length;
      final ad = _advertisements[index];

      if (_isAdPlayable(ad)) {
        _currentAdIndex = index;
        return ad;
      }
    }

    return null;
  }

  bool _isAdPlayable(Advertisement ad) => true;

  String _cleanVideoUrl(String url) {
    if (url.contains('https://cloud.softacular.nethttps://')) {
      return url.replaceFirst(
          'https://cloud.softacular.nethttps://', 'https://');
    }
    if (url.contains('http://cloud.softacular.nethttps://')) {
      return url.replaceFirst(
          'http://cloud.softacular.nethttps://', 'https://');
    }
    return url;
  }

  void _moveToNextAd() {
    _currentAdIndex = (_currentAdIndex + 1) % _advertisements.length;
    _adTimer?.cancel();
  }

  bool _hasAdvertisementsChanged(
      List<Advertisement> oldAds, List<Advertisement> newAds) {
    if (oldAds.length != newAds.length) return true;

    final oldIds = oldAds.map((ad) => ad.id).toSet();
    final newIds = newAds.map((ad) => ad.id).toSet();

    return !oldIds.containsAll(newIds) || !newIds.containsAll(oldIds);
  }

  @override
  Future<void> close() async {
    _adTimer?.cancel();
    _scheduleFetchTimer?.cancel();

    return super.close();
  }

  // ===== Getters for UI =====
  List<Advertisement> get advertisements => _advertisements;
  Advertisement? get currentAd => _currentAd;

  int get totalVideoCount =>
      _advertisements.where((ad) => ad.type == 'video').length;
}

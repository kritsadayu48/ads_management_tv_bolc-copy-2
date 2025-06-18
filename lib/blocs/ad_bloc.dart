import 'dart:async';
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';
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

  // Core data
  List<Advertisement> _advertisements = [];
  Advertisement? _currentAd;
  int _currentAdIndex = 0;

  // Single video controller approach for Android TV
  VideoPlayerController? _videoController;
  
  // Cache management - Focus on file caching, not controller caching
  final Map<String, String> _cachedFiles = {};
  final Set<String> _downloadedVideos = {};
  
  // Download state
  bool _isDownloadingInProgress = false;
  int _totalVideosToDownload = 0;
  int _videosDownloaded = 0;

  // Timers
  Timer? _adTimer;
  Timer? _scheduleFetchTimer;

  AdBloc({
    required this.deviceId,
    required AdService adService,
    required DeviceService deviceService,
  }) : _adService = adService,
       _deviceService = deviceService,
       super(AdInitial()) {
    
    // Register event handlers
    on<InitializeAd>(_onInitializeAd);
    on<FetchAdvertisements>(_onFetchAdvertisements);
    on<PlayNextAd>(_onPlayNextAd);
    on<PreloadVideos>(_onPreloadVideos);
    on<VideoInitialized>(_onVideoInitialized);
    on<VideoCompleted>(_onVideoCompleted);
    on<SkipToNext>(_onSkipToNext);
    on<HandleError>(_onHandleError);
  }

  // ===== Event Handlers =====
  
  Future<void> _onInitializeAd(InitializeAd event, Emitter<AdState> emit) async {
    emit(AdLoading());
    
    try {
      // Load existing cache info
      await _loadCacheInfo();
      
      // Set up periodic timers
      _setupTimers();
      
      // Initial fetch
      add(FetchAdvertisements());
      
    } catch (e) {
      add(HandleError('Initialization failed: $e'));
    }
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
        print('📺 Android TV - Advertisement list changed, updating...');
        _advertisements = newAds;
        _currentAdIndex = 0;
        _currentAd = null;

        // Start downloading videos to cache
        add(PreloadVideos(_advertisements));
      } else {
        print('📺 Android TV - No changes in advertisement list');
        if (_currentAd == null) {
          add(PlayNextAd());
        }
      }
      
    } catch (e) {
      print('📺 Android TV - Error fetching advertisements: $e');
      
      if (e.toString().contains('device_revoked')) {
        print('📺 Android TV - Device has been revoked, clearing credentials');
        await _deviceService.clearCredentials();
        emit(AdError(message: 'Device revoked', isDeviceRevoked: true));
      } else {
        add(HandleError('Failed to fetch advertisements: $e'));
      }
    }
  }

  Future<void> _onPreloadVideos(PreloadVideos event, Emitter<AdState> emit) async {
    if (event.advertisements.isEmpty || _isDownloadingInProgress) return;

    _isDownloadingInProgress = true;
    
    final videoAds = event.advertisements.where((ad) => ad.type == 'video').toList();
    _totalVideosToDownload = videoAds.length;
    _videosDownloaded = _downloadedVideos.length;

    print('📺 Android TV - Starting background download for ${_totalVideosToDownload} videos (${_videosDownloaded} already cached)');

    // Start playing first ad immediately - don't wait for downloads
    add(PlayNextAd());

    // Download videos in background (only show progress if no ad is playing)
    _downloadVideosInBackground(videoAds, emit);
  }

  void _downloadVideosInBackground(List<Advertisement> videoAds, Emitter<AdState> emit) async {
    for (int i = 0; i < videoAds.length; i++) {
      final ad = videoAds[i];
      
      // Skip if already downloaded
      if (_downloadedVideos.contains(ad.id)) {
        print('📺 Android TV - Already cached: ${ad.id}');
        continue;
      }
      
      final progress = (_videosDownloaded + 1) / _totalVideosToDownload;
      
      try {
        print('📺 Android TV - Background downloading: ${ad.title ?? ad.id}');
        
        final cachedFile = await _downloadVideoToCache(_cleanVideoUrl(ad.content), ad.id);
        
        if (cachedFile != null) {
          _downloadedVideos.add(ad.id);
          _videosDownloaded++;
          
          print('📺 Android TV - Downloaded: ${ad.title ?? ad.id} (${_videosDownloaded}/${_totalVideosToDownload})');
        }
        
        // Small delay to prevent overwhelming Android TV
        await Future.delayed(const Duration(milliseconds: 1000));
        
      } catch (e) {
        print('📺 Android TV - Download failed for ${ad.id}: $e');
        // Continue with next video even if one fails
      }
    }

    _isDownloadingInProgress = false;
    print('📺 Android TV - Background download completed: ${_videosDownloaded}/${_totalVideosToDownload}');
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

    print('📺 Android TV - Playing next ad: ${_currentAd!.title ?? _currentAd!.id} (type: ${_currentAd!.type})');

    _adTimer?.cancel();

    if (_currentAd!.type == 'video') {
      await _playVideoAd(_currentAd!, emit);
    } else {
      await _playImageAd(_currentAd!, emit);
    }
  }

  Future<void> _playVideoAd(Advertisement ad, Emitter<AdState> emit) async {
    final isCached = _downloadedVideos.contains(ad.id);
    
    print('📺 Android TV - Video ${ad.id} cached: $isCached');
    
    if (isCached) {
      // Cached video - initialize immediately without loading state
      await _initializeVideoController(ad, fromCache: true, emit: emit);
    } else {
      // Network video - show loading state
      emit(AdPlaying(
        currentAd: ad,
        isVideoReady: false,
      ));
      
      await _initializeVideoController(ad, fromCache: false, emit: emit);
    }
  }

  Future<void> _initializeVideoController(Advertisement ad, {required bool fromCache, Emitter<AdState>? emit}) async {
    try {
      print('📺 Android TV - Initializing video controller for: ${ad.id} (cached: $fromCache)');
      
      // Clean up existing controller completely
      await _cleanupVideoController();
      
      // Wait longer for Android TV to free up resources
      await Future.delayed(const Duration(milliseconds: 500));

      String videoUrl = _cleanVideoUrl(ad.content);
      
      if (fromCache) {
        final cachedPath = _cachedFiles[ad.id];
        if (cachedPath != null && File(cachedPath).existsSync()) {
          _videoController = VideoPlayerController.file(
            File(cachedPath),
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: false,
              allowBackgroundPlayback: false,
            ),
          );
          print('📺 Android TV - Using cached file: $cachedPath');
        } else {
          throw Exception('Cached file not found for ${ad.id}');
        }
      } else {
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(videoUrl),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: false,
            allowBackgroundPlayback: false,
          ),
          httpHeaders: {
            'User-Agent': 'Android TV Player',
            'Accept': 'video/mp4,video/*;q=0.9',
          },
        );
        print('📺 Android TV - Using network URL: $videoUrl');
      }

      // Configure controller
      await _videoController!.setVolume(1.0);
      await _videoController!.setLooping(false);
      
      // Initialize with appropriate timeout
      final timeout = fromCache ? Duration(seconds: 8) : Duration(seconds: 30);
      
      print('📺 Android TV - Starting initialization...');
      final stopwatch = Stopwatch()..start();
      
      await _videoController!.initialize().timeout(
        timeout,
        onTimeout: () => throw TimeoutException('Android TV initialization timeout', timeout),
      );
      
      stopwatch.stop();
      print('📺 Android TV - Initialized in ${stopwatch.elapsedMilliseconds}ms');

      // Verify controller is valid
      if (!_videoController!.value.isInitialized) {
        throw Exception('Controller not properly initialized');
      }

      // Start playing
      await _videoController!.play();
      
      // Add completion listener
      _videoController!.addListener(_onVideoPositionChanged);
      
      // For cached videos, emit ready state immediately instead of using VideoInitialized event
      if (fromCache && emit != null) {
        emit(AdPlaying(
          currentAd: ad,
          isVideoReady: true,
          videoController: _videoController,
        ));
        
        // Set timer directly
        final duration = _videoController!.value.duration.inSeconds > 0
            ? _videoController!.value.duration.inSeconds
            : (ad.durationSeconds > 0 ? ad.durationSeconds : 30);
            
        _adTimer = Timer(Duration(seconds: duration), () {
          if (!isClosed) {
            add(VideoCompleted());
          }
        });
        
        print('📺 Android TV - Cached video ready immediately, no loading state shown');
      } else {
        // For network videos, use the normal VideoInitialized event
        add(VideoInitialized(ad));
      }
      
      // Start background download if not cached
      if (!fromCache) {
        _downloadVideoToCache(videoUrl, ad.id).then((file) {
          if (file != null) {
            _downloadedVideos.add(ad.id);
            print('📺 Android TV - Background download completed for: ${ad.id}');
          }
        }).catchError((e) {
          print('📺 Android TV - Background download failed: $e');
        });
      }
      
    } catch (e) {
      print('📺 Android TV - Video initialization failed: $e');
      
      // Clean up failed controller
      await _cleanupVideoController();
      
      add(HandleError('Video initialization failed: $e'));
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

  Future<void> _onVideoInitialized(VideoInitialized event, Emitter<AdState> emit) async {
    if (state is AdPlaying && _currentAd?.id == event.ad.id) {
      final currentState = state as AdPlaying;
      
      emit(AdPlaying(
        currentAd: currentState.currentAd,
        isVideoReady: true,
        videoController: _videoController,
      ));

      // Set timer
      if (_videoController != null) {
        final duration = _videoController!.value.duration.inSeconds > 0
            ? _videoController!.value.duration.inSeconds
            : (_currentAd?.durationSeconds ?? 30);
            
        _adTimer = Timer(Duration(seconds: duration), () {
          if (!isClosed) {
            add(VideoCompleted());
          }
        });
      }
    }
  }

  Future<void> _onVideoCompleted(VideoCompleted event, Emitter<AdState> emit) async {
    print('📺 Android TV - Video completed, moving to next');
    
    // Don't cleanup immediately - let it finish gracefully
    _moveToNextAd();
    
    // Add small delay before next video for Android TV
    await Future.delayed(const Duration(milliseconds: 300));
    
    add(PlayNextAd());
  }

  Future<void> _onSkipToNext(SkipToNext event, Emitter<AdState> emit) async {
    print('📺 Android TV - Skipping to next ad');
    
    await _cleanupVideoController();
    _moveToNextAd();
    add(PlayNextAd());
  }

  Future<void> _onHandleError(HandleError event, Emitter<AdState> emit) async {
    emit(AdError(message: event.error));
    
    // Clean up and try next after delay
    await _cleanupVideoController();
    
    Future.delayed(const Duration(seconds: 3), () {
      if (!isClosed) {
        _moveToNextAd();
        add(PlayNextAd());
      }
    });
  }

  // ===== Helper Methods =====

  Future<void> _loadCacheInfo() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${directory.path}/video_cache');
      
      if (await cacheDir.exists()) {
        final files = cacheDir.listSync();
        for (final file in files) {
          if (file is File && file.path.endsWith('.mp4')) {
            final fileName = file.path.split('/').last;
            // Try to find matching ad by checking hash
            for (final ad in _advertisements) {
              final expectedFileName = 'video_${ad.id.hashCode.abs()}.mp4';
              if (fileName == expectedFileName) {
                _cachedFiles[ad.id] = file.path;
                _downloadedVideos.add(ad.id);
                print('📺 Android TV - Found cached video: ${ad.id}');
                break;
              }
            }
          }
        }
      }
      print('📺 Android TV - Loaded ${_downloadedVideos.length} cached videos');
    } catch (e) {
      print('📺 Android TV - Error loading cache info: $e');
    }
  }

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
      return url.replaceFirst('https://cloud.softacular.nethttps://', 'https://');
    }
    if (url.contains('http://cloud.softacular.nethttps://')) {
      return url.replaceFirst('http://cloud.softacular.nethttps://', 'https://');
    }
    return url;
  }

  Future<File?> _downloadVideoToCache(String url, String adId) async {
    try {
      // Check if already exists
      final cachedPath = _cachedFiles[adId];
      if (cachedPath != null) {
        final file = File(cachedPath);
        if (file.existsSync()) {
          return file;
        }
      }

      final directory = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${directory.path}/video_cache');
      
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final fileName = 'video_${adId.hashCode.abs()}.mp4';
      final file = File('${cacheDir.path}/$fileName');

      if (await file.exists()) {
        _cachedFiles[adId] = file.path;
        return file;
      }

      print('📺 Android TV - Downloading: $url');

      // Use more conservative settings for Android TV
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      client.connectionTimeout = const Duration(seconds: 20);
      client.idleTimeout = const Duration(seconds: 30);

      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('User-Agent', 'Android TV Player');
        
        final response = await request.close().timeout(
          const Duration(seconds: 90), // Longer timeout for Android TV
        );

        if (response.statusCode == 200) {
          final bytes = await consolidateHttpClientResponseBytes(response);
          await file.writeAsBytes(bytes);
          
          _cachedFiles[adId] = file.path;
          
          final fileSize = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
          print('📺 Android TV - Download completed: ${fileSize}MB');
          
          return file;
        } else {
          print('📺 Android TV - Download failed: HTTP ${response.statusCode}');
        }
      } finally {
        client.close();
      }
      
    } catch (e) {
      print('📺 Android TV - Download error: $e');
    }
    
    return null;
  }

  void _moveToNextAd() {
    _currentAdIndex = (_currentAdIndex + 1) % _advertisements.length;
    _adTimer?.cancel();
  }

  Future<void> _cleanupVideoController() async {
    if (_videoController != null) {
      print('📺 Android TV - Cleaning up video controller...');
      
      try {
        // Remove listener first
        _videoController!.removeListener(_onVideoPositionChanged);
        
        // Pause if playing
        if (_videoController!.value.isInitialized && _videoController!.value.isPlaying) {
          await _videoController!.pause();
        }
        
        // Wait a moment for Android TV
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Dispose
        await _videoController!.dispose();
        
        print('📺 Android TV - Video controller disposed');
        
      } catch (e) {
        print('📺 Android TV - Error during cleanup: $e');
      }
      
      _videoController = null;
    }
  }

  void _onVideoPositionChanged() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return;
    }

    try {
      final position = _videoController!.value.position;
      final duration = _videoController!.value.duration;

      if (duration.inSeconds > 0 && position.inSeconds >= duration.inSeconds - 1) {
        print('📺 Android TV - Video finished playing');
        
        _videoController?.removeListener(_onVideoPositionChanged);
        _adTimer?.cancel();

        if (!isClosed) {
          add(VideoCompleted());
        }
      }
    } catch (e) {
      print('📺 Android TV - Error in video position changed: $e');
    }
  }

  bool _hasAdvertisementsChanged(List<Advertisement> oldAds, List<Advertisement> newAds) {
    if (oldAds.length != newAds.length) return true;
    
    final oldIds = oldAds.map((ad) => ad.id).toSet();
    final newIds = newAds.map((ad) => ad.id).toSet();
    
    return !oldIds.containsAll(newIds) || !newIds.containsAll(oldIds);
  }

  @override
  Future<void> close() async {
    _adTimer?.cancel();
    _scheduleFetchTimer?.cancel();
    
    await _cleanupVideoController();
    
    return super.close();
  }

  // ===== Getters for UI =====
  VideoPlayerController? get videoController => _videoController;
  List<Advertisement> get advertisements => _advertisements;
  Advertisement? get currentAd => _currentAd;
  int get downloadedVideoCount => _downloadedVideos.length;
  int get totalVideoCount => _advertisements.where((ad) => ad.type == 'video').length;
  bool isVideoDownloaded(String adId) => _downloadedVideos.contains(adId);
  Map<String, String> get cachedFiles => Map.from(_cachedFiles);
}
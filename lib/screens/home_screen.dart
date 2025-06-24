// home_screen_bloc.dart - Optimized for Android TV Performance
import 'dart:async';
import 'dart:ui' as ui;
import 'package:ads_management_tv/blocs/ad_bloc.dart';
import 'package:ads_management_tv/events/ad_events.dart';
import 'package:ads_management_tv/models/advertisement.dart';
import 'package:ads_management_tv/screens/qr_generator_screen.dart';
import 'package:ads_management_tv/services/device_service.dart';
import 'package:ads_management_tv/states/ad_states.dart';
import 'package:ads_management_tv/widgets/video_player_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AdPlayerScreen extends StatefulWidget {
  final String deviceId;

  const AdPlayerScreen({Key? key, required this.deviceId}) : super(key: key);

  @override
  State<AdPlayerScreen> createState() => _AdPlayerScreenState();
}

class _AdPlayerScreenState extends State<AdPlayerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;

  // Content management for smooth transitions
  Widget? _currentContentWidget;
  Widget? _nextContentWidget;
  String? _currentAdId;

  bool _isBuilding = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();

    print(
        '📺 TV - AdPlayerScreen: Initializing BLoC-based version for device ID: ${widget.deviceId}');

    // Set immersive mode for TV
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Optimized animation controller
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200), // Fast transitions for TV
    );

    // Initialize BLoC
    context.read<AdBloc>().add(InitializeAd(widget.deviceId));
  }

  @override
  void dispose() {
    print('📺 TV - AdPlayerScreen: Disposing BLoC-based UI resources');

    _isDisposed = true;
    _fadeController.dispose();

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: [],
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    super.dispose();
    print('📺 TV - AdPlayerScreen: BLoC UI disposal completed');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: BlocConsumer<AdBloc, AdState>(
          listener: (context, state) {
            _handleStateChange(state);
          },
          builder: (context, state) {
            return _buildStateContent(context, state);
          },
        ),
      ),
    );
  }

  void _handleStateChange(AdState state) {
    if (_isDisposed || !mounted) return;

    if (state is AdPlaying) {
      _handleAdPlayingState(state);
    } else if (state is AdError && state.isDeviceRevoked) {
      print('📺 TV - Device revoked detected, navigating to QR screen');
      _handleDeviceRevoked(context);
    }
  }

  void _handleDeviceRevoked(BuildContext context) async {
    print(
        '📺 TV - AdPlayerScreen: Device has been revoked, navigating to QR screen');

    if (!mounted) return;

    try {
      final deviceService = DeviceService();
      await deviceService.clearCredentials();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const QrGeneratorScreen()),
        );
      }
    } catch (e) {
      print('📺 TV - Error during device revocation handling: $e');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const QrGeneratorScreen()),
        );
      }
    }
  }

  void _handleAdPlayingState(AdPlaying state) {
    final newAdId = state.currentAd.id;

    if (_currentAdId != newAdId && !_isBuilding) {
      _currentAdId = newAdId;
      _isBuilding = true;

      Widget newContent;
      if (state.currentAd.type == 'video') {
        newContent = VideoPlayerWidget(
          // *** ลบบรรทัด key: ValueKey(...) นี้ทิ้งไปครับ ***
          // key: ValueKey(state.currentAd.id),

          videoUrl: state.currentAd.content,
          orientation: state.currentAd.orientation,
          isLooping: context.read<AdBloc>().advertisements.length == 1,
          onCompleted: () {
            context.read<AdBloc>().add(VideoCompleted());
          },
          onError: (error) {
            context
                .read<AdBloc>()
                .add(HandleError("Video player error: $error"));
          },
        );
      } else {
        // ในส่วนของ Image การใส่ Key ไว้ยังคงเหมาะสม
        newContent = KeyedSubtree(
          key: ValueKey(state.currentAd.id),
          child: _buildImageContentOptimized(state.currentAd),
        );
      }

      _transitionToNewContent(newContent);
    }
  }

  Widget _buildStateContent(BuildContext context, AdState state) {
    // Show current content with minimal overlays
    return Stack(
      fit: StackFit.expand,
      children: [
        // Main content
        if (_currentContentWidget != null)
          FadeTransition(
            opacity: _fadeController,
            child: _currentContentWidget,
          )
        else
          _buildStateSpecificContent(state),

        // Only show preloading overlay at startup, not during playback
        if (state is AdPreloading && _currentContentWidget == null)
          _buildPreloadingOverlay(state),

        // Minimal debug info in corner (optional)
        //if (state is AdPlaying) _buildDebugInfo(state),
      ],
    );
  }

  Widget _buildStartupPreloadingView(AdPreloading state) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.indigo[900]!,
            Colors.black87,
            Colors.black,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App logo/icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.tv,
                size: 50,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 40),

            // Progress bar
            Container(
              width: 300,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: state.progress,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Progress percentage
            Text(
              '${(state.progress * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 30),

            // Status text
            const Text(
              'เตรียมความพร้อมระบบโฆษณา',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w300,
              ),
            ),

            const SizedBox(height: 10),

            // Current status
            Container(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Text(
                state.status,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 20),

            // Info text
            Text(
              'กำลังดาวน์โหลดและเตรียมวิดีโอให้พร้อมเล่น',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Minimal preloading overlay (shown during playback)
  Widget _buildPreloadingOverlay(AdPreloading state) {
    return Positioned(
      top: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                value: state.progress,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(state.progress * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Debug info overlay (optional, can be removed in production)
  // Widget _buildDebugInfo(AdPlaying state) {
  //   final adBloc = context.read<AdBloc>();
  //   final totalVideos = adBloc.totalVideoCount;

  //   return Positioned(
  //     bottom: 20,
  //     left: 20,
  //     child: Container(
  //       padding: const EdgeInsets.all(8),
  //       decoration: BoxDecoration(
  //         color: Colors.black.withOpacity(0.6),
  //         borderRadius: BorderRadius.circular(4),
  //       ),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         mainAxisSize: MainAxisSize.min,
  //         children: [
  //           Text(
  //             'AD: ${state.currentAd.title ?? state.currentAd.id}',
  //             style: const TextStyle(color: Colors.white, fontSize: 10),
  //           ),
  //           Text(
  //             'Type: ${state.currentAd.type}',
  //             style: const TextStyle(color: Colors.white, fontSize: 10),
  //           ),
  //           if (state.currentAd.type == 'video') ...[
  //             Text(
  //               'Ready: ${state.isVideoReady}',
  //               style: TextStyle(
  //                 color: state.isVideoReady ? Colors.green : Colors.orange,
  //                 fontSize: 10,
  //               ),
  //             ),
  //           ],
  //         ],
  //       ),
  //     ),
  //   );
  // }

  void _transitionToNewContent(Widget newContent) {
    _nextContentWidget = newContent;

    if (_currentContentWidget != null) {
      // Smooth transition
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && !_isDisposed) {
          _fadeController.reverse().then((_) {
            if (mounted && !_isDisposed) {
              setState(() {
                _currentContentWidget = _nextContentWidget;
                _nextContentWidget = null;
                _isBuilding = false;
              });
              _fadeController.forward();
            }
          });
        }
      });
    } else {
      // First content
      Future.microtask(() {
        if (mounted && !_isDisposed) {
          setState(() {
            _currentContentWidget = _nextContentWidget;
            _nextContentWidget = null;
            _fadeController.value = 1.0;
            _isBuilding = false;
          });
        }
      });
    }
  }

  Widget _buildStateSpecificContent(AdState state) {
    if (state is AdInitial || state is AdLoading) {
      return _buildInitialLoadingView();
    } else if (state is AdPreloading) {
      return _buildStartupPreloadingView(state);
    } else if (state is AdNoContent) {
      return _buildNoAdsView();
    } else if (state is AdError) {
      return _buildErrorView(state);
    }

    return Container(color: Colors.black);
  }

  Widget _buildImageContentOptimized(Advertisement ad) {
    print('📺 TV - UI: ⚡ Building optimized BLoC image content');

    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        child: CachedNetworkImage(
          imageUrl: ad.content,
          fit: BoxFit.cover,
          memCacheWidth: 1920,
          memCacheHeight: 1080,
          maxWidthDiskCache: 1920,
          maxHeightDiskCache: 1080,
          fadeInDuration: const Duration(milliseconds: 100),
          fadeOutDuration: const Duration(milliseconds: 50),
          placeholder: (context, url) => Container(color: Colors.black),
          errorWidget: (context, url, error) {
            // Signal error to BLoC
            context.read<AdBloc>().add(HandleError('Image load failed: $url'));
            return Container(
              color: Colors.black,
              child: const Center(
                child: Icon(Icons.error, color: Colors.red, size: 50),
              ),
            );
          },
          imageBuilder: (context, imageProvider) {
            return FutureBuilder<ui.Image>(
              future: _getImageInfo(imageProvider),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Image(image: imageProvider, fit: BoxFit.cover);
                }

                final image = snapshot.data!;
                final aspectRatio = image.width / image.height;

                // Portrait image with blur background
                if (aspectRatio < 1.0) {
                  return _buildPortraitImageLayout(imageProvider, aspectRatio);
                } else {
                  return Image(image: imageProvider, fit: BoxFit.cover);
                }
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildPortraitImageLayout(
      ImageProvider imageProvider, double aspectRatio) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background blur
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: imageProvider,
                fit: BoxFit.cover,
              ),
            ),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                color: Colors.black.withOpacity(0.3),
              ),
            ),
          ),
        ),

        // Centered image
        Center(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 1.0,
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image(image: imageProvider, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialLoadingView() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue[900]!,
            Colors.purple[900]!,
            Colors.black,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated logo
            TweenAnimationBuilder<double>(
              duration: const Duration(seconds: 2),
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: 0.8 + (0.2 * value),
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.tv,
                      size: 60,
                      color: Colors.white.withOpacity(value),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'กำลังเริ่มต้นระบบ...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Device ID: ${widget.deviceId}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoAdsView() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blueGrey[900]!,
            Colors.black,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.1),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ],
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.tv,
                    color: Colors.white,
                    size: 80,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'อุปกรณ์พร้อมใช้งาน',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'ไม่มีโฆษณาที่กำหนดสำหรับอุปกรณ์นี้',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Device ID: ${widget.deviceId}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                context.read<AdBloc>().add(FetchAdvertisements());
              },
              child: const Text('รีเฟรชเนื้อหา'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(AdError state) {
    if (state.isDeviceRevoked) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(
              'กำลังนำคุณไปยังหน้าลงทะเบียนอุปกรณ์...',
              style: TextStyle(fontSize: 18, color: Colors.white),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 80,
          ),
          const SizedBox(height: 20),
          Text(
            state.message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              context.read<AdBloc>().add(FetchAdvertisements());
            },
            child: const Text('ลองใหม่'),
          ),
        ],
      ),
    );
  }

  Future<ui.Image> _getImageInfo(ImageProvider imageProvider) async {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    final ImageStream stream =
        imageProvider.resolve(const ImageConfiguration());

    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        stream.removeListener(listener);
        completer.complete(info.image);
      },
      onError: (exception, stackTrace) {
        stream.removeListener(listener);
        completer.completeError(exception);
      },
    );

    stream.addListener(listener);
    return completer.future;
  }

  // void _handleDeviceRevoked() {
  //   Future.microtask(() {
  //     if (mounted) {
  //       Navigator.of(context).pushReplacement(
  //         MaterialPageRoute(builder: (context) => const QrGeneratorScreen()),
  //       );
  //     }
  //   });
  // }
}

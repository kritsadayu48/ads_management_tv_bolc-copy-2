import 'dart:async'; // เพิ่ม import

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class ExoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final Function()? onCompleted; // Callback เมื่อวิดีโอเล่นจบ
  final Function(Object error)? onError; // Callback เมื่อเกิดข้อผิดพลาด

  const ExoPlayerWidget({
    Key? key,
    required this.videoUrl,
    this.onCompleted,
    this.onError,
  }) : super(key: key);

  @override
  State<ExoPlayerWidget> createState() => _ExoPlayerWidgetState();
}

class _ExoPlayerWidgetState extends State<ExoPlayerWidget> {
  final String viewType = 'ExoPlayerView';
  MethodChannel? _methodChannel;

  // เพิ่มเติมสำหรับ EventChannel
  EventChannel? _eventChannel;
  StreamSubscription? _eventSubscription;

  @override
  void didUpdateWidget(ExoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ตรวจสอบว่า URL ของวิดีโอเปลี่ยนไปหรือไม่
    if (widget.videoUrl != oldWidget.videoUrl) {
      print('📺 TV - Dart: URL changed, re-initializing player.');
      // ถ้าเปลี่ยน ให้สั่ง initialize player ด้วย URL ใหม่
      _initializePlayer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> creationParams = <String, dynamic>{};

    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (PlatformViewCreationParams params) {
        return PlatformViewsService.initSurfaceAndroidView(
          id: params.id,
          viewType: viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () {
            params.onFocusChanged(true);
          },
        )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
          ..create();
      },
    );
  }

  void _onPlatformViewCreated(int id) {
    print('📺 TV - Dart: PlatformView created with ID: $id');
    _methodChannel = MethodChannel('com.softacular.signboard.tv/exoplayer_$id');

    // ตั้งค่า EventChannel
    _eventChannel =
        EventChannel('com.softacular.signboard.tv/exoplayer_events_$id');
    _eventSubscription = _eventChannel?.receiveBroadcastStream().listen(
      (dynamic event) {
        // จัดการ event ที่ได้รับจาก Native
        print('📺 TV - Dart: Received event: $event');
        if (event == "completed") {
          widget.onCompleted?.call();
        }
      },
      onError: (dynamic error) {
        // จัดการ error ที่ได้รับจาก Native
        print('📺 TV - Dart: Received error: $error');
        widget.onError?.call(error);
      },
    );

    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      await _methodChannel
          ?.invokeMethod('initialize', {'url': widget.videoUrl});
      print(
          '📺 TV - Dart: Sent initialize command for URL: ${widget.videoUrl}');
    } on PlatformException catch (e) {
      print('📺 TV - Dart: Failed to initialize player: ${e.message}');
      widget.onError?.call(e);
    }
  }

  @override
  void dispose() {
    // ยกเลิกการ subscribe และคืนทรัพยากร
    _eventSubscription?.cancel();
    _methodChannel?.invokeMethod('dispose');
    super.dispose();
  }
}

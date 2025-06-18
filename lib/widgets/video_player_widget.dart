import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String orientation;
  final bool isLooping;
  final Function()? onCompleted;
  final Function(Object error)? onError;

  const VideoPlayerWidget({
    Key? key,
    required this.videoUrl,
    this.orientation = 'horizontal',
    this.isLooping = false,
    this.onCompleted,
    this.onError,
  }) : super(key: key);

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  static const MethodChannel _channel = MethodChannel('com.softacular.signboard.tv/video_player');

  int? _textureId;
  StreamSubscription? _eventSubscription;
  
  // State สำหรับเก็บขนาดวิดีโอ
  double _videoWidth = 0;
  double _videoHeight = 0;

  @override
  void initState() {
    super.initState();
    _createPlayer();
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoUrl != oldWidget.videoUrl && _textureId != null) {
      // เมื่อ URL เปลี่ยน ให้รีเซ็ตขนาดและสั่ง initialize ใหม่
      setState(() {
        _videoWidth = 0;
        _videoHeight = 0;
      });
      _initializePlayer();
    }
  }

  Future<void> _createPlayer() async {
    try {
      final textureId = await _channel.invokeMethod<int>('create');
      if (textureId == null || !mounted) return;
      
      setState(() {
        _textureId = textureId;
      });

      _setupEventListeners();
      _initializePlayer();
    } catch (e) {
      widget.onError?.call(e);
    }
  }

  void _setupEventListeners() {
    if (_textureId == null) return;
    _eventSubscription?.cancel(); // ยกเลิกของเก่าก่อน
    _eventSubscription = EventChannel('com.softacular.signboard.tv/video_events_$_textureId')
        .receiveBroadcastStream()
        .listen((event) {
          if (event is Map) {
            final eventType = event['event'];
            if (eventType == 'sized') {
              // เมื่อได้รับขนาดวิดีโอจาก Native
              if (mounted) {
                setState(() {
                  _videoWidth = event['width'] ?? 0;
                  _videoHeight = event['height'] ?? 0;
                });
              }
            } else if (eventType == 'completed') {
              widget.onCompleted?.call();
            }
          }
    }, onError: (error) {
      widget.onError?.call(error);
    });
  }

  Future<void> _initializePlayer() async {
    if (_textureId == null) return;
    try {
      await _channel.invokeMethod('initialize', {
        'textureId': _textureId,
        'url': widget.videoUrl,
        'isLooping': widget.isLooping, // ส่งค่า isLooping ไปด้วย
      });
    } catch (e) {
      widget.onError?.call(e);
    }
  }
  @override
  Widget build(BuildContext context) {
    // ถ้ายังไม่ได้ textureId หรือยังไม่รู้ขนาดวิดีโอ ให้แสดงหน้าจอโหลดดิ้ง
    if (_textureId == null || _videoWidth == 0 || _videoHeight == 0) {
      return Container(
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: Colors.white24)),
      );
    }

    final aspectRatio = _videoWidth / _videoHeight;
    final isPortrait = aspectRatio < 1.1; // ครอบคลุมวิดีโอจัตุรัสด้วย

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          // Background (แสดงเฉพาะวิดีโอแนวตั้ง)
          if (isPortrait)
            Transform.scale(
              scale: 2.5,
              child: Texture(textureId: _textureId!),
            ),
          
          // Blur Effect Layer (แสดงเฉพาะวิดีโอแนวตั้ง)
          if (isPortrait)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
              child: Container(color: Colors.black.withOpacity(0.3)),
            ),

          // Foreground Video
          Center(
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Texture(textureId: _textureId!),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (_textureId != null) {
      _channel.invokeMethod('dispose', {'textureId': _textureId});
    }
    _eventSubscription?.cancel();
    super.dispose();
  }
}
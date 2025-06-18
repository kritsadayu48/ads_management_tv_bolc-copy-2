// file: services/native_video_player.dart

import 'package:flutter/services.dart';

class NativeVideoPlayer {
  // สร้าง channel ให้ตรงกับที่ใช้ใน MainActivity.kt
  static const MethodChannel _channel = MethodChannel('com.softacular.signboard.tv/video_player');

  // เมธอดสำหรับสร้าง Texture ในฝั่ง Native
  Future<int?> createTexture() async {
    try {
      final textureId = await _channel.invokeMethod<int>('createTexture');
      print('📺 TV - Dart: Texture created with ID: $textureId');
      return textureId;
    } on PlatformException catch (e) {
      print('📺 TV - Dart: Failed to create texture: ${e.message}');
      return null;
    }
  }

  // เมธอดสำหรับสั่งให้ Native เริ่มเตรียมวิดีโอ
  Future<void> initializeVideo({
    required String url,
    required String adId,
    required int textureId,
    bool isImage = false,
  }) async {
    try {
      await _channel.invokeMethod('initializeVideo', {
        'url': url,
        'adId': adId,
        'textureId': textureId, // ส่ง textureId ไปด้วย
        'isImage': isImage,
      });
    } on PlatformException catch (e) {
      print("📺 TV - Dart: Failed to initialize video: '${e.message}'.");
    }
  }
  
  // เมธอดสำหรับเล่นวิดีโอ
  Future<void> playVideo() async {
    try {
      await _channel.invokeMethod('playVideo');
    } on PlatformException catch (e) {
      print("📺 TV - Dart: Failed to play video: '${e.message}'.");
    }
  }

  // เมธอดสำหรับคืนทรัพยากร Texture
  Future<void> disposeTexture(int? textureId) async {
    if (textureId == null) return;
    try {
      await _channel.invokeMethod('disposeTexture', {'textureId': textureId});
      print('📺 TV - Dart: Texture disposed with ID: $textureId');
    } on PlatformException catch (e) {
      print("📺 TV - Dart: Failed to dispose texture: '${e.message}'.");
    }
  }
  
  // เมธอดสำหรับคืนทรัพยากรทั้งหมดของ Player
  Future<void> dispose() async {
     try {
      await _channel.invokeMethod('dispose');
    } on PlatformException catch (e) {
      print("📺 TV - Dart: Failed to dispose player: '${e.message}'.");
    }
  }
}
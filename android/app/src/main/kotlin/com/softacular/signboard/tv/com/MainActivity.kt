package com.softacular.signboard.tv.com

import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

@UnstableApi
class MainActivity: FlutterActivity() {
    private val VIDEO_PLAYER_CHANNEL = "com.softacular.signboard.tv/video_player"
    private var videoPlayerHandler: VideoPlayerHandler? = null

    @OptIn(UnstableApi::class)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // แก้ไขที่นี่: ส่ง dependencies ทั้ง 3 ตัวที่จำเป็นเข้าไปใน Handler
        videoPlayerHandler = VideoPlayerHandler(
            applicationContext, // ใช้ applicationContext เพื่อความปลอดภัย
            flutterEngine.renderer,
            flutterEngine.dartExecutor.binaryMessenger // ส่งตัวกลางสื่อสารเข้าไป
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIDEO_PLAYER_CHANNEL)
            .setMethodCallHandler(videoPlayerHandler)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        videoPlayerHandler?.disposeAll()
        videoPlayerHandler = null
    }
}
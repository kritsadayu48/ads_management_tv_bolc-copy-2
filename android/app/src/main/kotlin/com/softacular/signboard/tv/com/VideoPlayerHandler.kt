package com.softacular.signboard.tv.com

import android.content.Context
import android.net.Uri
import android.util.Log
import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File

@UnstableApi
class VideoPlayerHandler(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    private val messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    // แก้ไขที่ 1: สร้าง ExoPlayer แค่ตัวเดียว และเก็บไว้ใช้ตลอด
    private val exoPlayer: ExoPlayer
    private val textureEntries = mutableMapOf<Long, TextureRegistry.SurfaceTextureEntry>()
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    companion object {
        private var simpleCache: SimpleCache? = null
        private const val CACHE_SIZE_BYTES: Long = 100 * 1024 * 1024 // 100 MB
        private const val TAG = "VideoPlayerHandler"
    }

    init {
        if (simpleCache == null) {
            val cacheDir = File(context.cacheDir, "video_cache")
            val databaseProvider = StandaloneDatabaseProvider(context)
            simpleCache = SimpleCache(cacheDir, LeastRecentlyUsedCacheEvictor(CACHE_SIZE_BYTES), databaseProvider)
        }

        val cacheDataSourceFactory = CacheDataSource.Factory()
            .setCache(simpleCache!!)
            .setUpstreamDataSourceFactory(DefaultHttpDataSource.Factory())
        val mediaSourceFactory = DefaultMediaSourceFactory(cacheDataSourceFactory)

        exoPlayer = ExoPlayer.Builder(context)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()

        setupEventListener()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Number>("textureId")?.toLong()

        when (call.method) {
            "create" -> {
                // ไม่สร้าง Player ใหม่ แต่สร้างแค่ Texture
                val textureEntry = textureRegistry.createSurfaceTexture()
                val newTextureId = textureEntry.id()
                textureEntries[newTextureId] = textureEntry

                // สร้าง EventChannel สำหรับ Texture ID ใหม่นี้
                eventChannel = EventChannel(messenger, "com.softacular.signboard.tv/video_events_$newTextureId")
                setupEventChannelListener()

                Log.d(TAG, "Created new texture entry with textureId: $newTextureId")
                result.success(newTextureId)
            }
            "initialize" -> {
                val url = call.argument<String>("url")
                val isLooping = call.argument<Boolean>("isLooping") ?: false

                if (textureId != null && url != null) {
                    // ใช้ Player ตัวเดิมที่มีอยู่
                    exoPlayer.stop() // หยุดของเก่าก่อน
                    exoPlayer.setVideoSurface(Surface(textureEntries[textureId]?.surfaceTexture()))

                    val mediaItem = MediaItem.fromUri(Uri.parse(url))
                    exoPlayer.setMediaItem(mediaItem)
                    exoPlayer.repeatMode = if (isLooping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
                    exoPlayer.prepare()
                    exoPlayer.playWhenReady = true
                    Log.d(TAG, "Initializing textureId $textureId with URL: $url")
                    result.success(null)
                } else {
                    result.error("INIT_FAILED", "textureId or URL is null", null)
                }
            }
            "dispose" -> {
                if (textureId != null) {
                    textureEntries[textureId]?.release()
                    textureEntries.remove(textureId)
                    // ถ้าไม่มี texture ไหนใช้อยู่แล้ว ให้หยุด player
                    if (textureEntries.isEmpty()) {
                        exoPlayer.stop()
                    }
                    Log.d(TAG, "Disposed textureId: $textureId")
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun setupEventChannelListener() {
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun setupEventListener() {
        exoPlayer.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_ENDED) {
                    eventSink?.success(mapOf("event" to "completed"))
                }
            }
            override fun onPlayerError(error: PlaybackException) {
                eventSink?.error("PLAYER_ERROR", error.message, null)
            }
            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.width > 0 && videoSize.height > 0) {
                    val sizeMap = mapOf(
                        "event" to "sized",
                        "width" to videoSize.width.toDouble(),
                        "height" to videoSize.height.toDouble()
                    )
                    eventSink?.success(sizeMap)
                }
            }
        })
    }

    fun disposeAll() {
        textureEntries.values.forEach { it.release() }
        textureEntries.clear()
        exoPlayer.release()
        Log.d(TAG, "Disposed all players and textures.")
    }
}
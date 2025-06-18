package com.softacular.signboard.tv.com

import android.content.Context
import android.net.Uri
import android.util.Log
import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize // เพิ่ม import
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

    private val players = mutableMapOf<Long, PlayerData>()

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
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val textureId = call.argument<Number>("textureId")?.toLong()

        when (call.method) {
            "create" -> {
                val textureEntry = textureRegistry.createSurfaceTexture()
                val newTextureId = textureEntry.id()
                val eventChannel = EventChannel(messenger, "com.softacular.signboard.tv/video_events_$newTextureId")

                val player = createPlayer()
                player.setVideoSurface(Surface(textureEntry.surfaceTexture()))

                val playerData = PlayerData(player, textureEntry, eventChannel)
                players[newTextureId] = playerData

                setupEventListener(player, playerData)

                Log.d(TAG, "Created new player for textureId: $newTextureId")
                result.success(newTextureId)
            }
            "initialize" -> {
                val url = call.argument<String>("url")
                val isLooping = call.argument<Boolean>("isLooping") ?: false // อ่านค่า isLooping
                val playerData = players[textureId]

                if (playerData != null && url != null) {
                    val mediaItem = MediaItem.fromUri(Uri.parse(url))
                    playerData.player.setMediaItem(mediaItem)

                    // *** ตั้งค่าการเล่นวนซ้ำที่นี่ ***
                    playerData.player.repeatMode = if (isLooping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF

                    playerData.player.prepare()
                    playerData.player.playWhenReady = true
                    Log.d(TAG, "Initializing textureId $textureId with isLooping: $isLooping")
                    result.success(null)
                } else {
                    result.error("INIT_FAILED", "Player not found or URL is null", null)
                }
            }
            "dispose" -> {
                if (textureId != null) {
                    players[textureId]?.release()
                    players.remove(textureId)
                    Log.d(TAG, "Disposed player for textureId: $textureId")
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun createPlayer(): ExoPlayer {
        val cacheDataSourceFactory = CacheDataSource.Factory()
            .setCache(simpleCache!!)
            .setUpstreamDataSourceFactory(DefaultHttpDataSource.Factory())
        val mediaSourceFactory = DefaultMediaSourceFactory(cacheDataSourceFactory)

        return ExoPlayer.Builder(context)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()
    }

    private fun setupEventListener(player: ExoPlayer, playerData: PlayerData) {
        playerData.eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                playerData.eventSink = events
            }
            override fun onCancel(arguments: Any?) {
                playerData.eventSink = null
            }
        })

        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_ENDED) {
                    playerData.eventSink?.success(mapOf("event" to "completed"))
                }
            }
            override fun onPlayerError(error: PlaybackException) {
                playerData.eventSink?.error("PLAYER_ERROR", error.message, null)
            }

            // *** แก้ไขที่นี่: เพิ่มการส่งข้อมูลขนาดวิดีโอ ***
            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.width > 0 && videoSize.height > 0) {
                    val sizeMap = mapOf(
                        "event" to "sized",
                        "width" to videoSize.width.toDouble(),
                        "height" to videoSize.height.toDouble()
                    )
                    playerData.eventSink?.success(sizeMap)
                }
            }
        })
    }

    fun disposeAll() {
        for (playerData in players.values) {
            playerData.release()
        }
        players.clear()
    }

    private class PlayerData(
        val player: ExoPlayer,
        private val textureEntry: TextureRegistry.SurfaceTextureEntry,
        val eventChannel: EventChannel
    ) {
        var eventSink: EventChannel.EventSink? = null

        fun release() {
            eventChannel.setStreamHandler(null)
            player.release()
            textureEntry.release()
        }
    }
}
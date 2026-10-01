package com.example.youtube_app

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.graphics.Rect
import android.os.Build
import android.os.StatFs
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val playbackChannel = "infinitytube/platform_playback"
    private val storageChannel = "infinitytube/storage"
    private lateinit var platformPlaybackChannel: MethodChannel
    private var pipEnabled = true
    private var autoEnterPiP = true
    private var videoPlaying = false
    private var videoWidth = 16
    private var videoHeight = 9

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        platformPlaybackChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, playbackChannel)
        platformPlaybackChannel
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPiP" -> {
                        videoWidth = call.argument<Int>("width") ?: videoWidth
                        videoHeight = call.argument<Int>("height") ?: videoHeight
                        result.success(enterNativePictureInPicture())
                    }
                    "updatePiPState" -> {
                        pipEnabled = call.argument<Boolean>("enabled") ?: true
                        autoEnterPiP = call.argument<Boolean>("autoEnter") ?: true
                        videoPlaying = call.argument<Boolean>("playing") ?: false
                        videoWidth = call.argument<Int>("width") ?: videoWidth
                        videoHeight = call.argument<Int>("height") ?: videoHeight
                        updatePictureInPictureConfiguration()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, storageChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStorageInfo" -> {
                        val stats = StatFs(filesDir.absolutePath)
                        result.success(
                            mapOf(
                                "totalBytes" to stats.totalBytes,
                                "freeBytes" to stats.availableBytes,
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun enterNativePictureInPicture(): Boolean {
        if (!pipEnabled || Build.VERSION.SDK_INT < Build.VERSION_CODES.O || isInPictureInPictureMode) {
            return Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode
        }

        return try {
            enterPictureInPictureMode(buildPictureInPictureParams())
        } catch (_: IllegalStateException) {
            false
        }
    }

    private fun safeAspectRatio(): Rational {
        val width = videoWidth.coerceAtLeast(1)
        val height = videoHeight.coerceAtLeast(1)
        val ratio = width.toDouble() / height.toDouble()
        return when {
            ratio > 2.39 -> Rational(239, 100)
            ratio < 0.418 -> Rational(100, 239)
            else -> Rational(width, height)
        }
    }

    private fun buildPictureInPictureParams(): PictureInPictureParams {
        val sourceRect = Rect()
        window.decorView.getGlobalVisibleRect(sourceRect)
        return PictureInPictureParams.Builder()
            .setAspectRatio(safeAspectRatio())
            .setSourceRectHint(sourceRect)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setAutoEnterEnabled(pipEnabled && autoEnterPiP && videoPlaying)
                    setSeamlessResizeEnabled(true)
                }
            }
            .build()
    }

    private fun updatePictureInPictureConfiguration() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            setPictureInPictureParams(buildPictureInPictureParams())
        } catch (_: IllegalStateException) {
            // Activity may not be attached yet during startup.
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (
            Build.VERSION.SDK_INT in Build.VERSION_CODES.O until Build.VERSION_CODES.S &&
            pipEnabled &&
            autoEnterPiP &&
            videoPlaying &&
            !isInPictureInPictureMode
        ) {
            enterNativePictureInPicture()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (::platformPlaybackChannel.isInitialized) {
            platformPlaybackChannel.invokeMethod(
                "pipStateChanged",
                isInPictureInPictureMode,
            )
        }
    }
}

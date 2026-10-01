package com.example.youtube_app

import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val playbackChannel = "infinitytube/platform_playback"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, playbackChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPiP" -> result.success(enterNativePictureInPicture())
                    else -> result.notImplemented()
                }
            }
    }

    private fun enterNativePictureInPicture(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || isInPictureInPictureMode) {
            return Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode
        }

        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
        } catch (_: IllegalStateException) {
            false
        }
    }
}

package de.khonager.trans

import android.media.AudioAttributes
import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var wakeAlarmPreviewPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "de.khonager.trans/wake_alarm_preview"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("missing_path", "Missing preview sound path.", null)
                        return@setMethodCallHandler
                    }

                    try {
                        playWakeAlarmPreview(path)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("play_failed", error.message, null)
                    }
                }
                "stop" -> {
                    stopWakeAlarmPreview()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun playWakeAlarmPreview(path: String) {
        stopWakeAlarmPreview()

        wakeAlarmPreviewPlayer = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            setDataSource(path)
            setOnCompletionListener {
                stopWakeAlarmPreview()
            }
            prepare()
            start()
        }
    }

    private fun stopWakeAlarmPreview() {
        wakeAlarmPreviewPlayer?.setOnCompletionListener(null)
        wakeAlarmPreviewPlayer?.release()
        wakeAlarmPreviewPlayer = null
    }
}

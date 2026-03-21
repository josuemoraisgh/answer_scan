package com.example.answer_scan

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.example.answer_scan/omr"
    }

    // Lazy: OmrScanner created on first method call (after OpenCV init)
    private val omrScanner by lazy { OmrScanner() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialise OpenCV native library bundled in the AAR
        if (!OpenCVLoader.initLocal()) {
            android.util.Log.e("MainActivity", "OpenCV initialisation failed")
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanSheet" -> {
                        val imagePath = call.argument<String>("imagePath")
                        val debug     = call.argument<Boolean>("debug") ?: false

                        if (imagePath == null) {
                            result.error("INVALID_ARG", "imagePath is required", null)
                            return@setMethodCallHandler
                        }

                        // Run on a background thread — OpenCV is CPU-heavy
                        Thread {
                            val scan = omrScanner.scan(imagePath, debug)
                            activity.runOnUiThread {
                                if (scan.error != null) {
                                    result.error("SCAN_FAILED", scan.error, null)
                                } else {
                                    result.success(
                                        mapOf(
                                            "answers"        to scan.answers,
                                            "scores"         to scan.scores,
                                            "innerCorners"   to scan.innerCorners,
                                            "debugImagePath" to scan.debugImagePath,
                                        )
                                    )
                                }
                            }
                        }.start()
                    }

                    else -> result.notImplemented()
                }
            }
    }
}

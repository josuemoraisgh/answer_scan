package com.example.answer_scan

import android.util.Log
import com.example.answer_scan.omr.TemplateScanner
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.example.answer_scan/omr"
    }

    private val templateScanner by lazy { TemplateScanner() }
    private val scanExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var isOpenCvReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        isOpenCvReady = OpenCVLoader.initLocal()
        Log.i(TAG, "OpenCV initialisation: ${if (isOpenCvReady) "OK" else "FAILED"}")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanSheet" -> {
                        if (!isOpenCvReady) {
                            result.error(
                                "OPENCV_INIT_FAILED",
                                "OpenCV nao foi inicializado no Android.",
                                null,
                            )
                            return@setMethodCallHandler
                        }

                        val imagePath = call.argument<String>("imagePath")
                        val debug = call.argument<Boolean>("debug") ?: false
                        if (imagePath.isNullOrBlank()) {
                            result.error(
                                "INVALID_ARG",
                                "imagePath is required and must be non-empty",
                                null,
                            )
                            return@setMethodCallHandler
                        }

                        scanExecutor.execute {
                            val scanResult = templateScanner.scan(imagePath, debug)
                            runOnUiThread {
                                val success = scanResult["success"] as? Boolean ?: false
                                if (success) {
                                    result.success(scanResult)
                                } else {
                                    val error = scanResult["error"] as? String ?: "Scan failed"
                                    result.error("SCAN_FAILED", error, scanResult)
                                }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        scanExecutor.shutdownNow()
        super.onDestroy()
    }
}

package com.example.answer_scan.omr

import android.util.Log
import org.opencv.core.Core
import org.opencv.core.Mat
import org.opencv.core.Point
import org.opencv.core.Scalar
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc

class OmrDebugHelper {

    companion object {
        private const val TAG = "OmrDebugHelper"

        private val GREEN = Scalar(0.0, 220.0, 0.0)
        private val RED = Scalar(0.0, 0.0, 220.0)
        private val YELLOW = Scalar(0.0, 220.0, 220.0)
        private val BLUE = Scalar(220.0, 0.0, 0.0)
        private val MAGENTA = Scalar(200.0, 0.0, 200.0)
        private val GRAY = Scalar(120.0, 120.0, 120.0)
        private val WHITE = Scalar(255.0, 255.0, 255.0)
        private val BLACK = Scalar(0.0, 0.0, 0.0)
    }

    fun generate(
        oriented: Mat,
        templateCorners: List<Point>,
        warped: Mat,
        warpBinary: Mat,
        scores: Array<DoubleArray>,
        questions: List<ScanResultMapper.QuestionResult>,
        gridMapper: GridMapper,
        originalPath: String,
    ): String? {
        return try {
            val warpWidth = TemplateConfig.WARP_W
            val scale = warpWidth.toDouble() / oriented.width()

            val panel1 = Mat()
            Imgproc.resize(
                oriented,
                panel1,
                Size(warpWidth.toDouble(), oriented.height() * scale),
            )
            templateCorners.forEachIndexed { index, point ->
                val scaled = Point(point.x * scale, point.y * scale)
                val color = when (index) {
                    0 -> GREEN
                    1 -> RED
                    2 -> YELLOW
                    else -> BLUE
                }
                Imgproc.circle(panel1, scaled, 14, color, -1)
                Imgproc.circle(panel1, scaled, 14, BLACK, 2)
            }
            Imgproc.putText(
                panel1,
                "Detected template corners",
                Point(16.0, 32.0),
                Imgproc.FONT_HERSHEY_SIMPLEX,
                0.8,
                WHITE,
                2,
            )

            val panel2 = Mat()
            Imgproc.cvtColor(warped, panel2, Imgproc.COLOR_GRAY2BGR)
            Imgproc.rectangle(
                panel2,
                Point(TemplateConfig.LABEL_W.toDouble(), TemplateConfig.HEADER_H.toDouble()),
                Point(TemplateConfig.WARP_W.toDouble(), TemplateConfig.WARP_H.toDouble()),
                BLUE,
                2,
            )

            for (col in 0 until TemplateConfig.N_COLS) {
                for (row in 0 until TemplateConfig.N_ROWS) {
                    val full = gridMapper.getFullCellRect(col, row)
                    val roi = gridMapper.getCellROI(col, row)
                    val core = gridMapper.getCellCoreROI(col, row)
                    Imgproc.rectangle(
                        panel2,
                        Point(full.x1.toDouble(), full.y1.toDouble()),
                        Point(full.x2.toDouble(), full.y2.toDouble()),
                        GRAY,
                        1,
                    )
                    Imgproc.rectangle(
                        panel2,
                        Point(roi.x1.toDouble(), roi.y1.toDouble()),
                        Point(roi.x2.toDouble(), roi.y2.toDouble()),
                        YELLOW,
                        1,
                    )
                    Imgproc.rectangle(
                        panel2,
                        Point(core.x1.toDouble(), core.y1.toDouble()),
                        Point(core.x2.toDouble(), core.y2.toDouble()),
                        MAGENTA,
                        1,
                    )
                }
            }
            Imgproc.putText(
                panel2,
                "Warped image with cell, ROI and core ROI",
                Point(16.0, 32.0),
                Imgproc.FONT_HERSHEY_SIMPLEX,
                0.8,
                WHITE,
                2,
            )

            val panel3 = Mat()
            Imgproc.cvtColor(warpBinary, panel3, Imgproc.COLOR_GRAY2BGR)
            for (col in 0 until TemplateConfig.N_COLS) {
                val question = questions[col]
                for (row in 0 until TemplateConfig.N_ROWS) {
                    val roi = gridMapper.getCellROI(col, row)
                    val color = when {
                        question.answer == listOf("A", "B", "C", "D", "E").getOrNull(row) -> GREEN
                        scores[col][row] >= TemplateConfig.FILL_THRESHOLD -> RED
                        else -> GRAY
                    }
                    Imgproc.rectangle(
                        panel3,
                        Point(roi.x1.toDouble(), roi.y1.toDouble()),
                        Point(roi.x2.toDouble(), roi.y2.toDouble()),
                        color,
                        2,
                    )
                    Imgproc.putText(
                        panel3,
                        "%.0f".format(scores[col][row] * 100),
                        Point(roi.x1.toDouble() + 3, roi.y1.toDouble() + roi.height * 0.65),
                        Imgproc.FONT_HERSHEY_PLAIN,
                        0.85,
                        color,
                        1,
                    )
                }
                val headerX = TemplateConfig.LABEL_W + col * TemplateConfig.CELL_W
                Imgproc.putText(
                    panel3,
                    question.answer,
                    Point(headerX.toDouble() + 5, TemplateConfig.HEADER_H * 0.75),
                    Imgproc.FONT_HERSHEY_SIMPLEX,
                    0.55,
                    WHITE,
                    2,
                )
            }
            Imgproc.putText(
                panel3,
                "Binarized image with scores and selected answers",
                Point(16.0, 32.0),
                Imgproc.FONT_HERSHEY_SIMPLEX,
                0.8,
                WHITE,
                2,
            )

            val combined = Mat()
            Core.vconcat(listOf(panel1, panel2, panel3), combined)

            val debugPath = originalPath.replace(Regex("\\.[^.]+$"), "_omr_debug.jpg")
            Imgcodecs.imwrite(debugPath, combined)

            panel1.release()
            panel2.release()
            panel3.release()
            combined.release()

            Log.d(TAG, "Debug image saved: $debugPath")
            debugPath
        } catch (error: Exception) {
            Log.e(TAG, "Debug image generation failed", error)
            null
        }
    }
}

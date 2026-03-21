package com.example.answer_scan.omr

import android.util.Log
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfDouble
import org.opencv.core.MatOfPoint
import org.opencv.core.Point
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import kotlin.math.max
import kotlin.math.pow

class TemplateScanner {

    companion object {
        private const val TAG = "TemplateScanner"
    }

    private val markerDetector = MarkerDetector()
    private val perspectiveCorrector = PerspectiveCorrector()
    private val gridMapper = GridMapper()
    private val answerReader = AnswerReader(gridMapper)
    private val resultMapper = ScanResultMapper()
    private val debugHelper = OmrDebugHelper()

    fun scan(imagePath: String, debug: Boolean = false): Map<String, Any?> {
        val src = Imgcodecs.imread(imagePath)
        if (src.empty()) {
            return resultMapper.buildError(
                message = "Nao foi possivel carregar a imagem selecionada.",
                sheetStatus = "image_load_failed",
            )
        }

        val oriented = ensureLandscape(src)
        val gray = Mat()
        val blurred = Mat()
        val markerBinary = Mat()
        val otsuBinary = Mat()
        val warped = Mat()
        val warpAdaptive = Mat()
        val warpOtsu = Mat()
        val warpBinary = Mat()

        try {
            Imgproc.cvtColor(oriented, gray, Imgproc.COLOR_BGR2GRAY)
            Imgproc.GaussianBlur(gray, blurred, Size(5.0, 5.0), 0.0)

            val sharpnessVariance = computeSharpnessVariance(gray)
            Log.d(TAG, "Sharpness variance=${"%.2f".format(sharpnessVariance)}")
            if (sharpnessVariance < TemplateConfig.MIN_SHARPNESS_VARIANCE) {
                return resultMapper.buildError(
                    message = "Imagem borrada demais. Reposicione a folha e mantenha o celular estavel.",
                    sheetStatus = "blurry",
                    extraDebug = mapOf("sharpnessVariance" to sharpnessVariance),
                )
            }

            Imgproc.adaptiveThreshold(
                blurred,
                markerBinary,
                255.0,
                Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
                Imgproc.THRESH_BINARY_INV,
                41,
                10.0,
            )
            Imgproc.threshold(
                blurred,
                otsuBinary,
                0.0,
                255.0,
                Imgproc.THRESH_BINARY_INV + Imgproc.THRESH_OTSU,
            )
            Core.bitwise_or(markerBinary, otsuBinary, markerBinary)

            val markers = markerDetector.detect(
                markerBinary,
                oriented.width(),
                oriented.height(),
            ) ?: return resultMapper.buildError(
                message = "Nao foi possivel localizar os 4 marcadores. Enquadre toda a folha e tente novamente.",
                sheetStatus = "markers_not_found",
                extraDebug = mapOf("sharpnessVariance" to sharpnessVariance),
            )

            val validation = validateTemplate(markers.templateCorners, oriented.width(), oriented.height())
            if (validation != null) {
                return resultMapper.buildError(
                    message = validation.message,
                    sheetStatus = validation.sheetStatus,
                    markersDetected = 4,
                    extraDebug = mapOf("sharpnessVariance" to sharpnessVariance),
                )
            }

            val warpedMat = perspectiveCorrector.warp(blurred, markers.templateCorners)
            warpedMat.copyTo(warped)
            warpedMat.release()

            Imgproc.adaptiveThreshold(
                warped,
                warpAdaptive,
                255.0,
                Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
                Imgproc.THRESH_BINARY_INV,
                31,
                8.0,
            )
            Imgproc.threshold(
                warped,
                warpOtsu,
                0.0,
                255.0,
                Imgproc.THRESH_BINARY_INV + Imgproc.THRESH_OTSU,
            )
            Core.bitwise_or(warpAdaptive, warpOtsu, warpBinary)

            val scores = answerReader.scoreAllCells(warpBinary)
            val questions = resultMapper.classifyAll(scores)

            val debugPath = if (debug) {
                debugHelper.generate(
                    oriented = oriented,
                    templateCorners = markers.templateCorners,
                    warped = warped,
                    warpBinary = warpBinary,
                    scores = scores,
                    questions = questions,
                    gridMapper = gridMapper,
                    originalPath = imagePath,
                )
            } else {
                null
            }

            val result = resultMapper.buildSuccess(
                questions = questions,
                markersDetected = 4,
                perspectiveCorrected = true,
                extraDebug = mapOf(
                    "sharpnessVariance" to sharpnessVariance,
                    "warpWidth" to warped.width(),
                    "warpHeight" to warped.height(),
                ),
            )

            return if (debugPath != null) {
                result + mapOf("debugImagePath" to debugPath)
            } else {
                result
            }
        } finally {
            releaseAll(
                src,
                oriented,
                gray,
                blurred,
                markerBinary,
                otsuBinary,
                warped,
                warpAdaptive,
                warpOtsu,
                warpBinary,
            )
        }
    }

    private fun ensureLandscape(src: Mat): Mat {
        val oriented = Mat()
        if (src.width() >= src.height()) {
            src.copyTo(oriented)
        } else {
            Core.rotate(src, oriented, Core.ROTATE_90_CLOCKWISE)
        }
        return oriented
    }

    private fun computeSharpnessVariance(gray: Mat): Double {
        val laplacian = Mat()
        val mean = MatOfDouble()
        val stdDev = MatOfDouble()

        Imgproc.Laplacian(gray, laplacian, CvType.CV_64F)
        Core.meanStdDev(laplacian, mean, stdDev)

        val variance = stdDev.toArray().firstOrNull()?.pow(2) ?: 0.0

        laplacian.release()
        mean.release()
        stdDev.release()

        return variance
    }

    private fun validateTemplate(
        corners: List<Point>,
        imgW: Int,
        imgH: Int,
    ): ValidationFailure? {
        val topWidth = distance(corners[0], corners[1])
        val bottomWidth = distance(corners[2], corners[3])
        val leftHeight = distance(corners[0], corners[2])
        val rightHeight = distance(corners[1], corners[3])

        val widthRatio = max(topWidth, bottomWidth) / max(1.0, minOf(topWidth, bottomWidth))
        val heightRatio = max(leftHeight, rightHeight) / max(1.0, minOf(leftHeight, rightHeight))
        if (widthRatio > TemplateConfig.MAX_OPPOSITE_SIDE_RATIO ||
            heightRatio > TemplateConfig.MAX_OPPOSITE_SIDE_RATIO
        ) {
            return ValidationFailure(
                message = "Perspectiva forte demais. Reenquadre a folha mais de frente.",
                sheetStatus = "perspective_invalid",
            )
        }

        val polygon = MatOfPoint(*corners.toTypedArray())
        val areaFraction = Imgproc.contourArea(polygon) / (imgW.toDouble() * imgH.toDouble())
        polygon.release()
        if (areaFraction < TemplateConfig.MIN_TEMPLATE_AREA_FRAC) {
            return ValidationFailure(
                message = "Folha pequena ou cortada no enquadramento. Aproxime mais a camera.",
                sheetStatus = "sheet_out_of_frame",
            )
        }

        return null
    }

    private fun distance(a: Point, b: Point): Double {
        val dx = a.x - b.x
        val dy = a.y - b.y
        return kotlin.math.sqrt(dx * dx + dy * dy)
    }

    private fun releaseAll(vararg mats: Mat) {
        mats.forEach { mat -> mat.release() }
    }

    private data class ValidationFailure(
        val message: String,
        val sheetStatus: String,
    )
}

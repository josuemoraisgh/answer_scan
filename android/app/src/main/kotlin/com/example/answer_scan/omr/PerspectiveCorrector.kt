package com.example.answer_scan.omr

import org.opencv.core.Core
import org.opencv.core.Mat
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Scalar
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc

class PerspectiveCorrector {

    /**
     * Warps [src] into [dst] using the perspective transform defined by the
     * four [srcCorners] (TL, TR, BL, BR) mapping to the corners of a
     * [TemplateConfig.WARP_W] × [TemplateConfig.WARP_H] output image.
     *
     * [dst] may be any Mat (including an empty one); it is resized internally.
     * The caller is responsible for releasing [dst].
     */
    fun warp(src: Mat, srcCorners: List<Point>, dst: Mat) {
        require(srcCorners.size == 4) { "srcCorners must have exactly 4 points (TL, TR, BL, BR)" }

        val warpW = TemplateConfig.WARP_W.toDouble()
        val warpH = TemplateConfig.WARP_H.toDouble()

        val srcMat = MatOfPoint2f(*srcCorners.toTypedArray())
        val dstMat = MatOfPoint2f(
            Point(0.0,        0.0),
            Point(warpW - 1, 0.0),
            Point(0.0,        warpH - 1),
            Point(warpW - 1, warpH - 1),
        )

        val H = Imgproc.getPerspectiveTransform(srcMat, dstMat)
        Imgproc.warpPerspective(
            src, dst, H,
            Size(warpW, warpH),
            Imgproc.INTER_LINEAR,
            Core.BORDER_CONSTANT,
            Scalar(255.0),
        )

        srcMat.release()
        dstMat.release()
        H.release()
    }
}

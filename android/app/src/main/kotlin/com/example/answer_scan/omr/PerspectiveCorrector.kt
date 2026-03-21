package com.example.answer_scan.omr

import org.opencv.core.Core
import org.opencv.core.Mat
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Scalar
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc

class PerspectiveCorrector {

    fun warp(gray: Mat, srcCorners: List<Point>): Mat {
        require(srcCorners.size == 4) { "srcCorners must have exactly 4 points" }

        val warpW = TemplateConfig.WARP_W.toDouble()
        val warpH = TemplateConfig.WARP_H.toDouble()

        val src = MatOfPoint2f(*srcCorners.toTypedArray())
        val dst = MatOfPoint2f(
            Point(0.0, 0.0),
            Point(warpW - 1.0, 0.0),
            Point(0.0, warpH - 1.0),
            Point(warpW - 1.0, warpH - 1.0),
        )

        val homography = Imgproc.getPerspectiveTransform(src, dst)
        val warped = Mat()
        Imgproc.warpPerspective(
            gray,
            warped,
            homography,
            Size(warpW, warpH),
            Imgproc.INTER_LINEAR,
            Core.BORDER_CONSTANT,
            Scalar(255.0),
        )

        src.release()
        dst.release()
        homography.release()

        return warped
    }
}

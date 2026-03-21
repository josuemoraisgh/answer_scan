package com.example.answer_scan

import android.util.Log
import org.opencv.core.*
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import kotlin.math.*

/**
 * Native OMR scanner using OpenCV.
 *
 * Fixed template:
 *   - 4 solid black square corner markers (one per corner)
 *   - 20 questions (columns 1-20)
 *   - 5 alternatives per question (rows A-E)
 *
 * Algorithm:
 *   1. Load image → grayscale → Otsu binarise (inverted)
 *   2. Detect corner markers via contour analysis
 *   3. Extract inner edges of each marker
 *   4. Average opposite edges → axis-aligned bounding rectangle
 *   5. Perspective-warp grid area into [WARP_W × WARP_H] canonical image
 *   6. Otsu threshold on warped image
 *   7. Score each of 20×5 cells by dark-pixel density in inner ROI
 *   8. Classify each question: A–E | BLANK | MULTIPLE | AMBIGUOUS
 */
class OmrScanner {

    // ── Constants ─────────────────────────────────────────────────────────────

    companion object {
        private const val TAG = "OmrScanner"

        const val N_COLS = 20           // questions
        const val N_ROWS = 5            // alternatives A-E

        // Warped output image size (pixels). Square cells → CELL=60 px
        const val CELL_PX   = 60
        const val WARP_W    = N_COLS * CELL_PX   // 1200
        const val WARP_H    = N_ROWS * CELL_PX   // 300

        // Fraction of each cell edge to exclude (border guard)
        const val CELL_INSET = 0.20

        // Classification thresholds
        const val BLANK_THRESHOLD = 0.05   // < 5 % dark → blank
        const val FILL_THRESHOLD  = 0.18   // > 18 % dark → marked
        const val GAP_RATIO       = 1.80   // best/second must exceed this for clarity

        val LABELS = arrayOf("A", "B", "C", "D", "E")
    }

    // ── Public API ────────────────────────────────────────────────────────────

    data class ScanResult(
        /** 20 strings: "A"–"E", "BLANK", "MULTIPLE", or "AMBIGUOUS" */
        val answers: List<String>,
        /** 20 × 5 raw density scores (0.0–1.0) */
        val scores: List<List<Double>>,
        /** Inner corner pixel coords [[x,y]×4] in original oriented image */
        val innerCorners: List<List<Double>>,
        /** Path to debug JPEG (null if debug=false) */
        val debugImagePath: String?,
        /** Non-null when the scan fails */
        val error: String?,
    )

    fun scan(imagePath: String, debug: Boolean = false): ScanResult {
        val src = Imgcodecs.imread(imagePath)
        if (src.empty()) {
            return error("Não foi possível carregar: $imagePath")
        }

        val oriented = ensureLandscape(src)

        // ── 1. Grayscale + Otsu binary (inverted: dark areas become white) ──
        val gray   = Mat()
        val binary = Mat()
        Imgproc.cvtColor(oriented, gray, Imgproc.COLOR_BGR2GRAY)
        Imgproc.GaussianBlur(gray, gray, Size(3.0, 3.0), 0.0)
        Imgproc.threshold(gray, binary, 0.0, 255.0,
            Imgproc.THRESH_BINARY_INV + Imgproc.THRESH_OTSU)

        // ── 2. Detect corner markers ────────────────────────────────────────
        val markers = findMarkers(binary, oriented.width(), oriented.height())
            ?: return error("Não foi possível localizar os 4 marcadores de canto. " +
                            "Enquadre o gabarito no guia e tente novamente.")

        // ── 3–4. Compute axis-aligned grid rectangle from inner marker edges ─
        //   top-left inner corner    = (right, bottom) of TL marker
        //   top-right inner corner   = (left,  bottom) of TR marker
        //   bottom-left inner corner = (right, top)    of BL marker
        //   bottom-right inner corner= (left,  top)    of BR marker
        //   Average opposite sides for a stable rectangle.
        val (tl, tr, bl, br) = markers
        val gridLeft   = (tl.innerRight  + bl.innerRight)  / 2.0
        val gridRight  = (tr.innerLeft   + br.innerLeft)   / 2.0
        val gridTop    = (tl.innerBottom + tr.innerBottom) / 2.0
        val gridBottom = (bl.innerTop    + br.innerTop)    / 2.0

        val srcCorners = listOf(
            Point(gridLeft,  gridTop),
            Point(gridRight, gridTop),
            Point(gridLeft,  gridBottom),
            Point(gridRight, gridBottom),
        )

        // ── 5. Perspective warp ──────────────────────────────────────────────
        val warped = warpGrid(gray, srcCorners)

        // ── 6. Otsu threshold on warped ──────────────────────────────────────
        val warpBin = Mat()
        Imgproc.threshold(warped, warpBin, 0.0, 255.0,
            Imgproc.THRESH_BINARY_INV + Imgproc.THRESH_OTSU)

        // ── 7. Score cells ───────────────────────────────────────────────────
        val scores = scoreAllCells(warpBin)

        // ── 8. Classify ──────────────────────────────────────────────────────
        val answers = classifyAnswers(scores)

        // ── Optional debug image ─────────────────────────────────────────────
        val debugPath: String? = if (debug) {
            buildDebugImage(oriented, srcCorners, warped, warpBin, scores, answers, imagePath)
        } else null

        val cornersOut = srcCorners.map { p -> listOf(p.x, p.y) }
        val scoresOut  = scores.map { col -> col.toList() }

        // Release OpenCV Mats
        listOf(src, oriented, gray, binary, warped, warpBin).forEach { it.release() }

        return ScanResult(answers, scoresOut, cornersOut, debugPath, null)
    }

    // ── Marker detection ─────────────────────────────────────────────────────

    /**
     * Represents a detected corner marker with its inner-edge pixel coords.
     */
    private data class MarkerBox(
        val cx: Double, val cy: Double,     // centre (for corner assignment)
        val innerLeft: Double,
        val innerRight: Double,
        val innerTop: Double,
        val innerBottom: Double,
    )

    /**
     * Finds the 4 corner markers and returns them as [TL, TR, BL, BR].
     * Returns null if fewer than 4 solid-square candidates are found.
     */
    private fun findMarkers(binary: Mat, imgW: Int, imgH: Int): List<MarkerBox>? {
        val contours  = ArrayList<MatOfPoint>()
        val hierarchy = Mat()
        Imgproc.findContours(
            binary.clone(), contours, hierarchy,
            Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE,
        )

        val imgArea = imgW.toLong() * imgH
        val minArea = imgArea * 0.0006   // at least 0.06 % of frame
        val maxArea = imgArea * 0.025    // at most 2.5 %

        val candidates = mutableListOf<MarkerBox>()

        for (c in contours) {
            val area = Imgproc.contourArea(c)
            if (area < minArea || area > maxArea) continue

            val r = Imgproc.boundingRect(c)
            if (r.width == 0 || r.height == 0) continue

            // Squareness: width/height ratio
            val aspect = r.width.toDouble() / r.height
            if (aspect < 0.55 || aspect > 1.82) continue

            // Solidity: contour area vs bounding-rect area — markers are solid
            val solidity = area / (r.width.toDouble() * r.height)
            if (solidity < 0.55) continue

            val cx = r.x + r.width  / 2.0
            val cy = r.y + r.height / 2.0

            // Inner edges relative to image corners:
            //   TL marker → inner = (right, bottom)
            //   TR marker → inner = (left,  bottom)
            //   BL marker → inner = (right, top)
            //   BR marker → inner = (left,  top)
            // We record all four edges; the caller picks the right ones after
            // corner assignment.
            candidates.add(
                MarkerBox(
                    cx           = cx,
                    cy           = cy,
                    innerLeft    = r.x.toDouble(),
                    innerRight   = (r.x + r.width).toDouble(),
                    innerTop     = r.y.toDouble(),
                    innerBottom  = (r.y + r.height).toDouble(),
                )
            )
        }

        if (candidates.size < 4) {
            Log.w(TAG, "Marker candidates found: ${candidates.size} (need ≥ 4)")
            return null
        }

        // Assign to image corners: TL(0,0) TR(W,0) BL(0,H) BR(W,H)
        val imageCorners = listOf(
            Point(0.0,       0.0),
            Point(imgW.toDouble(), 0.0),
            Point(0.0,       imgH.toDouble()),
            Point(imgW.toDouble(), imgH.toDouble()),
        )

        val assigned  = Array<MarkerBox?>(4) { null }
        val usedFlags = BooleanArray(candidates.size)

        for (ci in 0..3) {
            val corner = imageCorners[ci]
            var bestDist = Double.MAX_VALUE
            var bestIdx  = -1
            for ((i, m) in candidates.withIndex()) {
                if (usedFlags[i]) continue
                val d = hypot(m.cx - corner.x, m.cy - corner.y)
                if (d < bestDist) { bestDist = d; bestIdx = i }
            }
            if (bestIdx < 0) return null
            assigned[ci] = candidates[bestIdx]
            usedFlags[bestIdx] = true
        }

        return assigned.map { it!! }   // [TL, TR, BL, BR]
    }

    // ── Homography ────────────────────────────────────────────────────────────

    private fun warpGrid(gray: Mat, srcCorners: List<Point>): Mat {
        // srcCorners: [TL, TR, BL, BR]
        val src = MatOfPoint2f(*srcCorners.toTypedArray())
        val dst = MatOfPoint2f(
            Point(0.0,            0.0),
            Point(WARP_W.toDouble(), 0.0),
            Point(0.0,            WARP_H.toDouble()),
            Point(WARP_W.toDouble(), WARP_H.toDouble()),
        )
        val H      = Imgproc.getPerspectiveTransform(src, dst)
        val warped = Mat()
        Imgproc.warpPerspective(gray, warped, H, Size(WARP_W.toDouble(), WARP_H.toDouble()))
        H.release()
        return warped
    }

    // ── Cell scoring ──────────────────────────────────────────────────────────

    /**
     * Returns [N_COLS][N_ROWS] dark-pixel density scores in [0, 1].
     */
    private fun scoreAllCells(warpBin: Mat): Array<DoubleArray> {
        val scores  = Array(N_COLS) { DoubleArray(N_ROWS) }
        val insetPx = (CELL_PX * CELL_INSET).toInt()

        for (col in 0 until N_COLS) {
            for (row in 0 until N_ROWS) {
                val x1 = col * CELL_PX + insetPx
                val y1 = row * CELL_PX + insetPx
                val x2 = (col + 1) * CELL_PX - insetPx
                val y2 = (row + 1) * CELL_PX - insetPx
                if (x2 <= x1 || y2 <= y1) continue

                val roi   = warpBin.submat(y1, y2, x1, x2)
                val dark  = Core.countNonZero(roi)
                val total = (x2 - x1) * (y2 - y1)
                scores[col][row] = dark.toDouble() / total
                roi.release()
            }
        }
        return scores
    }

    // ── Classification ────────────────────────────────────────────────────────

    /**
     * Classifies each of the 20 questions based on its 5 row scores.
     * Returns one of: "A", "B", "C", "D", "E", "BLANK", "MULTIPLE", "AMBIGUOUS"
     */
    private fun classifyAnswers(scores: Array<DoubleArray>): List<String> =
        (0 until N_COLS).map { col ->
            val s = scores[col]

            val maxScore = s.max()!!
            if (maxScore < BLANK_THRESHOLD) return@map "BLANK"

            val marked = (0 until N_ROWS).filter { s[it] >= FILL_THRESHOLD }
            when {
                marked.isEmpty() -> "BLANK"
                marked.size > 1  -> "MULTIPLE"
                else -> {
                    val bestIdx    = s.indices.maxByOrNull { s[it] }!!
                    val sortedDesc = s.sortedDescending()
                    val second     = sortedDesc.getOrElse(1) { 0.0 }
                    val ratio      = if (second < 0.01) Double.MAX_VALUE else maxScore / second
                    if (ratio < GAP_RATIO) "AMBIGUOUS" else LABELS[bestIdx]
                }
            }
        }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /** Rotate portrait images to landscape. */
    private fun ensureLandscape(src: Mat): Mat =
        if (src.width() < src.height()) {
            val r = Mat()
            Core.rotate(src, r, Core.ROTATE_90_CLOCKWISE)
            r
        } else src

    private fun error(msg: String) =
        ScanResult(emptyList(), emptyList(), emptyList(), null, msg)

    // ── Debug visualisation ───────────────────────────────────────────────────

    private fun buildDebugImage(
        oriented: Mat,
        srcCorners: List<Point>,
        warped: Mat,
        warpBin: Mat,
        scores: Array<DoubleArray>,
        answers: List<String>,
        originalPath: String,
    ): String {
        val vis = oriented.clone()

        // Draw grid corners on original image
        val colors = listOf(
            Scalar(0.0, 255.0, 0.0),   // TL green
            Scalar(0.0, 0.0, 255.0),   // TR red
            Scalar(255.0, 255.0, 0.0), // BL cyan
            Scalar(255.0, 0.0, 255.0), // BR magenta
        )
        srcCorners.forEachIndexed { i, pt ->
            Imgproc.circle(vis, pt, 16, colors[i], -1)
        }

        // Warped visualisation: grayscale → BGR
        val warpVis = Mat()
        Imgproc.cvtColor(warped, warpVis, Imgproc.COLOR_GRAY2BGR)

        val green = Scalar(0.0, 220.0, 0.0)
        val red   = Scalar(0.0, 0.0, 220.0)
        val gray  = Scalar(90.0, 90.0, 90.0)

        for (col in 0 until N_COLS) {
            for (row in 0 until N_ROWS) {
                val score    = scores[col][row]
                val isMarked = (LABELS[row] == answers[col])
                val x1 = col * CELL_PX; val y1 = row * CELL_PX
                val x2 = x1 + CELL_PX - 1; val y2 = y1 + CELL_PX - 1
                val colour = when {
                    isMarked           -> green
                    score > FILL_THRESHOLD -> red
                    else               -> gray
                }
                Imgproc.rectangle(warpVis,
                    Point(x1.toDouble(), y1.toDouble()),
                    Point(x2.toDouble(), y2.toDouble()), colour, 2)
                Imgproc.putText(warpVis,
                    "%.0f".format(score * 100),
                    Point((x1 + 3).toDouble(), (y1 + CELL_PX * 0.65).toDouble()),
                    Imgproc.FONT_HERSHEY_PLAIN, 0.9, colour, 1)
            }
        }

        // Answer labels above each column
        for (col in 0 until N_COLS) {
            Imgproc.putText(warpVis, answers[col].take(1),
                Point((col * CELL_PX + 10).toDouble(), 18.0),
                Imgproc.FONT_HERSHEY_SIMPLEX, 0.55, Scalar(0.0, 200.0, 200.0), 1)
        }

        // Stack: scaled original above warped visualisation
        val scale    = WARP_W.toDouble() / vis.width()
        val smallVis = Mat()
        Imgproc.resize(vis, smallVis,
            Size(WARP_W.toDouble(), vis.height() * scale))

        val combined = Mat()
        Core.vconcat(listOf(smallVis, warpVis), combined)

        val debugPath = originalPath.replace(Regex("\\.[^.]+$"), "_omr_debug.jpg")
        Imgcodecs.imwrite(debugPath, combined)

        listOf(vis, warpVis, smallVis, combined).forEach { it.release() }
        return debugPath
    }
}

package com.example.answer_scan.omr

import kotlin.math.roundToInt

object TemplateConfig {
    const val WARP_W = 2100
    const val WARP_H = 700

    const val HEADER_HEIGHT_FRAC = 0.18
    const val LABEL_WIDTH_FRAC = 0.07

    val HEADER_H: Int get() = (WARP_H * HEADER_HEIGHT_FRAC).roundToInt()
    val LABEL_W: Int get() = (WARP_W * LABEL_WIDTH_FRAC).roundToInt()

    const val N_COLS = 20
    const val N_ROWS = 5

    val ANSWER_W: Int get() = WARP_W - LABEL_W
    val ANSWER_H: Int get() = WARP_H - HEADER_H
    val CELL_W: Int get() = ANSWER_W / N_COLS
    val CELL_H: Int get() = ANSWER_H / N_ROWS

    const val CELL_READ_FRAC = 0.58
    const val CELL_CORE_FRAC = 0.32

    const val BLANK_THRESHOLD = 0.08
    const val FILL_THRESHOLD = 0.20
    const val MULTIPLE_THRESHOLD = 0.18
    const val DOMINANCE_DELTA = 0.07
    const val GAP_RATIO = 1.55

    const val MARKER_MIN_AREA_FRAC = 0.0003
    const val MARKER_MAX_AREA_FRAC = 0.040
    const val MARKER_MIN_SOLIDITY = 0.72
    const val MARKER_MIN_DENSITY = 0.55
    const val MARKER_MIN_ASPECT = 0.60
    const val MARKER_MAX_ASPECT = 1.40
    const val MARKER_CORNER_REGION_FRAC = 0.35

    const val MIN_SHARPNESS_VARIANCE = 15.0
    const val MIN_TEMPLATE_AREA_FRAC = 0.15
    const val MAX_OPPOSITE_SIDE_RATIO = 1.70
}

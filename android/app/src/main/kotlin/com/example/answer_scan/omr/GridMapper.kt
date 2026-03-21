package com.example.answer_scan.omr

class GridMapper {

    data class CellROI(
        val col: Int,
        val row: Int,
        val x1: Int,
        val y1: Int,
        val x2: Int,
        val y2: Int,
    ) {
        val width: Int get() = x2 - x1
        val height: Int get() = y2 - y1
        val isEmpty: Boolean get() = width <= 0 || height <= 0
    }

    private val answerX0 = TemplateConfig.LABEL_W
    private val answerY0 = TemplateConfig.HEADER_H
    private val cellW = TemplateConfig.CELL_W
    private val cellH = TemplateConfig.CELL_H

    private val readInsetX =
        ((cellW * (1.0 - TemplateConfig.CELL_READ_FRAC)) / 2.0).toInt()
    private val readInsetY =
        ((cellH * (1.0 - TemplateConfig.CELL_READ_FRAC)) / 2.0).toInt()
    private val coreInsetX =
        ((cellW * (1.0 - TemplateConfig.CELL_CORE_FRAC)) / 2.0).toInt()
    private val coreInsetY =
        ((cellH * (1.0 - TemplateConfig.CELL_CORE_FRAC)) / 2.0).toInt()

    fun getCellROI(col: Int, row: Int): CellROI {
        val cellX1 = answerX0 + col * cellW
        val cellY1 = answerY0 + row * cellH
        return CellROI(
            col = col,
            row = row,
            x1 = cellX1 + readInsetX,
            y1 = cellY1 + readInsetY,
            x2 = cellX1 + cellW - readInsetX,
            y2 = cellY1 + cellH - readInsetY,
        )
    }

    fun getCellCoreROI(col: Int, row: Int): CellROI {
        val cellX1 = answerX0 + col * cellW
        val cellY1 = answerY0 + row * cellH
        return CellROI(
            col = col,
            row = row,
            x1 = cellX1 + coreInsetX,
            y1 = cellY1 + coreInsetY,
            x2 = cellX1 + cellW - coreInsetX,
            y2 = cellY1 + cellH - coreInsetY,
        )
    }

    fun getFullCellRect(col: Int, row: Int): CellROI {
        val x1 = answerX0 + col * cellW
        val y1 = answerY0 + row * cellH
        return CellROI(col, row, x1, y1, x1 + cellW, y1 + cellH)
    }

    fun debugSummary(): String =
        "GridMapper(answerOrigin=($answerX0,$answerY0), cell=${cellW}x${cellH}, " +
            "readInset=($readInsetX,$readInsetY), coreInset=($coreInsetX,$coreInsetY))"
}

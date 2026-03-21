package com.example.answer_scan.omr

class ScanResultMapper {

    companion object {
        private val OPTION_LABELS = arrayOf("A", "B", "C", "D", "E")
    }

    data class QuestionResult(
        val answer: String,
        val confidence: Double,
        val scores: DoubleArray,
    )

    fun classifyAll(scores: Array<DoubleArray>): List<QuestionResult> =
        (0 until TemplateConfig.N_COLS).map { col -> classify(scores[col]) }

    fun buildSuccess(
        questions: List<QuestionResult>,
        markersDetected: Int,
        perspectiveCorrected: Boolean,
        extraDebug: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> {
        val answers = mutableMapOf<String, String>()
        val confidence = mutableMapOf<String, Double>()
        val scores = mutableMapOf<String, List<Double>>()

        questions.forEachIndexed { index, question ->
            val key = "${index + 1}"
            answers[key] = question.answer
            confidence[key] = question.confidence
            scores[key] = question.scores.toList()
        }

        return mapOf(
            "success" to true,
            "sheetStatus" to inferSheetStatus(questions),
            "answers" to answers,
            "confidence" to confidence,
            "scores" to scores,
            "debug" to (mutableMapOf<String, Any?>(
                "markersDetected" to markersDetected,
                "perspectiveCorrected" to perspectiveCorrected,
            ).apply {
                putAll(extraDebug)
            }),
        )
    }

    fun buildError(
        message: String,
        sheetStatus: String,
        markersDetected: Int = 0,
        perspectiveCorrected: Boolean = false,
        extraDebug: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> = mapOf(
        "success" to false,
        "sheetStatus" to sheetStatus,
        "error" to message,
        "debug" to (mutableMapOf<String, Any?>(
            "markersDetected" to markersDetected,
            "perspectiveCorrected" to perspectiveCorrected,
        ).apply {
            putAll(extraDebug)
        }),
    )

    private fun classify(rowScores: DoubleArray): QuestionResult {
        val ranked = rowScores.withIndex().sortedByDescending { it.value }
        val best = ranked[0]
        val second = ranked.getOrElse(1) { ranked[0] }
        val bestScore = best.value
        val secondScore = second.value
        val gap = bestScore - secondScore
        val ratio = if (secondScore <= 0.001) Double.MAX_VALUE else bestScore / secondScore

        if (bestScore < TemplateConfig.BLANK_THRESHOLD) {
            val confidence = 1.0 -
                (bestScore / TemplateConfig.BLANK_THRESHOLD).coerceIn(0.0, 1.0)
            return QuestionResult("blank", confidence, rowScores)
        }

        if (secondScore >= TemplateConfig.MULTIPLE_THRESHOLD) {
            val confidence = ((bestScore + secondScore) / 2.0).coerceIn(0.0, 1.0)
            return QuestionResult("multiple", confidence, rowScores)
        }

        if (bestScore < TemplateConfig.FILL_THRESHOLD ||
            gap < TemplateConfig.DOMINANCE_DELTA ||
            ratio < TemplateConfig.GAP_RATIO
        ) {
            val gapConfidence = (gap / TemplateConfig.DOMINANCE_DELTA).coerceIn(0.0, 1.0)
            val ratioConfidence = (ratio / TemplateConfig.GAP_RATIO).coerceIn(0.0, 1.0)
            val confidence = ((gapConfidence + ratioConfidence) / 2.0).coerceIn(0.0, 1.0)
            return QuestionResult("ambiguous", confidence, rowScores)
        }

        val absoluteConfidence = (
            (bestScore - TemplateConfig.FILL_THRESHOLD) /
                (1.0 - TemplateConfig.FILL_THRESHOLD)
            ).coerceIn(0.0, 1.0)
        val separationConfidence = (gap / bestScore.coerceAtLeast(0.001))
            .coerceIn(0.0, 1.0)
        val confidence = (
            absoluteConfidence * 0.45 +
                separationConfidence * 0.55
            ).coerceIn(0.0, 1.0)

        return QuestionResult(
            OPTION_LABELS[best.index],
            confidence,
            rowScores,
        )
    }

    private fun inferSheetStatus(questions: List<QuestionResult>): String =
        if (questions.any { question ->
                question.answer == "blank" ||
                    question.answer == "multiple" ||
                    question.answer == "ambiguous"
            }
        ) {
            "review_required"
        } else {
            "ok"
        }
}

package com.sscadcam.dharmacore

import android.app.Service
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.os.IBinder
import android.util.Log
import com.brother.ptouch.sdk.LabelInfo
import com.brother.ptouch.sdk.Printer
import com.brother.ptouch.sdk.PrinterInfo
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Runs Brother SDK printing in a **separate process** (`:brother_print`).
 * If the SDK JNI-aborts, only this process dies — the Flutter UI stays up.
 */
class BrotherPrintService : Service() {

    companion object {
        private const val TAG = "DharmaBrotherSvc"
        const val ACTION_PRINT = "com.sscadcam.dharmacore.action.BROTHER_PRINT"
        const val EXTRA_PNG_PATH = "png_path"
        const val EXTRA_MAC = "mac"
        const val EXTRA_MODEL = "model"
        const val EXTRA_JOB_ID = "job_id"
        /** Tape height in mm: 18 (bin labels) or 12 (~1/2" tool tags). */
        const val EXTRA_TAPE_MM = "tape_mm"

        private const val BLE_TIMEOUT_MS = 5_000L

        /**
         * Printable dots *across* the tape (print-head direction).
         *
         * P910: true ~360 dpi both axes → 18mm ≈ 256 dots.
         * P710/P715: 128-pin head; high-res is 180 dpi across × 360 dpi along
         * feed (Brother raster manual). 18mm printable = 112 dots, 12mm = 70.
         */
        private const val W18_P910_DOTS = 256
        private const val W12_P910_DOTS = 170
        private const val W18_P710_DOTS = 112
        private const val W12_P710_DOTS = 70

        /** Keep ink inside the printable band — PT heads clip the outer pins. */
        private const val MARGIN_ACROSS_P910 = 10
        private const val MARGIN_ACROSS_P710 = 2

        /** Leading / trailing pad along the tape (feed direction). */
        private const val LEAD_PAD_DOTS = 14
        private const val TRAIL_PAD_DOTS = 10

        fun jobsDir(context: Context): File =
            File(context.applicationContext.filesDir, "brother_jobs").apply { mkdirs() }

        fun resultFile(context: Context, jobId: String): File =
            File(jobsDir(context), "$jobId.result")

        fun writeResult(context: Context, jobId: String, code: String, message: String?) {
            val line = buildString {
                append(code)
                if (!message.isNullOrBlank()) {
                    append('\n')
                    append(message)
                }
            }
            resultFile(context, jobId).writeText(line)
        }
    }

    private val executor = Executors.newSingleThreadExecutor()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != ACTION_PRINT) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        val pngPath = intent.getStringExtra(EXTRA_PNG_PATH)
        val mac = intent.getStringExtra(EXTRA_MAC)
        val modelName = intent.getStringExtra(EXTRA_MODEL) ?: "PT_P910BT"
        val jobId = intent.getStringExtra(EXTRA_JOB_ID)
        val tapeMm = intent.getIntExtra(EXTRA_TAPE_MM, 18)
        if (pngPath.isNullOrBlank() || mac.isNullOrBlank() || jobId.isNullOrBlank()) {
            Log.e(TAG, "missing extras")
            stopSelf(startId)
            return START_NOT_STICKY
        }

        executor.execute {
            try {
                runPrint(pngPath, mac, modelName, jobId, tapeMm)
            } catch (t: Throwable) {
                Log.e(TAG, "print failed", t)
                writeResult(this, jobId, "PRINT_ERROR", t.message ?: t.javaClass.simpleName)
            } finally {
                stopSelf(startId)
            }
        }
        return START_NOT_STICKY
    }

    private fun runPrint(
        pngPath: String,
        mac: String,
        modelName: String,
        jobId: String,
        tapeMm: Int,
    ) {
        if (!File(pngPath).isFile) {
            writeResult(this, jobId, "FILE_MISSING", "Label image not found")
            return
        }
        val decoded = BitmapFactory.decodeFile(pngPath)
            ?: run {
                writeResult(this, jobId, "DECODE_ERROR", "Failed to decode label image")
                return
            }
        val argb = if (decoded.config == Bitmap.Config.ARGB_8888 && decoded.isMutable) {
            decoded
        } else {
            decoded.copy(Bitmap.Config.ARGB_8888, true)?.also {
                if (decoded !== it) decoded.recycle()
            } ?: run {
                writeResult(this, jobId, "DECODE_ERROR", "Failed to convert bitmap")
                return
            }
        }

        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
        if (adapter == null || !adapter.isEnabled) {
            writeResult(this, jobId, "BLUETOOTH_OFF", "Bluetooth is disabled")
            return
        }

        val model = when (modelName) {
            "PT_P710BT" -> PrinterInfo.Model.PT_P710BT
            "PT_P715eBT" -> PrinterInfo.Model.PT_P715eBT
            else -> PrinterInfo.Model.PT_P910BT
        }

        // Flutter PNGs are landscape (square 360dpi pixels for P910). Brother
        // wants tape-width × feed-length. P710 high-res is anisotropic (180×360).
        val srcW = argb.width
        val srcH = argb.height
        val rotated = rotateLandscapeForPtTape(argb).also {
            if (it !== argb) argb.recycle()
        }
        val useW12 = tapeMm in 11..13
        val isP710Family =
            model == PrinterInfo.Model.PT_P710BT || model == PrinterInfo.Model.PT_P715eBT
        val targetTapeDots = tapeImageAreaWidthDots(model, useW12, isP710Family)
        val bitmap = fitToPrintableArea(rotated, targetTapeDots, isP710Family).also {
            if (it !== rotated) rotated.recycle()
        }
        Log.i(
            TAG,
            "job=$jobId model=$modelName tape=${tapeMm}mm bitmap ${srcW}x${srcH} → ${bitmap.width}x${bitmap.height} (dots=$targetTapeDots p710=$isP710Family)",
        )

        val workDir = (getExternalFilesDir(null) ?: filesDir)
            .let { File(it, "brother_print") }
            .apply { mkdirs() }
        val printPng = File(workDir, "job_${jobId}_pt.png")
        try {
            FileOutputStream(printPng).use { out ->
                if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)) {
                    writeResult(this, jobId, "ENCODE_ERROR", "Failed to write print label")
                    return
                }
            }
        } catch (e: Exception) {
            writeResult(this, jobId, "ENCODE_ERROR", e.message ?: "Failed to write print label")
            return
        }

        // Prefer app-specific external dir (Brother docs / SO: unset workPath → JNI abort).
        val ports = listOf(PrinterInfo.Port.BLUETOOTH, PrinterInfo.Port.BLE)
        var lastError = "Print failed"

        for (port in ports) {
            Log.i(TAG, "job=$jobId try port=$port model=$model")
            val printer = Printer()
            printer.setBluetooth(adapter)
            try {
                printer.setBluetoothLowEnergy(this, adapter, BLE_TIMEOUT_MS)
            } catch (e: Exception) {
                Log.w(TAG, "setBluetoothLowEnergy: ${e.message}")
            }

            val info = printer.printerInfo
            info.printerModel = model
            info.port = port
            info.macAddress = mac
            info.workPath = workDir.absolutePath
            // P910: FIT_TO_PAPER — ORIGINAL JNI-aborts when dots ≠ expected W18.
            // P710: ORIGINAL — FIT_TO_PAPER + high-res often squashes to a short strip.
            info.printMode = if (isP710Family) {
                PrinterInfo.PrintMode.ORIGINAL
            } else {
                PrinterInfo.PrintMode.FIT_TO_PAPER
            }
            info.isAutoCut = true
            info.isCutAtEnd = true
            info.isHalfCut = false
            info.isSpecialTape = false
            val labelOrdinal = if (useW12) LabelInfo.PT.W12.ordinal else LabelInfo.PT.W18.ordinal
            info.labelNameIndex = labelOrdinal
            info.printQuality = PrinterInfo.PrintQuality.HIGH_RESOLUTION
            info.skipStatusCheck = true
            if (!printer.setPrinterInfo(info)) {
                lastError = "setPrinterInfo failed for $port"
                continue
            }
            try {
                val labelInfo = printer.labelInfo ?: LabelInfo()
                labelInfo.labelNameIndex = labelOrdinal
                labelInfo.isAutoCut = true
                labelInfo.isEndCut = true
                labelInfo.isHalfCut = false
                labelInfo.isSpecialTape = false
                printer.setLabelInfo(labelInfo)
            } catch (e: Exception) {
                Log.w(TAG, "setLabelInfo: ${e.message}")
            }

            if (!printer.startCommunication()) {
                lastError = "Could not connect via $port"
                continue
            }

            val status = try {
                val fileStatus = printer.printFile(printPng.absolutePath)
                if (fileStatus.errorCode == PrinterInfo.ErrorCode.ERROR_NONE) {
                    fileStatus
                } else {
                    Log.w(TAG, "printFile ${fileStatus.errorCode}, trying printImage")
                    printer.printImage(bitmap)
                }
            } finally {
                try {
                    printer.endCommunication()
                } catch (_: Exception) {
                }
            }

            if (status.errorCode == PrinterInfo.ErrorCode.ERROR_NONE) {
                writeResult(this, jobId, "OK", null)
                Log.i(TAG, "job=$jobId success via $port")
                return
            }
            lastError = "Print error via $port: ${status.errorCode}"
        }

        writeResult(this, jobId, "PRINT_FAILED", lastError)
    }

    /**
     * Brother PT print head spans the tape width: bitmap width must be tape
     * dots. Flutter labels are landscape — rotate 90° CW so left→leading edge.
     */
    private fun rotateLandscapeForPtTape(src: Bitmap): Bitmap {
        if (src.width <= src.height) return src
        val matrix = Matrix().apply { postRotate(90f) }
        return Bitmap.createBitmap(src, 0, 0, src.width, src.height, matrix, true)
    }

    /** Printable dots across 12mm/18mm tape for this model. */
    private fun tapeImageAreaWidthDots(
        model: PrinterInfo.Model,
        useW12: Boolean,
        isP710Family: Boolean,
    ): Int {
        val fallback = when {
            isP710Family && useW12 -> W12_P710_DOTS
            isP710Family -> W18_P710_DOTS
            useW12 -> W12_P910_DOTS
            else -> W18_P910_DOTS
        }
        try {
            val list = Printer.getLabelParamList(model) ?: return fallback
            val paperId = if (useW12) LabelInfo.PT.W12.id else LabelInfo.PT.W18.id
            val nameHint = if (useW12) "12" else "18"
            val match = list.firstOrNull { it.paperID == paperId }
                ?: list.firstOrNull { it.paperName?.contains(nameHint) == true }
            if (match != null) {
                val area = match.imageAreaWidth
                // Prefer SDK when it looks like a real cross-tape width for this family.
                if (area > 0) {
                    val maxSane = if (isP710Family) 140 else 300
                    val minSane = if (isP710Family) 48 else 100
                    if (area in minSane..maxSane) return area
                    Log.w(TAG, "ignoring odd imageAreaWidth=$area for p710=$isP710Family")
                }
                val pins = match.headPinNum - match.pinOffsetLeft - match.pinOffsetRight
                if (pins in minSaneFor(isP710Family)..maxSaneFor(isP710Family)) return pins
            }
        } catch (e: Exception) {
            Log.w(TAG, "getLabelParamList: ${e.message}")
        }
        return fallback
    }

    private fun minSaneFor(isP710Family: Boolean) = if (isP710Family) 48 else 100
    private fun maxSaneFor(isP710Family: Boolean) = if (isP710Family) 140 else 300

    /**
     * Fit content into the printable band.
     *
     * P910: uniform scale (360×360), with side margins.
     * P710 high-res: 180 dpi across × 360 dpi along feed — scale width to the
     * head only; **keep feed length** so labels don't collapse to ~1".
     */
    private fun fitToPrintableArea(
        src: Bitmap,
        printableWidth: Int,
        isP710Family: Boolean,
    ): Bitmap {
        val width = printableWidth.coerceAtLeast(48)
        val marginBase = if (isP710Family) MARGIN_ACROSS_P710 else MARGIN_ACROSS_P910
        val margin = marginBase.coerceAtMost((width / 2) - 1).coerceAtLeast(0)
        val innerW = (width - margin * 2).coerceAtLeast(1)

        val scaleX = innerW.toFloat() / src.width.toFloat()
        // P710: across-tape is ~half the dpi of our 360dpi Flutter canvas; along
        // tape stays 360dpi — do not apply scaleX to height (that made ~1" labels).
        val scaleY = if (isP710Family) 1.0f else scaleX
        val innerH = (src.height * scaleY).toInt().coerceAtLeast(1)

        val scaled = if (src.width == innerW && src.height == innerH) {
            src
        } else {
            Bitmap.createScaledBitmap(src, innerW, innerH, true)
        }
        val outH = innerH + LEAD_PAD_DOTS + TRAIL_PAD_DOTS
        val out = Bitmap.createBitmap(width, outH, Bitmap.Config.ARGB_8888)
        out.eraseColor(Color.WHITE)
        Canvas(out).drawBitmap(scaled, margin.toFloat(), LEAD_PAD_DOTS.toFloat(), null)
        if (scaled !== src) scaled.recycle()
        return out
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}

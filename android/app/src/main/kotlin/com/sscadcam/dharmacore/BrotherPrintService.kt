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

        private const val BLE_TIMEOUT_MS = 5_000L

        /** 18mm printable width @ Brother HIGH_RESOLUTION (~360 dpi). */
        private const val W18_HIGH_RES_DOTS = 256

        /** Keep ink inside the printable band — PT heads clip the outer pins. */
        private const val MARGIN_ACROSS_DOTS = 10

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
        if (pngPath.isNullOrBlank() || mac.isNullOrBlank() || jobId.isNullOrBlank()) {
            Log.e(TAG, "missing extras")
            stopSelf(startId)
            return START_NOT_STICKY
        }

        executor.execute {
            try {
                runPrint(pngPath, mac, modelName, jobId)
            } catch (t: Throwable) {
                Log.e(TAG, "print failed", t)
                writeResult(this, jobId, "PRINT_ERROR", t.message ?: t.javaClass.simpleName)
            } finally {
                stopSelf(startId)
            }
        }
        return START_NOT_STICKY
    }

    private fun runPrint(pngPath: String, mac: String, modelName: String, jobId: String) {
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

        // Flutter PNGs are landscape. Brother PT wants tape-width × feed-length
        // at HIGH_RESOLUTION (~360dpi). Rotate, then fit inside the printable
        // band with margins so P710/P910 don't clip top/left text.
        val srcW = argb.width
        val srcH = argb.height
        val rotated = rotateLandscapeForPtTape(argb).also {
            if (it !== argb) argb.recycle()
        }
        val targetTapeDots = w18ImageAreaWidthDots(model)
        val bitmap = fitToPrintableArea(rotated, targetTapeDots).also {
            if (it !== rotated) rotated.recycle()
        }
        Log.i(
            TAG,
            "job=$jobId model=$modelName bitmap ${srcW}x${srcH} → ${bitmap.width}x${bitmap.height} (W18 dots=$targetTapeDots)",
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
            // FIT_TO_PAPER: ORIGINAL JNI-aborts on P910BT when bitmap dots don't
            // exactly match the printer's expected W18 raster size.
            info.printMode = PrinterInfo.PrintMode.FIT_TO_PAPER
            info.isAutoCut = true
            info.isCutAtEnd = true
            info.isHalfCut = false
            info.isSpecialTape = false
            info.labelNameIndex = LabelInfo.PT.W18.ordinal
            info.printQuality = PrinterInfo.PrintQuality.HIGH_RESOLUTION
            info.skipStatusCheck = true
            if (!printer.setPrinterInfo(info)) {
                lastError = "setPrinterInfo failed for $port"
                continue
            }
            try {
                val labelInfo = printer.labelInfo ?: LabelInfo()
                labelInfo.labelNameIndex = LabelInfo.PT.W18.ordinal
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

    /** Printable dots across 18mm tape at HIGH_RESOLUTION (~360dpi). */
    private fun w18ImageAreaWidthDots(model: PrinterInfo.Model): Int {
        try {
            val list = Printer.getLabelParamList(model) ?: return W18_HIGH_RES_DOTS
            val w18Id = LabelInfo.PT.W18.id
            val match = list.firstOrNull { it.paperID == w18Id }
                ?: list.firstOrNull { it.paperName?.contains("18") == true }
            if (match != null) {
                val area = match.imageAreaWidth
                if (area > 0) return area
                val pins = match.headPinNum - match.pinOffsetLeft - match.pinOffsetRight
                if (pins > 0) return pins
            }
        } catch (e: Exception) {
            Log.w(TAG, "getLabelParamList: ${e.message}")
        }
        return W18_HIGH_RES_DOTS
    }

    /**
     * Scale content into the printable band and pad with white so ink isn't
     * clipped on the outer pins (top/bottom of the sticker) or at feed start
     * (left of the sticker). Critical for P710BT which clips harder than P910.
     */
    private fun fitToPrintableArea(src: Bitmap, printableWidth: Int): Bitmap {
        val width = printableWidth.coerceAtLeast(64)
        val margin = MARGIN_ACROSS_DOTS.coerceAtMost((width / 2) - 1).coerceAtLeast(0)
        val innerW = (width - margin * 2).coerceAtLeast(1)
        val scale = innerW.toFloat() / src.width.toFloat()
        val innerH = (src.height * scale).toInt().coerceAtLeast(1)
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

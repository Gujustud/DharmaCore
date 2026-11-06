package com.example.cribhub

import android.app.Service
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
        const val ACTION_PRINT = "com.example.cribhub.action.BROTHER_PRINT"
        const val EXTRA_PNG_PATH = "png_path"
        const val EXTRA_MAC = "mac"
        const val EXTRA_MODEL = "model"
        const val EXTRA_JOB_ID = "job_id"

        private const val BLE_TIMEOUT_MS = 5_000L

        /** 18mm printable width @ Brother HIGH_RESOLUTION (~360 dpi). */
        private const val W18_HIGH_RES_DOTS = 256

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

        // Flutter PNGs are landscape @ ~180dpi. Brother PT wants tape-width ×
        // feed-length, and HIGH_RESOLUTION is 360dpi (~2× dots across 18mm).
        // Without rotate+scale, text is sideways and/or only ~half tape height.
        val srcW = argb.width
        val srcH = argb.height
        val rotated = rotateLandscapeForPtTape(argb).also {
            if (it !== argb) argb.recycle()
        }
        val targetTapeDots = w18ImageAreaWidthDots(model)
        val bitmap = scaleToTapeWidth(rotated, targetTapeDots).also {
            if (it !== rotated) rotated.recycle()
        }
        Log.i(
            TAG,
            "job=$jobId bitmap ${srcW}x${srcH} → ${bitmap.width}x${bitmap.height} (W18 dots=$targetTapeDots)",
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
            // Bitmap is already tape-width × feed-length @ ~360dpi. FIT_TO_PAPER
            // uses the full W18 printable area (matches desktop driver fill).
            info.printMode = PrinterInfo.PrintMode.FIT_TO_PAPER
            info.isAutoCut = true
            info.isCutAtEnd = true
            info.isHalfCut = false
            info.isSpecialTape = false
            info.labelNameIndex = LabelInfo.PT.W18.ordinal
            info.printQuality = PrinterInfo.PrintQuality.HIGH_RESOLUTION_USING_HR_IMAGE
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
     * dots. Flutter labels are landscape — rotate 90° CW.
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

    private fun scaleToTapeWidth(src: Bitmap, targetWidth: Int): Bitmap {
        // Only upscale — never shrink HR art; FIT_TO_PAPER fills remaining room.
        if (targetWidth <= 0 || src.width >= targetWidth - 2) return src
        val scale = targetWidth.toFloat() / src.width.toFloat()
        val targetHeight = (src.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, targetWidth, targetHeight, true)
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}

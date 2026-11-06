package com.example.cribhub

import android.app.Service
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.IBinder
import android.util.Log
import com.brother.ptouch.sdk.LabelInfo
import com.brother.ptouch.sdk.Printer
import com.brother.ptouch.sdk.PrinterInfo
import java.io.File
import java.util.concurrent.Executors

/**
 * Runs Brother SDK printing in a **separate process** (`:brother_print`).
 * If the SDK JNI-aborts, only this process dies — the Flutter UI stays up and
 * can fall back to the system print sheet.
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
        val bitmap = if (decoded.config == Bitmap.Config.ARGB_8888 && decoded.isMutable) {
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

        // Prefer app-specific external dir (Brother docs / SO: unset workPath → JNI abort).
        val workDir = (getExternalFilesDir(null) ?: filesDir)
            .let { File(it, "brother_print") }
            .apply { mkdirs() }
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
                val fileStatus = printer.printFile(pngPath)
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

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}

package com.example.cribhub

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.util.Log
import android.widget.Toast
import com.brother.ptouch.sdk.LabelInfo
import com.brother.ptouch.sdk.Printer
import com.brother.ptouch.sdk.PrinterInfo
import com.brother.ptouch.sdk.PrinterStatus
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "DharmaLabelPrint"
        private const val REQUEST_BLUETOOTH_CONNECT = 9001
        private const val PREFS = "dharma_label_print"
        private const val KEY_CRASHED = "brother_sdk_crashed"
        private const val KEY_SAFE_VERSION = "brother_safe_version"
        private const val BLE_RESOLVE_TIMEOUT_MS = 5_000L
    }

    private val executor = Executors.newSingleThreadExecutor()
    private var pendingPrintBytes: ByteArray? = null
    private var pendingPrintResult: MethodChannel.Result? = null

    private val prefs: SharedPreferences
        get() = getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        clearCrashFlagIfNewVersion()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.cribhub/label_printer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "printLabel" -> {
                        val bytes = extractImageBytes(
                            (call.arguments as? Map<*, *>)?.get("imageBytes")
                        )
                        if (bytes == null) {
                            replyError(result, "INVALID_ARGS", "imageBytes required")
                            return@setMethodCallHandler
                        }
                        if (prefs.getBoolean(KEY_CRASHED, false)) {
                            // Previous attempt died inside native printImage (JNI abort).
                            replyError(
                                result,
                                "BROTHER_UNSAFE",
                                "Brother SDK crashed on the last print; falling back to system print",
                            )
                            return@setMethodCallHandler
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val needConnect = checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
                            val needScan = checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED
                            if (needConnect || needScan) {
                                pendingPrintBytes = bytes
                                pendingPrintResult = result
                                val perms = mutableListOf<String>()
                                if (needConnect) perms.add(Manifest.permission.BLUETOOTH_CONNECT)
                                if (needScan) perms.add(Manifest.permission.BLUETOOTH_SCAN)
                                requestPermissions(perms.toTypedArray(), REQUEST_BLUETOOTH_CONNECT)
                                return@setMethodCallHandler
                            }
                        }
                        executor.execute { runPrintLabel(bytes, result) }
                    }
                    "clearBrotherCrashFlag" -> {
                        prefs.edit().putBoolean(KEY_CRASHED, false).apply()
                        replySuccess(result, true)
                    }
                    "exportLabelPng" -> {
                        val args = call.arguments as? Map<*, *>
                        val bytes = extractImageBytes(args?.get("imageBytes"))
                        if (bytes != null) {
                            try {
                                val binCode = (args?.get("binCode") as? String) ?: "bin"
                                val safeBin = binCode.replace(Regex("[^A-Za-z0-9_-]"), "_")
                                val file = File(cacheDir, "label_${safeBin}_${System.currentTimeMillis()}.png")
                                FileOutputStream(file).use { it.write(bytes) }
                                replySuccess(result, file.absolutePath)
                            } catch (e: Exception) {
                                replyError(result, "EXPORT_ERROR", e.message ?: "Failed to export label PNG")
                            }
                        } else {
                            replyError(result, "INVALID_ARGS", "imageBytes required")
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** New APK version clears the crash latch so we retry one-tap Brother print. */
    private fun clearCrashFlagIfNewVersion() {
        val versionCode = try {
            if (Build.VERSION.SDK_INT >= 28) {
                packageManager.getPackageInfo(packageName, 0).longVersionCode.toInt()
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0).versionCode
            }
        } catch (_: Exception) {
            0
        }
        if (prefs.getInt(KEY_SAFE_VERSION, -1) != versionCode) {
            prefs.edit()
                .putBoolean(KEY_CRASHED, false)
                .putInt(KEY_SAFE_VERSION, versionCode)
                .apply()
            Log.i(TAG, "cleared Brother crash flag for versionCode=$versionCode")
        }
    }

    private fun extractImageBytes(raw: Any?): ByteArray? {
        return when (raw) {
            is ByteArray -> raw
            is ByteBuffer -> {
                val buf = raw.duplicate()
                val out = ByteArray(buf.remaining())
                buf.get(out)
                out
            }
            is List<*> -> try {
                raw.map { (it as Number).toInt().toByte() }.toByteArray()
            } catch (_: Exception) {
                null
            }
            else -> null
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_BLUETOOTH_CONNECT) return
        val bytes = pendingPrintBytes
        val res = pendingPrintResult
        pendingPrintBytes = null
        pendingPrintResult = null
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (granted && bytes != null && res != null) {
            executor.execute { runPrintLabel(bytes, res) }
        } else if (res != null) {
            runOnUiThread {
                Toast.makeText(this, "Bluetooth permission needed for printing", Toast.LENGTH_LONG).show()
            }
            replyError(res, "PERMISSION_DENIED", "Bluetooth permission required for label printing")
        }
    }

    private fun replySuccess(result: MethodChannel.Result, value: Any? = null) {
        runOnUiThread {
            try {
                result.success(value)
            } catch (_: Exception) {
            }
        }
    }

    private fun replyError(result: MethodChannel.Result, code: String, message: String?) {
        runOnUiThread {
            try {
                result.error(code, message, null)
            } catch (_: Exception) {
            }
        }
    }

    private fun runPrintLabel(pngBytes: ByteArray, result: MethodChannel.Result) {
        val replied = AtomicBoolean(false)
        fun success() {
            if (replied.compareAndSet(false, true)) replySuccess(result)
        }
        fun error(code: String, message: String?) {
            Log.e(TAG, "printLabel error $code: $message")
            if (replied.compareAndSet(false, true)) replyError(result, code, message)
        }

        try {
            Log.i(TAG, "printLabel start bytes=${pngBytes.size}")
            val decoded = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size)
                ?: run {
                    error("DECODE_ERROR", "Failed to decode image")
                    return
                }
            val bitmap = if (decoded.config == Bitmap.Config.ARGB_8888 && decoded.isMutable) {
                decoded
            } else {
                decoded.copy(Bitmap.Config.ARGB_8888, true)?.also {
                    if (decoded !== it) decoded.recycle()
                } ?: run {
                    error("DECODE_ERROR", "Failed to convert bitmap to ARGB_8888")
                    return
                }
            }

            val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter: BluetoothAdapter? = bluetoothManager?.adapter
            if (adapter == null || !adapter.isEnabled) {
                runOnUiThread { Toast.makeText(this, "Bluetooth is off", Toast.LENGTH_SHORT).show() }
                error("BLUETOOTH_OFF", "Bluetooth is disabled")
                return
            }

            val bonded = try {
                adapter.bondedDevices.orEmpty()
            } catch (e: SecurityException) {
                error("PERMISSION_DENIED", "Bluetooth permission required for label printing")
                return
            }
            val pairedDevice = pickBrotherDevice(bonded)
            if (pairedDevice == null) {
                runOnUiThread { Toast.makeText(this, "No Brother/PT printer paired", Toast.LENGTH_LONG).show() }
                error("NO_PRINTER", "Pair the PT-P910BT (or PT-P710BT) in Bluetooth settings first")
                return
            }

            val deviceName = pairedDevice.name ?: ""
            Log.i(TAG, "paired printer name=$deviceName address=${pairedDevice.address}")
            val model = when {
                deviceName.contains("P910", ignoreCase = true) -> PrinterInfo.Model.PT_P910BT
                deviceName.contains("P715", ignoreCase = true) -> PrinterInfo.Model.PT_P715eBT
                deviceName.contains("P710", ignoreCase = true) -> PrinterInfo.Model.PT_P710BT
                else -> PrinterInfo.Model.PT_P910BT
            }

            val workDir = File(filesDir, "brother_print").apply { mkdirs() }
            // Prefer printFile (file path) — avoids some printImage JNI bitmap crashes.
            val labelFile = File(workDir, "label_${System.currentTimeMillis()}.png")
            FileOutputStream(labelFile).use { out ->
                if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)) {
                    error("ENCODE_ERROR", "Failed to write label PNG for Brother SDK")
                    return
                }
            }

            val portsToTry = listOf(PrinterInfo.Port.BLUETOOTH, PrinterInfo.Port.BLE)
            var lastError: String? = null

            for (port in portsToTry) {
                Log.i(TAG, "trying port=$port model=$model")
                val printer = Printer()
                // Cordova / Brother samples: set classic + BLE adapters before print.
                printer.setBluetooth(adapter)
                try {
                    printer.setBluetoothLowEnergy(this, adapter, BLE_RESOLVE_TIMEOUT_MS)
                } catch (e: Exception) {
                    Log.w(TAG, "setBluetoothLowEnergy: ${e.message}")
                }

                val info = printer.printerInfo
                info.printerModel = model
                info.port = port
                info.macAddress = pairedDevice.address
                info.workPath = workDir.absolutePath
                info.printMode = PrinterInfo.PrintMode.FIT_TO_PAPER
                info.isAutoCut = true
                info.isCutAtEnd = true
                info.isHalfCut = false
                info.isSpecialTape = false
                // Brother samples / Cordova use enum ordinal (W18 → 4), not getId().
                info.labelNameIndex = LabelInfo.PT.W18.ordinal
                info.printQuality = PrinterInfo.PrintQuality.HIGH_RESOLUTION
                info.skipStatusCheck = true
                if (!printer.setPrinterInfo(info)) {
                    lastError = "setPrinterInfo failed for $port"
                    Log.w(TAG, lastError!!)
                    continue
                }

                // Mirror cut flags into LabelInfo as some PT samples require.
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
                    Log.w(TAG, lastError!!)
                    continue
                }

                // Latch BEFORE native print. If JNI aborts, next launch sees KEY_CRASHED.
                prefs.edit().putBoolean(KEY_CRASHED, true).commit()

                val status: PrinterStatus = try {
                    val fileStatus = printer.printFile(labelFile.absolutePath)
                    if (fileStatus.errorCode == PrinterInfo.ErrorCode.ERROR_NONE) {
                        fileStatus
                    } else {
                        Log.w(TAG, "printFile ${fileStatus.errorCode}, trying printImage")
                        printer.printImage(bitmap)
                    }
                } finally {
                    try {
                        printer.endCommunication()
                    } catch (e: Exception) {
                        Log.w(TAG, "endCommunication: ${e.message}")
                    }
                }

                if (status.errorCode == PrinterInfo.ErrorCode.ERROR_NONE) {
                    prefs.edit().putBoolean(KEY_CRASHED, false).apply()
                    try {
                        labelFile.delete()
                    } catch (_: Exception) {
                    }
                    runOnUiThread {
                        Toast.makeText(this, "Label sent to printer", Toast.LENGTH_SHORT).show()
                    }
                    success()
                    Log.i(TAG, "printLabel success via $port")
                    return
                }

                prefs.edit().putBoolean(KEY_CRASHED, false).apply()
                lastError = "Print error via $port: ${status.errorCode}"
                Log.w(TAG, lastError!!)
            }

            error("PRINT_FAILED", lastError ?: "Print failed")
        } catch (e: Throwable) {
            // Soft failures only. JNI aborts never reach here — KEY_CRASHED stays true.
            Log.e(TAG, "printLabel exception", e)
            prefs.edit().putBoolean(KEY_CRASHED, false).apply()
            error("PRINT_ERROR", e.message ?: e.javaClass.simpleName)
        }
    }

    private fun pickBrotherDevice(bonded: Set<BluetoothDevice>): BluetoothDevice? {
        return bonded.firstOrNull { device ->
            (device.name ?: "").contains("P910", ignoreCase = true)
        } ?: bonded.firstOrNull { device ->
            val name = device.name ?: ""
            name.contains("PT-", ignoreCase = true) || name.contains("Brother", ignoreCase = true)
        }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}

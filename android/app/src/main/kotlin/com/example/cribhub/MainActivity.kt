package com.example.cribhub

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Build
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
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {

    companion object {
        private const val REQUEST_BLUETOOTH_CONNECT = 9001
    }

    private val executor = Executors.newSingleThreadExecutor()
    private var pendingPrintBytes: ByteArray? = null
    private var pendingPrintResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.cribhub/label_printer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "printLabel" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<String, Any>
                        val imageBytes = args?.get("imageBytes") as? List<*>
                        if (imageBytes != null) {
                            val bytes = imageBytes.map { (it as Number).toInt().toByte() }.toByteArray()
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
                                } else {
                                    executor.execute { runPrintLabel(bytes, result) }
                                }
                            } else {
                                executor.execute { runPrintLabel(bytes, result) }
                            }
                        } else {
                            replyError(result, "INVALID_ARGS", "imageBytes required")
                        }
                    }
                    "exportLabelPng" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<String, Any>
                        val imageBytes = args?.get("imageBytes") as? List<*>
                        if (imageBytes != null) {
                            try {
                                val bytes = imageBytes.map { (it as Number).toInt().toByte() }.toByteArray()
                                val binCode = (args["binCode"] as? String) ?: "bin"
                                val safeBin = binCode.replace(Regex("[^A-Za-z0-9_-]"), "_")
                                val fileName = "label_${safeBin}_${System.currentTimeMillis()}.png"
                                val file = File(cacheDir, fileName)
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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_BLUETOOTH_CONNECT) {
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
    }

    /**
     * Flutter MethodChannel.Result must be invoked on the main/UI thread.
     * Calling it from [executor] hard-crashes the activity ("app closes").
     */
    private fun replySuccess(result: MethodChannel.Result, value: Any? = null) {
        runOnUiThread {
            try {
                result.success(value)
            } catch (_: Exception) {
                // Reply already submitted or channel gone — ignore.
            }
        }
    }

    private fun replyError(result: MethodChannel.Result, code: String, message: String?) {
        runOnUiThread {
            try {
                result.error(code, message, null)
            } catch (_: Exception) {
                // Reply already submitted or channel gone — ignore.
            }
        }
    }

    private fun runPrintLabel(pngBytes: ByteArray, result: MethodChannel.Result) {
        val replied = AtomicBoolean(false)
        fun success() {
            if (replied.compareAndSet(false, true)) replySuccess(result)
        }
        fun error(code: String, message: String?) {
            if (replied.compareAndSet(false, true)) replyError(result, code, message)
        }

        try {
            val bitmap = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size)
                ?: run {
                    error("DECODE_ERROR", "Failed to decode image")
                    return
                }

            val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter: BluetoothAdapter? = bluetoothManager?.adapter
            if (adapter == null || !adapter.isEnabled) {
                runOnUiThread { Toast.makeText(this, "Bluetooth is off", Toast.LENGTH_SHORT).show() }
                error("BLUETOOTH_OFF", "Bluetooth is disabled")
                return
            }

            // Prefer P910BT when paired; fall back to any Brother/PT device (e.g. P710BT).
            val bonded = try {
                adapter.bondedDevices.orEmpty()
            } catch (e: SecurityException) {
                error("PERMISSION_DENIED", "Bluetooth permission required for label printing")
                return
            }
            val pairedDevice = bonded.firstOrNull { device ->
                (device.name ?: "").contains("P910", ignoreCase = true)
            } ?: bonded.firstOrNull { device ->
                val name = device.name ?: ""
                name.contains("PT-", ignoreCase = true) || name.contains("Brother", ignoreCase = true)
            }
            if (pairedDevice == null) {
                runOnUiThread { Toast.makeText(this, "No Brother/PT printer paired", Toast.LENGTH_LONG).show() }
                error("NO_PRINTER", "Pair the PT-P910BT (or PT-P710BT) in Bluetooth settings first")
                return
            }

            val deviceName = pairedDevice.name ?: ""
            val model = when {
                deviceName.contains("P910", ignoreCase = true) -> PrinterInfo.Model.PT_P910BT
                deviceName.contains("P715", ignoreCase = true) -> PrinterInfo.Model.PT_P715eBT
                deviceName.contains("P710", ignoreCase = true) -> PrinterInfo.Model.PT_P710BT
                else -> PrinterInfo.Model.PT_P910BT
            }

            val printerInfo = PrinterInfo().apply {
                printerModel = model
                port = PrinterInfo.Port.BLUETOOTH
                macAddress = pairedDevice.address
                workPath = cacheDir.absolutePath
                printMode = PrinterInfo.PrintMode.FIT_TO_PAPER
                isAutoCut = true
                // 18mm TZe for all shop labels (tools + material).
                labelNameIndex = LabelInfo.PT.W18.ordinal
                printQuality = PrinterInfo.PrintQuality.HIGH_RESOLUTION
            }

            val printer = Printer()
            printer.setBluetooth(adapter)
            printer.setPrinterInfo(printerInfo)

            if (!printer.startCommunication()) {
                error("CONNECT_FAILED", "Could not connect to printer")
                return
            }

            val status: PrinterStatus = try {
                printer.printImage(bitmap)
            } finally {
                try {
                    printer.endCommunication()
                } catch (_: Exception) {
                }
            }

            if (status.errorCode != PrinterInfo.ErrorCode.ERROR_NONE) {
                error("PRINT_FAILED", "Print error: ${status.errorCode}")
                return
            }

            runOnUiThread { Toast.makeText(this, "Label sent to printer", Toast.LENGTH_SHORT).show() }
            success()
        } catch (e: Throwable) {
            error("PRINT_ERROR", e.message ?: "Unknown error")
        }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}

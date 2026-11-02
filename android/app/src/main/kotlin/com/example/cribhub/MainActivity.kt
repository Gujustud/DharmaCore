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
                            result.error("INVALID_ARGS", "imageBytes required", null)
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
                                result.success(file.absolutePath)
                            } catch (e: Exception) {
                                result.error("EXPORT_ERROR", e.message ?: "Failed to export label PNG", null)
                            }
                        } else {
                            result.error("INVALID_ARGS", "imageBytes required", null)
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
                res.error("PERMISSION_DENIED", "Bluetooth permission required for label printing", null)
            }
        }
    }

    private fun runPrintLabel(pngBytes: ByteArray, result: MethodChannel.Result) {
        try {
            val bitmap = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size)
                ?: run {
                    result.error("DECODE_ERROR", "Failed to decode image", null)
                    return
                }

            val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter: BluetoothAdapter? = bluetoothManager?.adapter
            if (adapter == null || !adapter.isEnabled) {
                runOnUiThread { Toast.makeText(this, "Bluetooth is off", Toast.LENGTH_SHORT).show() }
                result.error("BLUETOOTH_OFF", "Bluetooth is disabled", null)
                return
            }

            // Prefer P910BT when paired; fall back to any Brother/PT device (e.g. P710BT).
            val bonded = adapter.bondedDevices.orEmpty()
            val pairedDevice = bonded.firstOrNull { device ->
                (device.name ?: "").contains("P910", ignoreCase = true)
            } ?: bonded.firstOrNull { device ->
                val name = device.name ?: ""
                name.contains("PT-", ignoreCase = true) || name.contains("Brother", ignoreCase = true)
            }
            if (pairedDevice == null) {
                runOnUiThread { Toast.makeText(this, "No Brother/PT printer paired", Toast.LENGTH_LONG).show() }
                result.error("NO_PRINTER", "Pair the PT-P910BT (or PT-P710BT) in Bluetooth settings first", null)
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
                result.error("CONNECT_FAILED", "Could not connect to printer", null)
                return
            }

            val status: PrinterStatus = printer.printImage(bitmap)
            printer.endCommunication()

            if (status.errorCode != PrinterInfo.ErrorCode.ERROR_NONE) {
                result.error("PRINT_FAILED", "Print error: ${status.errorCode}", null)
                return
            }

            runOnUiThread { Toast.makeText(this, "Label sent to printer", Toast.LENGTH_SHORT).show() }
            result.success(null)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message ?: "Unknown error", null)
        }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}

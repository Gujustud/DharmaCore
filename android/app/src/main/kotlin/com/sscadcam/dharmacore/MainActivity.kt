package com.sscadcam.dharmacore

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "DharmaLabelPrint"
        private const val REQUEST_BLUETOOTH_CONNECT = 9001
        // Keep short: if :brother_print JNI-dies we shouldn't wait a full minute.
        private const val PRINT_TIMEOUT_MS = 20_000L
        private const val POLL_MS = 200L
    }

    private val executor = Executors.newSingleThreadExecutor()
    private var pendingPrintBytes: ByteArray? = null
    private var pendingPrintResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sscadcam.dharmacore/label_printer")
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
                        executor.execute { runPrintViaService(bytes, result) }
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
            executor.execute { runPrintViaService(bytes, res) }
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

    /**
     * Orchestrates print in [BrotherPrintService] (`:brother_print` process).
     * UI process only waits for a result file — JNI aborts kill the service
     * process only, then we surface BROTHER_CRASH for Dart system-print fallback.
     */
    private fun runPrintViaService(pngBytes: ByteArray, result: MethodChannel.Result) {
        val replied = AtomicBoolean(false)
        fun success() {
            if (replied.compareAndSet(false, true)) replySuccess(result)
        }
        fun error(code: String, message: String?) {
            Log.e(TAG, "printLabel error $code: $message")
            if (replied.compareAndSet(false, true)) replyError(result, code, message)
        }

        try {
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
            val modelName = when {
                deviceName.contains("P710", ignoreCase = true) -> "PT_P710BT"
                deviceName.contains("P715", ignoreCase = true) -> "PT_P715eBT"
                else -> "PT_P910BT"
            }

            val jobId = UUID.randomUUID().toString()
            val jobsDir = BrotherPrintService.jobsDir(this)
            val pngFile = File(jobsDir, "$jobId.png")
            FileOutputStream(pngFile).use { it.write(pngBytes) }
            val resultFile = BrotherPrintService.resultFile(this, jobId)
            if (resultFile.exists()) resultFile.delete()

            Log.i(TAG, "starting BrotherPrintService job=$jobId model=$modelName mac=${pairedDevice.address}")
            val intent = Intent(this, BrotherPrintService::class.java).apply {
                action = BrotherPrintService.ACTION_PRINT
                putExtra(BrotherPrintService.EXTRA_PNG_PATH, pngFile.absolutePath)
                putExtra(BrotherPrintService.EXTRA_MAC, pairedDevice.address)
                putExtra(BrotherPrintService.EXTRA_MODEL, modelName)
                putExtra(BrotherPrintService.EXTRA_JOB_ID, jobId)
            }
            startService(intent)

            val deadline = System.currentTimeMillis() + PRINT_TIMEOUT_MS
            while (System.currentTimeMillis() < deadline) {
                if (resultFile.isFile) {
                    val lines = resultFile.readText().lines()
                    val code = lines.firstOrNull()?.trim().orEmpty()
                    val message = lines.drop(1).joinToString("\n").ifBlank { null }
                    try {
                        resultFile.delete()
                        pngFile.delete()
                    } catch (_: Exception) {
                    }
                    if (code == "OK") {
                        runOnUiThread {
                            Toast.makeText(this, "Label sent to printer", Toast.LENGTH_SHORT).show()
                        }
                        success()
                    } else {
                        error(code.ifBlank { "PRINT_FAILED" }, message)
                    }
                    return
                }
                Thread.sleep(POLL_MS)
            }

            // No result → service hung or JNI-killed the :brother_print process.
            try {
                pngFile.delete()
            } catch (_: Exception) {
            }
            error(
                "BROTHER_CRASH",
                "Brother print process crashed or timed out. PT-P910BT needs the Brother SDK (it will not appear in Android's system printer list).",
            )
        } catch (e: Throwable) {
            Log.e(TAG, "printLabel exception", e)
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

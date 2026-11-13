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
        /** Per-printer wait; keep short so we can try the other PT if this one is off. */
        private const val PRINT_TIMEOUT_MS = 12_000L
        private const val POLL_MS = 200L
        private const val PREFS = "brother_print"
        private const val PREF_LAST_MAC = "last_mac"
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
     * Tries each paired Brother PT in priority order (connected first, then last-used)
     * so whichever printer is powered on can take the job.
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
            val devices = orderedBrotherDevices(bonded)
            if (devices.isEmpty()) {
                runOnUiThread { Toast.makeText(this, "No Brother/PT printer paired", Toast.LENGTH_LONG).show() }
                error("NO_PRINTER", "Pair a PT-P710BT or PT-P910BT in Bluetooth settings first")
                return
            }

            val jobsDir = BrotherPrintService.jobsDir(this)
            var lastCode = "NO_PRINTER"
            var lastMessage: String? = "No Brother printer responded"
            val tried = mutableListOf<String>()

            for (device in devices) {
                val deviceName = device.name ?: device.address
                val modelName = modelNameFor(device)
                tried.add("$deviceName ($modelName)")

                val jobId = UUID.randomUUID().toString()
                val pngFile = File(jobsDir, "$jobId.png")
                FileOutputStream(pngFile).use { it.write(pngBytes) }
                val resultFile = BrotherPrintService.resultFile(this, jobId)
                if (resultFile.exists()) resultFile.delete()

                Log.i(
                    TAG,
                    "starting BrotherPrintService job=$jobId model=$modelName mac=${device.address} connected=${isBluetoothConnected(device)}",
                )
                val intent = Intent(this, BrotherPrintService::class.java).apply {
                    action = BrotherPrintService.ACTION_PRINT
                    putExtra(BrotherPrintService.EXTRA_PNG_PATH, pngFile.absolutePath)
                    putExtra(BrotherPrintService.EXTRA_MAC, device.address)
                    putExtra(BrotherPrintService.EXTRA_MODEL, modelName)
                    putExtra(BrotherPrintService.EXTRA_JOB_ID, jobId)
                }
                startService(intent)

                val deadline = System.currentTimeMillis() + PRINT_TIMEOUT_MS
                var finished = false
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
                        finished = true
                        if (code == "OK") {
                            rememberLastMac(device.address)
                            runOnUiThread {
                                Toast.makeText(
                                    this,
                                    "Label sent to $deviceName",
                                    Toast.LENGTH_SHORT,
                                ).show()
                            }
                            success()
                            return
                        }
                        lastCode = code.ifBlank { "PRINT_FAILED" }
                        lastMessage = message ?: "Print failed on $deviceName"
                        // Try next paired Brother (this one may be off / out of range).
                        Log.w(TAG, "printer $deviceName failed ($lastCode): $lastMessage — trying next if any")
                        break
                    }
                    Thread.sleep(POLL_MS)
                }

                if (!finished) {
                    try {
                        pngFile.delete()
                    } catch (_: Exception) {
                    }
                    lastCode = "BROTHER_CRASH"
                    lastMessage =
                        "$deviceName ($modelName) crashed or timed out. Make sure it is on and in range, then retry."
                    Log.w(TAG, lastMessage!!)
                }
            }

            val triedList = tried.joinToString(", ")
            error(
                lastCode,
                "${lastMessage ?: "Print failed"}. Tried: $triedList",
            )
        } catch (e: Throwable) {
            Log.e(TAG, "printLabel exception", e)
            error("PRINT_ERROR", e.message ?: e.javaClass.simpleName)
        }
    }

    /** Connected first, then last successful MAC, then name — no fixed P910 preference. */
    private fun orderedBrotherDevices(bonded: Set<BluetoothDevice>): List<BluetoothDevice> {
        val lastMac = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(PREF_LAST_MAC, null)
            ?.uppercase()
        val candidates = bonded.filter { isBrotherName(it.name) }
        return candidates.sortedWith(
            compareByDescending<BluetoothDevice> { isBluetoothConnected(it) }
                .thenByDescending { it.address.equals(lastMac, ignoreCase = true) }
                .thenBy { it.name ?: it.address },
        )
    }

    private fun isBrotherName(name: String?): Boolean {
        val n = name ?: return false
        return n.contains("PT-", ignoreCase = true) ||
            n.contains("Brother", ignoreCase = true) ||
            n.contains("P910", ignoreCase = true) ||
            n.contains("P710", ignoreCase = true) ||
            n.contains("P715", ignoreCase = true)
    }

    private fun modelNameFor(device: BluetoothDevice): String {
        val name = device.name ?: ""
        return when {
            name.contains("P710", ignoreCase = true) -> "PT_P710BT"
            name.contains("P715", ignoreCase = true) -> "PT_P715eBT"
            name.contains("P910", ignoreCase = true) -> "PT_P910BT"
            else -> "PT_P910BT"
        }
    }

    /** Best-effort "is this paired device currently connected?" (hidden API on many OEMs). */
    private fun isBluetoothConnected(device: BluetoothDevice): Boolean {
        return try {
            val method = device.javaClass.getMethod("isConnected")
            method.invoke(device) as? Boolean == true
        } catch (_: Exception) {
            false
        }
    }

    private fun rememberLastMac(mac: String) {
        try {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(PREF_LAST_MAC, mac)
                .apply()
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}

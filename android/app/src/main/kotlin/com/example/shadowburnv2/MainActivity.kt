package com.example.shadowburnv2

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections

class MainActivity: FlutterActivity() {
    private val PRIMARY_CHANNEL = "com.shadowburn.app/lock"
    private val LEGACY_CHANNEL = "com.shadowburn.lock/channel"
    private val INTENT_CHANNEL = "com.shadowburn.app/intents"

    private val TERMUX_RUN_COMMAND_PERMISSION = "com.termux.permission.RUN_COMMAND"
    private val REQUEST_CODE_TERMUX_PERMISSION = 1042

    private var lastIntentUrl: String? = null
    private var primaryMethodChannel: MethodChannel? = null
    private var legacyMethodChannel: MethodChannel? = null
    private var intentMethodChannel: MethodChannel? = null
    private var pendingTermuxPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        overridePendingTransition(0, 0)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        intent?.dataString?.let {
            lastIntentUrl = it
        }

        checkAndEnforcePenaltyOnStartup()
    }

    private fun checkAndEnforcePenaltyOnStartup() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isPrefPrefixed = prefs.getBoolean("flutter.cerberus_penalty_active", false)
            val isPrefRaw = prefs.getBoolean("cerberus_penalty_active", false)

            if (isPrefPrefixed || isPrefRaw) {
                startCoreWatcherService()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        overridePendingTransition(0, 0)
        setIntent(intent)
        intent.dataString?.let { url ->
            lastIntentUrl = url
            intentMethodChannel?.invokeMethod("onNewIntent", url)
        }
        checkAndEnforcePenaltyOnStartup()
    }

    override fun onResume() {
        super.onResume()
        overridePendingTransition(0, 0)
        checkAndEnforcePenaltyOnStartup()
    }

    override fun onPause() {
        super.onPause()
        overridePendingTransition(0, 0)
    }

    override fun onStop() {
        super.onStop()
        overridePendingTransition(0, 0)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_TERMUX_PERMISSION) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingTermuxPermissionResult?.success(granted)
            pendingTermuxPermissionResult = null
            if (!granted) {
                openAppDetailsFallback()
            }
        }
    }

    private fun isExcludedInterface(ifaceName: String): Boolean {
        return ifaceName.startsWith("rmnet") ||
            ifaceName.startsWith("ccmni") ||
            ifaceName.contains("ccmni") ||
            ifaceName.startsWith("pdp") ||
            ifaceName.startsWith("tun") ||
            ifaceName.startsWith("ppp") ||
            ifaceName == "dummy0" ||
            ifaceName == "lo"
    }

    private fun isExcludedIp(ip: String): Boolean {
        return ip.isEmpty() ||
            ip == "192.0.0.4" ||
            ip.startsWith("192.0.0.") ||
            ip.startsWith("127.") ||
            ip.startsWith("169.254.")
    }

    private fun detectLocalLanCandidates(): List<Map<String, String>> {
        val candidates = mutableListOf<Triple<Int, String, String>>()
        try {
            val rawInterfaces = NetworkInterface.getNetworkInterfaces() ?: return emptyList()
            val interfaces = Collections.list(rawInterfaces)
            for (nif in interfaces) {
                if (!nif.isUp || nif.isLoopback) continue
                val ifaceName = (nif.name ?: "").lowercase()
                if (isExcludedInterface(ifaceName)) {
                    continue
                }

                val addresses = Collections.list(nif.inetAddresses)
                for (addr in addresses) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress && !addr.isLinkLocalAddress) {
                        val ip = (addr.hostAddress ?: continue).substringBefore('%').trim()
                        if (isExcludedIp(ip)) {
                            continue
                        }
                        val priority = when {
                            ifaceName.startsWith("ap") ||
                            ifaceName.startsWith("swlan") ||
                            ifaceName.startsWith("rndis") ||
                            ifaceName.startsWith("softap") ||
                            ifaceName == "wlan1" -> 1
                            ifaceName.startsWith("wlan") ||
                            ifaceName.startsWith("eth") -> 2
                            addr.isSiteLocalAddress -> 3
                            else -> 4
                        }
                        if (priority == 4 && !addr.isSiteLocalAddress) {
                            continue
                        }
                        val label = when (priority) {
                            1 -> "Hotspot 4G ($ifaceName)"
                            2 -> "Wi-Fi ($ifaceName)"
                            else -> "LAN ($ifaceName)"
                        }
                        candidates.add(Triple(priority, ip, label))
                    }
                }
            }
        } catch (_: Exception) {
            return emptyList()
        }

        return candidates
            .sortedBy { it.first }
            .distinctBy { it.second }
            .map { mapOf("ip" to it.second, "label" to it.third) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val handler = MethodChannel.MethodCallHandler { call, result ->
            when (call.method) {
                "getInitialIntentUrl", "getInitialLink" -> {
                    val url = lastIntentUrl
                    lastIntentUrl = null
                    result.success(url)
                }

                "getLocalNetworkIps" -> {
                    result.success(detectLocalLanCandidates())
                }

                "lockScreen" -> {
                    startCoreWatcherService()
                    try {
                        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        prefs.edit()
                            .putBoolean("flutter.cerberus_penalty_active", true)
                            .putBoolean("cerberus_penalty_active", true)
                            .apply()
                    } catch (_: Exception) {}

                    result.success(true)
                }

                "unlockScreen" -> {
                    stopCoreWatcherService()
                    try {
                        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        prefs.edit()
                            .putBoolean("flutter.cerberus_penalty_active", false)
                            .putBoolean("cerberus_penalty_active", false)
                            .apply()
                    } catch (_: Exception) {}

                    result.success(true)
                }

                "openEmergencyDialer" -> {
                    try {
                        val graceIntent = Intent(this, CoreWatcherService::class.java).apply {
                            action = "ACTION_EMERGENCY_GRACE"
                        }
                        startService(graceIntent)
                    } catch (_: Exception) {}

                    try {
                        val intent = Intent(Intent.ACTION_DIAL).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        }
                        startActivity(intent)
                        overridePendingTransition(0, 0)
                    } catch (_: Exception) {}
                    result.success(true)
                }

                "openEmergencySms" -> {
                    try {
                        val graceIntent = Intent(this, CoreWatcherService::class.java).apply {
                            action = "ACTION_EMERGENCY_GRACE"
                        }
                        startService(graceIntent)
                    } catch (_: Exception) {}

                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("sms:")).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        }
                        startActivity(intent)
                        overridePendingTransition(0, 0)
                    } catch (_: Exception) {
                        try {
                            val fallback = Intent(Intent.ACTION_MAIN).apply {
                                addCategory(Intent.CATEGORY_APP_MESSAGING)
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                            }
                            startActivity(fallback)
                            overridePendingTransition(0, 0)
                        } catch (_: Exception) {}
                    }
                    result.success(true)
                }

                "resetEmergencyExemption" -> {
                    try {
                        val graceIntent = Intent(this, CoreWatcherService::class.java).apply {
                            action = "ACTION_EMERGENCY_GRACE"
                        }
                        startService(graceIntent)
                    } catch (_: Exception) {}
                    result.success(true)
                }

                "requestOverlayPermission" -> {
                    checkAndRequestPermissions()
                    result.success(true)
                }

                "checkUsagePermission", "isUsageAccessGranted" -> {
                    result.success(hasUsageStatsPermission())
                }

                "openUsageSettings" -> {
                    openDeepUsageSettings()
                    result.success(true)
                }

                "checkBatteryOptimizations" -> {
                    result.success(isBatteryOptimizationIgnored())
                }

                "openBatteryNoRestrictions" -> {
                    openDeepBatterySettings()
                    result.success(true)
                }

                "checkAllNotificationsEnabled" -> {
                    result.success(areAllNotificationsEnabled())
                }

                "checkTermuxPermission" -> {
                    result.success(isTermuxPermissionGranted())
                }

                "requestTermuxPermission" -> {
                    if (isTermuxPermissionGranted()) {
                        result.success(true)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        pendingTermuxPermissionResult?.success(false)
                        pendingTermuxPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(TERMUX_RUN_COMMAND_PERMISSION),
                            REQUEST_CODE_TERMUX_PERMISSION
                        )
                    } else {
                        openAppDetailsFallback()
                        result.success(false)
                    }
                }

                "runTermuxLanScript" -> {
                    val scriptPath = call.argument<String>("scriptPath")
                        ?: "/storage/emulated/0/Download/LAN/web/start_lan.sh"
                    val argsList = call.argument<List<*>>("args")
                        ?.mapNotNull { it?.toString() }
                        ?.toTypedArray()
                        ?: emptyArray()

                    try {
                        val intent = Intent("com.termux.RUN_COMMAND").apply {
                            setClassName("com.termux", "com.termux.app.RunCommandService")
                            putExtra("com.termux.RUN_COMMAND_PATH", "/data/data/com.termux/files/usr/bin/bash")
                            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf(scriptPath) + argsList)
                            putExtra("com.termux.RUN_COMMAND_WORKDIR", "/storage/emulated/0/Download/LAN/web")
                            putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
                            putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", "0")
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("TERMUX_RUN_FAILED", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        primaryMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRIMARY_CHANNEL).apply {
            setMethodCallHandler(handler)
        }
        legacyMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LEGACY_CHANNEL).apply {
            setMethodCallHandler(handler)
        }
        intentMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INTENT_CHANNEL).apply {
            setMethodCallHandler(handler)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        try {
            primaryMethodChannel?.setMethodCallHandler(null)
            legacyMethodChannel?.setMethodCallHandler(null)
            intentMethodChannel?.setMethodCallHandler(null)
        } catch (_: Exception) {}
        primaryMethodChannel = null
        legacyMethodChannel = null
        intentMethodChannel = null
        pendingTermuxPermissionResult = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun isTermuxPermissionGranted(): Boolean {
        return try {
            ContextCompat.checkSelfPermission(this, TERMUX_RUN_COMMAND_PERMISSION) ==
                PackageManager.PERMISSION_GRANTED
        } catch (_: Exception) {
            false
        }
    }

    private fun startCoreWatcherService() {
        try {
            val serviceIntent = Intent(this, CoreWatcherService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopCoreWatcherService() {
        try {
            val serviceIntent = Intent(this, CoreWatcherService::class.java).apply {
                action = "ACTION_STOP_COREWATCHER"
            }
            startService(serviceIntent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun isBatteryOptimizationIgnored(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
    }

    private fun areAllNotificationsEnabled(): Boolean {
        return try {
            val manager = NotificationManagerCompat.from(this)
            manager.areNotificationsEnabled()
        } catch (_: Exception) {
            true
        }
    }

    private fun hasUsageStatsPermission(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
            } else {
                appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Exception) {
            false
        }
    }

    private fun checkAndRequestPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                startActivity(intent)
                overridePendingTransition(0, 0)
                return
            }
        }
        if (!hasUsageStatsPermission()) {
            openDeepUsageSettings()
        }
    }

    private fun openDeepUsageSettings() {
        val intentWithPackage = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        try {
            startActivity(intentWithPackage)
            overridePendingTransition(0, 0)
        } catch (_: Exception) {
            val genericIntent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            try {
                startActivity(genericIntent)
                overridePendingTransition(0, 0)
            } catch (_: Exception) {
                openAppDetailsFallback()
            }
        }
    }

    private fun openDeepBatterySettings() {
        val miuiIntent = Intent().apply {
            setClassName("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity")
            putExtra("package_name", packageName)
            putExtra("package_label", "ShadowBurn")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        try {
            startActivity(miuiIntent)
            overridePendingTransition(0, 0)
            return
        } catch (_: Exception) {}

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val batteryIntent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            try {
                startActivity(batteryIntent)
                overridePendingTransition(0, 0)
                return
            } catch (_: Exception) {}
        }

        try {
            val globalBattery = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            startActivity(globalBattery)
            overridePendingTransition(0, 0)
        } catch (_: Exception) {
            openAppDetailsFallback()
        }
    }

    private fun openAppDetailsFallback() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            startActivity(intent)
            overridePendingTransition(0, 0)
        } catch (_: Exception) {}
    }
}

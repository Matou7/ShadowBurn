package com.example.shadowburnv2

import android.app.ActivityManager
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val PRIMARY_CHANNEL = "com.shadowburn.app/lock"
    private val LEGACY_CHANNEL = "com.shadowburn.lock/channel"

    @Volatile private var isLocked = false
    @Volatile private var isAppInForeground = true

    private var lastBringToFrontTime = 0L
    private val mainHandler = Handler(Looper.getMainLooper())
    private var lastIntentUrl: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
                isLocked = true
                setExcludeFromRecents(true)
                startCoreWatcherService()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.dataString?.let {
            lastIntentUrl = it
        }
    }

    override fun onResume() {
        super.onResume()
        isAppInForeground = true
        if (isLocked) {
            setExcludeFromRecents(true)
        }
    }

    override fun onPause() {
        super.onPause()
        isAppInForeground = false
        if (isLocked && System.currentTimeMillis() >= CoreWatcherService.emergencyGraceUntil) {
            bringToFrontForced()
        }
    }

    override fun onStop() {
        super.onStop()
        isAppInForeground = false
        if (isLocked && System.currentTimeMillis() >= CoreWatcherService.emergencyGraceUntil) {
            bringToFrontForced()
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isLocked && System.currentTimeMillis() >= CoreWatcherService.emergencyGraceUntil) {
            bringToFrontForced()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val handler = MethodChannel.MethodCallHandler { call, result ->
            when (call.method) {
                "getInitialIntentUrl" -> {
                    val url = lastIntentUrl
                    lastIntentUrl = null
                    result.success(url)
                }

                "lockScreen" -> {
                    isLocked = true
                    setExcludeFromRecents(true)
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
                    isLocked = false
                    stopCoreWatcherService()
                    setExcludeFromRecents(false)

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
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        }
                        startActivity(intent)
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
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        }
                        startActivity(intent)
                    } catch (_: Exception) {
                        try {
                            val fallback = Intent(Intent.ACTION_MAIN).apply {
                                addCategory(Intent.CATEGORY_APP_MESSAGING)
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(fallback)
                        } catch (_: Exception) {}
                    }
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

                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRIMARY_CHANNEL).setMethodCallHandler(handler)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LEGACY_CHANNEL).setMethodCallHandler(handler)
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

    private fun setExcludeFromRecents(exclude: Boolean) {
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val tasks = am.appTasks
            if (!tasks.isNullOrEmpty()) {
                tasks[0].setExcludeFromRecents(exclude)
            }
        } catch (_: Exception) {}
    }

    private fun bringToFrontForced() {
        if (!isLocked || isAppInForeground || System.currentTimeMillis() < CoreWatcherService.emergencyGraceUntil) return

        val now = System.currentTimeMillis()
        if (now - lastBringToFrontTime < 80) return
        lastBringToFrontTime = now

        try {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            activityManager.moveTaskToFront(taskId, ActivityManager.MOVE_TASK_WITH_HOME)
        } catch (_: Exception) {}

        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or 
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            }
            startActivity(intent)
        } catch (_: Exception) {}
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
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
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
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        try {
            startActivity(intentWithPackage)
        } catch (_: Exception) {
            val genericIntent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            try {
                startActivity(genericIntent)
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
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        try {
            startActivity(miuiIntent)
            return
        } catch (_: Exception) {}

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val batteryIntent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            try {
                startActivity(batteryIntent)
                return
            } catch (_: Exception) {}
        }

        try {
            val globalBattery = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(globalBattery)
        } catch (_: Exception) {
            openAppDetailsFallback()
        }
    }

    private fun openAppDetailsFallback() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
        } catch (_: Exception) {}
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stopCoreWatcherService()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        stopCoreWatcherService()
        super.onDestroy()
    }
}
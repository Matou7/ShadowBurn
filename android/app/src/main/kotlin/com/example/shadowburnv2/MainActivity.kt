package com.example.shadowburnv2

import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import org.json.JSONObject
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val PRIMARY_CHANNEL = "com.shadowburn.app/lock"
    private val LEGACY_CHANNEL = "com.shadowburn.lock/channel"

    @Volatile private var isLocked = false
    @Volatile private var isEmergencyExempt = false
    @Volatile private var isPatrolling = false
    @Volatile private var isAppInForeground = true
    @Volatile private var exemptionTimestamp = 0L

    private var lastBringToFrontTime = 0L
    private var patrolThread: Thread? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Stockage du deeplink d'amorçage pour Flutter
    private var lastIntentUrl: String? = null

    private val emergencyKeywords = listOf(
        "dialer", "telecom", "incall", "phone", "contacts",
        "messaging", "mms", "message", "android.apps.messaging",
        "google.android.dialer", "miui.mms"
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.dataString?.let {
            lastIntentUrl = it
        }
        restoreCerberusLockFromDisk()
    }

    /**
     * Restore the native watchdog before Flutter builds its first frame.
     * Flutter SharedPreferences stores keys with the "flutter." prefix.
     */
    private fun restoreCerberusLockFromDisk() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val explicitLock = prefs.getBoolean("flutter.cerberus_lock_active", false)
            val penalty = prefs.getBoolean("flutter.cerberus_penalty_active", false)
            val rawSave = prefs.getString("flutter.save_v3", null)
            var dungeonActive = false
            if (!rawSave.isNullOrEmpty()) {
                val save = JSONObject(rawSave)
                dungeonActive = save.has("dungeon") && !save.isNull("dungeon")
            }
            if (explicitLock || penalty || dungeonActive) {
                isLocked = true
                isEmergencyExempt = false
                setExcludeFromRecents(true)
                startCerberusWatchdog()
            }
        } catch (_: Exception) {
            // Flutter will still restore and re-arm the lock during initializeGame.
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
            isEmergencyExempt = false
            setExcludeFromRecents(true)
            startCerberusWatchdog()
        }
    }

    override fun onPause() {
        super.onPause()
        isAppInForeground = false
        if (isLocked && !isEmergencyExempt) {
            mainHandler.postDelayed({
                if (!isAppInForeground && isLocked && !isEmergencyExempt) {
                    bringToFrontForced()
                }
            }, 50)
        }
    }

    override fun onStop() {
        super.onStop()
        if (isLocked && !isEmergencyExempt) {
            mainHandler.postDelayed({
                if (!isAppInForeground && isLocked && !isEmergencyExempt) {
                    bringToFrontForced()
                }
            }, 100)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val handler = MethodChannel.MethodCallHandler { call, result ->
            when (call.method) {
                // Récupération et consommation du Deeplink scanné
                "getInitialIntentUrl" -> {
                    val url = lastIntentUrl
                    lastIntentUrl = null
                    result.success(url)
                }

                "lockScreen" -> {
                    isLocked = true
                    isEmergencyExempt = false
                    setExcludeFromRecents(true)
                    startCerberusWatchdog()
                    result.success(true)
                }
                "unlockScreen" -> {
                    isLocked = false
                    isEmergencyExempt = false
                    stopCerberusWatchdog()
                    setExcludeFromRecents(false)
                    result.success(true)
                }
                "openEmergencyDialer" -> {
                    isEmergencyExempt = true
                    exemptionTimestamp = System.currentTimeMillis()
                    startCerberusWatchdog()
                    try {
                        val intent = Intent(Intent.ACTION_DIAL).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        }
                        startActivity(intent)
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "openEmergencySms" -> {
                    isEmergencyExempt = true
                    exemptionTimestamp = System.currentTimeMillis()
                    startCerberusWatchdog()
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
                "resetEmergencyExemption" -> {
                    isEmergencyExempt = false
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

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isLocked && !isEmergencyExempt) {
            mainHandler.postDelayed({
                if (!isAppInForeground && isLocked && !isEmergencyExempt) {
                    bringToFrontForced()
                }
            }, 40)
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

    private fun startCerberusWatchdog() {
        if (isPatrolling) return
        isPatrolling = true

        patrolThread = Thread {
            while (isPatrolling && isLocked) {
                try {
                    Thread.sleep(300)
                } catch (e: InterruptedException) {
                    break
                }

                if (!isLocked || !isPatrolling) break
                if (isAppInForeground) continue

                val now = System.currentTimeMillis()

                if (isEmergencyExempt) {
                    if (now - exemptionTimestamp < 3000) continue

                    val currentApp = getForegroundPackageName()
                    if (currentApp.isNotEmpty()) {
                        val isOwnApp = currentApp == packageName
                        val isEmergency = isEmergencyApp(currentApp)
                        val isLauncher = isLauncherApp(currentApp)

                        if (isLauncher || (!isOwnApp && !isEmergency)) {
                            isEmergencyExempt = false
                            mainHandler.post { bringToFrontForced() }
                        }
                    }
                } else {
                    mainHandler.post { bringToFrontForced() }
                }
            }
        }
        patrolThread?.start()
    }

    private fun stopCerberusWatchdog() {
        isPatrolling = false
        patrolThread?.interrupt()
        patrolThread = null
    }

    private fun isEmergencyApp(pkg: String): Boolean {
        if (pkg.isEmpty()) return false
        val lower = pkg.lowercase()
        return emergencyKeywords.any { lower.contains(it) }
    }

    private fun isLauncherApp(pkg: String): Boolean {
        if (pkg.isEmpty()) return false
        val lower = pkg.lowercase()
        return lower.contains("launcher") || lower.contains("miui.home") || lower.contains("systemui")
    }

    private fun getForegroundPackageName(): String {
        try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val time = System.currentTimeMillis()
            val events = usm.queryEvents(time - 1000 * 10, time)
            val event = UsageEvents.Event()
            var lastForegroundApp = ""

            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED) {
                    lastForegroundApp = event.packageName
                }
            }
            if (lastForegroundApp.isNotEmpty()) return lastForegroundApp

            val appList = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, time - 1000 * 5, time)
            if (!appList.isNullOrEmpty()) {
                return appList.maxByOrNull { it.lastTimeUsed }?.packageName ?: ""
            }
        } catch (_: Exception) {}
        return ""
    }

    private fun bringToFrontForced() {
        if (!isLocked || isEmergencyExempt || isAppInForeground) return

        val now = System.currentTimeMillis()
        if (now - lastBringToFrontTime < 400) return
        lastBringToFrontTime = now

        try {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            activityManager.moveTaskToFront(taskId, ActivityManager.MOVE_TASK_WITH_HOME)
        } catch (_: Exception) {}

        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
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
        stopCerberusWatchdog()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        stopCerberusWatchdog()
        super.onDestroy()
    }
}
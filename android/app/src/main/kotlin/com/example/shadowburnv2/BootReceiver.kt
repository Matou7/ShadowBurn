package com.example.shadowburnv2

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.time.Instant

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (Intent.ACTION_BOOT_COMPLETED == action ||
            "android.intent.action.QUICKBOOT_POWERON" == action ||
            "com.htc.intent.action.QUICKBOOT_POWERON" == action) {

            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isPenaltyActive = prefs.getBoolean("flutter.cerberus_penalty_active", false)
            val explicitLock = prefs.getBoolean("flutter.cerberus_lock_active", false)
            var shouldForceAwaken = isPenaltyActive || explicitLock

            if (!shouldForceAwaken) {
                val rawSave = prefs.getString("flutter.save_v3", null)
                if (!rawSave.isNullOrEmpty()) {
                    try {
                        val json = JSONObject(rawSave)
                        val now = Instant.now()
                        if (json.optBoolean("penaltyActive", false)) {
                            shouldForceAwaken = true
                        }

                        // Any active dungeon is a prison, including an overdue dungeon.
                        // Expiry never cancels the lock or releases the player.
                        if (json.has("dungeon") && !json.isNull("dungeon")) {
                            shouldForceAwaken = true
                        }

                        if (!shouldForceAwaken && json.has("threats") && !json.isNull("threats")) {
                            val threats = json.getJSONArray("threats")
                            for (i in 0 until threats.length()) {
                                val t = threats.getJSONObject(i)
                                val expiresAtStr = t.optString("expiresAt", null)
                                if (!expiresAtStr.isNullOrEmpty()) {
                                    val expiry = Instant.parse(expiresAtStr)
                                    if (now.isAfter(expiry)) {
                                        shouldForceAwaken = true
                                        break
                                    }
                                }
                            }
                        }
                    } catch (_: Exception) {}
                }
            }

            if (shouldForceAwaken) {
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
                context.startActivity(launchIntent)
            }
        }
    }
}
package com.example.shadowburnv2

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON" ||
            action == "ACTION_CERBERUS_RESURRECT") {

            try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val isPrefPrefixed = prefs.getBoolean("flutter.cerberus_penalty_active", false)
                val isPrefRaw = prefs.getBoolean("cerberus_penalty_active", false)

                if (isPrefPrefixed || isPrefRaw) {
                    val serviceIntent = Intent(context, CoreWatcherService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(serviceIntent)
                    } else {
                        context.startService(serviceIntent)
                    }

                    val launchIntent = Intent(context, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                                Intent.FLAG_ACTIVITY_SINGLE_TOP or 
                                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                                0x00800000 or 0x00200000
                    }
                    context.startActivity(launchIntent)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}
package com.example.shadowburnv2

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val currentAction = intent.action
        if (currentAction == Intent.ACTION_BOOT_COMPLETED ||
            currentAction == Intent.ACTION_MY_PACKAGE_REPLACED ||
            currentAction == "android.intent.action.QUICKBOOT_POWERON" ||
            currentAction == "ACTION_CERBERUS_RESURRECT") {

            try {
                val sharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val isPrefPrefixed = sharedPreferences.getBoolean("flutter.cerberus_penalty_active", false)
                val isPrefRaw = sharedPreferences.getBoolean("cerberus_penalty_active", false)

                if (isPrefPrefixed || isPrefRaw) {
                    val resurrectionIntent = Intent(context, BootReceiver::class.java).apply {
                        setAction("ACTION_CERBERUS_RESURRECT")
                    }
                    
                    val pFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }
                    
                    val broadcastPendingIntent = PendingIntent.getBroadcast(context, 9999, resurrectionIntent, pFlags)
                    val alarmManagerService = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                    
                    if (alarmManagerService != null) {
                        val triggerEpochTime = System.currentTimeMillis() + 10L // Résurrection en 10 ms
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            alarmManagerService.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerEpochTime, broadcastPendingIntent)
                        } else {
                            alarmManagerService.setExact(AlarmManager.RTC_WAKEUP, triggerEpochTime, broadcastPendingIntent)
                        }
                    }

                    val watcherServiceIntent = Intent(context, CoreWatcherService::class.java)
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(watcherServiceIntent)
                        } else {
                            context.startService(watcherServiceIntent)
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }

                    val mainActivityLaunchIntent = Intent(context, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                                Intent.FLAG_ACTIVITY_SINGLE_TOP or 
                                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                                0x00800000 or 0x00200000
                    }
                    context.startActivity(mainActivityLaunchIntent)
                }
            } catch (exception: Exception) {
                exception.printStackTrace()
            }
        }
    }
}
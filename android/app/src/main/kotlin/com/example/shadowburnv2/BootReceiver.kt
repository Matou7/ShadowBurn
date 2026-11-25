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
            currentAction == "com.htc.intent.action.QUICKBOOT_POWERON" ||
            currentAction == "ACTION_CERBERUS_RESURRECT"
        ) {
            try {
                if (CoreWatcherService.isPenaltyActiveInPrefs(context)) {
                    val resurrectionIntent = Intent(context, BootReceiver::class.java).apply {
                        action = "ACTION_CERBERUS_RESURRECT"
                    }

                    val pFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }

                    val broadcastPendingIntent = PendingIntent.getBroadcast(
                        context,
                        9999,
                        resurrectionIntent,
                        pFlags
                    )
                    val alarmManagerService =
                        context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager

                    if (alarmManagerService != null) {
                        val triggerEpochTime = System.currentTimeMillis() + 16000L
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            alarmManagerService.setExactAndAllowWhileIdle(
                                AlarmManager.RTC_WAKEUP,
                                triggerEpochTime,
                                broadcastPendingIntent
                            )
                        } else {
                            alarmManagerService.setExact(
                                AlarmManager.RTC_WAKEUP,
                                triggerEpochTime,
                                broadcastPendingIntent
                            )
                        }
                    }

                    val watcherServiceIntent = Intent(context, CoreWatcherService::class.java).apply {
                        action = "ACTION_FORCE_BRING_TO_FRONT"
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(watcherServiceIntent)
                        } else {
                            context.startService(watcherServiceIntent)
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            } catch (exception: Exception) {
                exception.printStackTrace()
            }
        }
    }
}
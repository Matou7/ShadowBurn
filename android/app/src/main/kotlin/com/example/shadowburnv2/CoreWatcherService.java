package com.example.shadowburnv2;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.app.usage.UsageEvents;
import android.app.usage.UsageStatsManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import androidx.core.app.NotificationCompat;
import java.util.Arrays;
import java.util.List;

public class CoreWatcherService extends Service {
    private static final String CHANNEL_ID = "CoreWatcherSystemLockChannel";
    private static final int NOTIFICATION_ID = 7777;
    private static final int RESURRECT_REQUEST_CODE = 9999;
    private static final long PATROL_INTERVAL_MS = 200L;
    private static final long USAGE_LOOKBACK_MS = 2500L;
    private static final long GRACE_DURATION_MS = 15000L;
    private static final long ALARM_MIN_INTERVAL_MS = 15000L;
    private static final long ALARM_DELAY_MS = 16000L;

    private PowerManager.WakeLock wakeLock = null;
    private volatile boolean isRunning = false;
    private Thread patrolThread = null;
    private long lastAlarmScheduledMs = 0L;
    private volatile String lastKnownForegroundPkg = "";

    public static volatile long emergencyGraceUntil = 0L;

    private static final List<String> EMERGENCY_WHITELIST = Arrays.asList(
        "com.google.android.dialer",
        "com.android.dialer",
        "com.samsung.android.dialer",
        "com.miui.dialer",
        "com.google.android.apps.messaging",
        "com.android.mms",
        "com.samsung.android.messaging",
        "com.miui.mms",
        "com.android.server.telecom",
        "com.android.contacts",
        "com.google.android.contacts",
        "telecom",
        "dialer",
        "mms",
        "messaging",
        "incallui"
    );

    public static boolean isPenaltyActiveInPrefs(Context context) {
        if (context == null) return false;
        SharedPreferences prefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE
        );
        return prefs.getBoolean("flutter.cerberus_penalty_active", false)
            || prefs.getBoolean("cerberus_penalty_active", false);
    }

    public static void grantEmergencyGrace(Context context) {
        emergencyGraceUntil = System.currentTimeMillis() + GRACE_DURATION_MS;
        if (context != null) {
            try {
                Intent graceIntent = new Intent(context, CoreWatcherService.class);
                graceIntent.setAction("ACTION_EMERGENCY_GRACE");
                context.startService(graceIntent);
            } catch (Exception ignored) {}
        }
    }

    private String getHomeLauncherPackageName() {
        try {
            Intent intent = new Intent(Intent.ACTION_MAIN);
            intent.addCategory(Intent.CATEGORY_HOME);
            ResolveInfo resolveInfo = getPackageManager()
                .resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY);
            if (resolveInfo != null && resolveInfo.activityInfo != null) {
                return resolveInfo.activityInfo.packageName;
            }
        } catch (Exception ignored) {}
        return "";
    }

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String actionVal = (intent != null) ? intent.getAction() : null;

        if ("ACTION_STOP_COREWATCHER".equals(actionVal)) {
            isRunning = false;
            emergencyGraceUntil = 0L;
            cancelAlarmResurrection();
            releaseWakeLockSafe();
            stopForeground(true);
            stopSelf();
            return START_NOT_STICKY;
        }

        if ("ACTION_EMERGENCY_GRACE".equals(actionVal)) {
            emergencyGraceUntil = System.currentTimeMillis() + GRACE_DURATION_MS;
            return START_STICKY;
        }

        if (!isPenaltyActiveInPrefs(this)) {
            isRunning = false;
            cancelAlarmResurrection();
            releaseWakeLockSafe();
            stopForeground(true);
            stopSelf();
            return START_NOT_STICKY;
        }

        try {
            Intent notificationIntent = new Intent(this, MainActivity.class);
            notificationIntent.setFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK |
                Intent.FLAG_ACTIVITY_SINGLE_TOP |
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT |
                0x00800000 |
                0x00200000
            );

            int pendingFlags = (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                ? (PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT)
                : PendingIntent.FLAG_UPDATE_CURRENT;

            PendingIntent pendingIntent = PendingIntent.getActivity(
                this,
                0,
                notificationIntent,
                pendingFlags
            );

            Notification notification = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("SYSTÈMES : ZONE DE PÉNALITÉ")
                .setContentText("Le Cerbère patrouille : bureau libre, applis tierces bloquées.")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentIntent(pendingIntent)
                .setFullScreenIntent(pendingIntent, true)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .build();

            startForeground(NOTIFICATION_ID, notification);
        } catch (Exception e) {
            e.printStackTrace();
        }

        PowerManager powerManager = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (powerManager != null && wakeLock == null) {
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "ShadowBurn::CoreWatcherWakeLock"
            );
            wakeLock.acquire(60L * 60L * 1000L);
        }

        if ("ACTION_FORCE_BRING_TO_FRONT".equals(actionVal)) {
            if (System.currentTimeMillis() >= emergencyGraceUntil) {
                String pkg = getForegroundPackageName();
                String homePkg = getHomeLauncherPackageName();
                if (!pkg.isEmpty()
                    && !pkg.equals(getPackageName())
                    && !pkg.equals(homePkg)
                    && !isPackageWhitelisted(pkg)) {
                    bringAppToFront();
                }
            }
        }

        scheduleAlarmResurrection(false);
        startWatchdogLoop();

        return START_STICKY;
    }

    private void releaseWakeLockSafe() {
        try {
            if (wakeLock != null && wakeLock.isHeld()) {
                wakeLock.release();
            }
        } catch (Exception ignored) {}
        wakeLock = null;
    }

    private void scheduleAlarmResurrection(boolean forceImmediate) {
        if (!isPenaltyActiveInPrefs(this)) {
            cancelAlarmResurrection();
            return;
        }
        long now = System.currentTimeMillis();
        if (!forceImmediate && (now - lastAlarmScheduledMs) < ALARM_MIN_INTERVAL_MS) {
            return;
        }
        lastAlarmScheduledMs = now;

        try {
            Intent alarmIntent = new Intent(getApplicationContext(), BootReceiver.class);
            alarmIntent.setAction("ACTION_CERBERUS_RESURRECT");
            int flags = (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                ? (PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT)
                : PendingIntent.FLAG_UPDATE_CURRENT;

            PendingIntent pi = PendingIntent.getBroadcast(
                getApplicationContext(),
                RESURRECT_REQUEST_CODE,
                alarmIntent,
                flags
            );
            AlarmManager am = (AlarmManager) getSystemService(Context.ALARM_SERVICE);

            if (am != null) {
                long triggerTime = now + (forceImmediate ? 2000L : ALARM_DELAY_MS);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerTime, pi);
                } else {
                    am.setExact(AlarmManager.RTC_WAKEUP, triggerTime, pi);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void cancelAlarmResurrection() {
        try {
            Intent alarmIntent = new Intent(getApplicationContext(), BootReceiver.class);
            alarmIntent.setAction("ACTION_CERBERUS_RESURRECT");
            int flags = (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                ? (PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT)
                : PendingIntent.FLAG_UPDATE_CURRENT;

            PendingIntent pi = PendingIntent.getBroadcast(
                getApplicationContext(),
                RESURRECT_REQUEST_CODE,
                alarmIntent,
                flags
            );
            AlarmManager am = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
            if (am != null) {
                am.cancel(pi);
            }
        } catch (Exception ignored) {}
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        super.onTaskRemoved(rootIntent);
        try {
            if (isPenaltyActiveInPrefs(this)) {
                scheduleAlarmResurrection(true);
                Intent restartServiceIntent = new Intent(getApplicationContext(), CoreWatcherService.class);
                restartServiceIntent.setAction("ACTION_FORCE_BRING_TO_FRONT");
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    getApplicationContext().startForegroundService(restartServiceIntent);
                } else {
                    getApplicationContext().startService(restartServiceIntent);
                }
            } else {
                cancelAlarmResurrection();
                releaseWakeLockSafe();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void bringAppToFront() {
        try {
            Intent launchIntent = new Intent(this, MainActivity.class);
            int showWhenLockedFlag = 0x00800000;
            int turnScreenOnFlag = 0x00200000;
            launchIntent.setFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK |
                Intent.FLAG_ACTIVITY_SINGLE_TOP |
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT |
                showWhenLockedFlag |
                turnScreenOnFlag |
                Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            );
            startActivity(launchIntent);
        } catch (Exception ignored) {}
    }

    private void startWatchdogLoop() {
        if (isRunning && patrolThread != null && patrolThread.isAlive()) {
            return;
        }
        isRunning = true;

        final String homeLauncherPkg = getHomeLauncherPackageName();
        final String selfPkg = getPackageName();

        patrolThread = new Thread(() -> {
            while (isRunning) {
                try {
                    Thread.sleep(PATROL_INTERVAL_MS);

                    if (!isPenaltyActiveInPrefs(CoreWatcherService.this)) {
                        cancelAlarmResurrection();
                        releaseWakeLockSafe();
                        stopForeground(true);
                        stopSelf();
                        break;
                    }

                    if (System.currentTimeMillis() < emergencyGraceUntil) {
                        continue;
                    }

                    scheduleAlarmResurrection(false);

                    String currentPkg = getForegroundPackageName();
                    if (currentPkg.isEmpty()) {
                        currentPkg = lastKnownForegroundPkg;
                    }

                    if (currentPkg.isEmpty()
                        || currentPkg.equals(selfPkg)
                        || currentPkg.equals(homeLauncherPkg)
                        || isPackageWhitelisted(currentPkg)) {
                        continue;
                    }

                    bringAppToFront();
                } catch (InterruptedException e) {
                    break;
                } catch (Exception ignored) {}
            }
        }, "CerberusEventWatchdog");
        patrolThread.start();
    }

    private boolean isPackageWhitelisted(String pkg) {
        if (pkg == null || pkg.isEmpty()) return false;
        String lower = pkg.toLowerCase();
        for (String allowed : EMERGENCY_WHITELIST) {
            if (lower.contains(allowed)) {
                return true;
            }
        }
        return false;
    }

    private String getForegroundPackageName() {
        try {
            UsageStatsManager usm = (UsageStatsManager) getSystemService(Context.USAGE_STATS_SERVICE);
            if (usm == null) return "";

            long now = System.currentTimeMillis();
            UsageEvents events = usm.queryEvents(now - USAGE_LOOKBACK_MS, now);
            if (events == null) return "";

            UsageEvents.Event event = new UsageEvents.Event();
            String latestPkg = "";

            while (events.hasNextEvent()) {
                events.getNextEvent(event);
                int type = event.getEventType();
                if (type == UsageEvents.Event.ACTIVITY_RESUMED
                    || type == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    String pkg = event.getPackageName();
                    if (pkg != null && !pkg.isEmpty()) {
                        latestPkg = pkg;
                        lastKnownForegroundPkg = pkg;
                    }
                }
            }
            return latestPkg;
        } catch (Exception e) {
            return "";
        }
    }

    @Override
    public void onDestroy() {
        isRunning = false;
        if (patrolThread != null) {
            patrolThread.interrupt();
            patrolThread = null;
        }
        try {
            if (isPenaltyActiveInPrefs(this)) {
                scheduleAlarmResurrection(true);
                Intent restartServiceIntent = new Intent(getApplicationContext(), CoreWatcherService.class);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    getApplicationContext().startForegroundService(restartServiceIntent);
                } else {
                    getApplicationContext().startService(restartServiceIntent);
                }
            } else {
                cancelAlarmResurrection();
                releaseWakeLockSafe();
            }
        } catch (Exception ignored) {}
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel serviceChannel = new NotificationChannel(
                CHANNEL_ID,
                "CoreWatcher System Watchdog",
                NotificationManager.IMPORTANCE_HIGH
            );
            serviceChannel.setDescription("Canal de sécurité intransigeant du Système");
            serviceChannel.setShowBadge(false);

            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.createNotificationChannel(serviceChannel);
            }
        }
    }
}
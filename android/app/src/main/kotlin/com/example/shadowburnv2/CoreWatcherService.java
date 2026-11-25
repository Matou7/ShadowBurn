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
    private PowerManager.WakeLock wakeLock = null;
    private volatile boolean isRunning = false;
    private Thread patrolThread = null;
    private long lastAlarmScheduledMs = 0L;

    public static volatile long emergencyGraceUntil = 0L;

    private String getHomeLauncherPackageName() {
        try {
            Intent intent = new Intent(Intent.ACTION_MAIN);
            intent.addCategory(Intent.CATEGORY_HOME);
            ResolveInfo resolveInfo = getPackageManager().resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY);
            if (resolveInfo != null && resolveInfo.activityInfo != null) {
                return resolveInfo.activityInfo.packageName;
            }
        } catch (Exception ignored) {}
        return "";
    }

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
        "messaging"
    );

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String actionVal = (intent != null) ? intent.getAction() : null;

        if ("ACTION_STOP_COREWATCHER".equals(actionVal)) {
            cancelAlarmResurrection();
            stopForeground(true);
            stopSelf();
            return START_NOT_STICKY;
        }

        if ("ACTION_EMERGENCY_GRACE".equals(actionVal)) {
            emergencyGraceUntil = System.currentTimeMillis() + 3000L;
            return START_STICKY;
        }

        if ("ACTION_FORCE_BRING_TO_FRONT".equals(actionVal)) {
            if (System.currentTimeMillis() >= emergencyGraceUntil) {
                bringAppToFront();
            }
            return START_STICKY;
        }

        SharedPreferences prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
        boolean isPenal = prefs.getBoolean("flutter.cerberus_penalty_active", false) || prefs.getBoolean("cerberus_penalty_active", false);

        if (!isPenal) {
            stopForeground(true);
            stopSelf();
            return START_NOT_STICKY;
        }

        try {
            Intent notificationIntent = new Intent(this, MainActivity.class);
            notificationIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK |
                                        Intent.FLAG_ACTIVITY_SINGLE_TOP |
                                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT |
                                        0x00800000 |
                                        0x00200000);

            int pendingFlags = (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                ? (PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT)
                : PendingIntent.FLAG_UPDATE_CURRENT;

            PendingIntent pendingIntent = PendingIntent.getActivity(this, 0, notificationIntent, pendingFlags);

            NotificationCompat.Builder builder = new NotificationCompat.Builder(this, CHANNEL_ID)
                    .setContentTitle("SYSTÈMES : ZONE DE PÉNALITÉ")
                    .setContentText("Le Hardware est verrouillé. Le Cerbère patrouille en temps réel.")
                    .setSmallIcon(android.R.drawable.ic_dialog_alert)
                    .setContentIntent(pendingIntent)
                    .setFullScreenIntent(pendingIntent, true)
                    .setOngoing(true)
                    .setPriority(NotificationCompat.PRIORITY_MAX)
                    .setCategory(NotificationCompat.CATEGORY_SERVICE);

            startForeground(7777, builder.build());
        } catch (Exception e) {
            e.printStackTrace();
        }

        PowerManager powerManager = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (powerManager != null && wakeLock == null) {
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ShadowBurn::CoreWatcherWakeLock");
            wakeLock.acquire(60L * 60L * 1000L);
        }

        scheduleAlarmResurrection(true);
        startWatchdogLoop();

        return START_STICKY;
    }

    private void scheduleAlarmResurrection(boolean forceImmediate) {
        long now = System.currentTimeMillis();
        // Évite de saturer AlarmManager (HyperOS/Android tue les apps qui reprogramment des alarmes en boucle < 5s)
        if (!forceImmediate && (now - lastAlarmScheduledMs) < 5000L) {
            return;
        }
        lastAlarmScheduledMs = now;

        try {
            Intent alarmIntent = new Intent(getApplicationContext(), BootReceiver.class);
            alarmIntent.setAction("ACTION_CERBERUS_RESURRECT");
            int flags = (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                ? (PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT)
                : PendingIntent.FLAG_UPDATE_CURRENT;

            PendingIntent pi = PendingIntent.getBroadcast(getApplicationContext(), 9999, alarmIntent, flags);
            AlarmManager am = (AlarmManager) getSystemService(Context.ALARM_SERVICE);

            if (am != null) {
                long triggerTime = now + (forceImmediate ? 1500L : 5500L);
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

            PendingIntent pi = PendingIntent.getBroadcast(getApplicationContext(), 9999, alarmIntent, flags);
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
            SharedPreferences prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            boolean isPrefPrefixed = prefs.getBoolean("flutter.cerberus_penalty_active", false);
            boolean isPrefRaw = prefs.getBoolean("cerberus_penalty_active", false);

            if (isPrefPrefixed || isPrefRaw) {
                scheduleAlarmResurrection(true);
                bringAppToFront();

                Intent restartServiceIntent = new Intent(getApplicationContext(), CoreWatcherService.class);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    getApplicationContext().startForegroundService(restartServiceIntent);
                } else {
                    getApplicationContext().startService(restartServiceIntent);
                }
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
            launchIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK |
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP |
                                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT |
                                    showWhenLockedFlag |
                                    turnScreenOnFlag |
                                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
            startActivity(launchIntent);
        } catch (Exception ignored) {}
    }

    private void startWatchdogLoop() {
        if (isRunning) return;
        isRunning = true;

        final String homeLauncherPkg = getHomeLauncherPackageName();

        patrolThread = new Thread(() -> {
            while (isRunning) {
                try {
                    // 150ms : réactivité instantanée tout en évitant le throttling CPU/batterie HyperOS
                    Thread.sleep(150);

                    SharedPreferences prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
                    boolean isPenal = prefs.getBoolean("flutter.cerberus_penalty_active", false) || prefs.getBoolean("cerberus_penalty_active", false);

                    if (!isPenal) {
                        cancelAlarmResurrection();
                        stopForeground(true);
                        stopSelf();
                        break;
                    }

                    if (System.currentTimeMillis() < emergencyGraceUntil) {
                        continue;
                    }

                    scheduleAlarmResurrection(false);

                    String currentPkg = getForegroundPackageName();

                    if (currentPkg.equals(getPackageName()) ||
                        currentPkg.equals(homeLauncherPkg) ||
                        isPackageWhitelisted(currentPkg) ||
                        currentPkg.isEmpty()) {
                        continue;
                    }

                    bringAppToFront();

                } catch (InterruptedException e) {
                    break;
                } catch (Exception ignored) {}
            }
        });
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

            long time = System.currentTimeMillis();
            UsageEvents events = usm.queryEvents(time - 1500L, time);
            UsageEvents.Event event = new UsageEvents.Event();
            String lastPackage = "";

            while (events.hasNextEvent()) {
                events.getNextEvent(event);
                if (event.getEventType() == UsageEvents.Event.ACTIVITY_RESUMED) {
                    lastPackage = event.getPackageName();
                }
            }
            return lastPackage;
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
            SharedPreferences prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            boolean isPenal = prefs.getBoolean("flutter.cerberus_penalty_active", false) || prefs.getBoolean("cerberus_penalty_active", false);

            if (isPenal) {
                scheduleAlarmResurrection(true);
                Intent restartServiceIntent = new Intent(getApplicationContext(), CoreWatcherService.class);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    getApplicationContext().startForegroundService(restartServiceIntent);
                } else {
                    getApplicationContext().startService(restartServiceIntent);
                }
            } else {
                if (wakeLock != null && wakeLock.isHeld()) {
                    wakeLock.release();
                }
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
const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");

admin.initializeApp();

const db = admin.firestore();

const ROOM_COLLECTIONS = ["current_raids", "current_raid"];
const DEFAULT_IDLE_MS = 2 * 60 * 1000;
const VICTORY_IDLE_MS = 3 * 60 * 1000;
const TERMINAL_IDLE_MS = 60 * 1000;

function timestampToMillis(value) {
  if (value && typeof value.toMillis === "function") {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return null;
}

function roomLastActivityMillis(data) {
  // Gameplay/admin activity takes precedence over the TV heartbeat.
  // An unattended TV tab must not keep an empty room alive indefinitely.
  return (
    timestampToMillis(data.last_activity_at) ??
    timestampToMillis(data.arena_last_seen) ??
    timestampToMillis(data.updateTime) ??
    timestampToMillis(data.updated_at)
  );
}

function inactivityLimitForStatus(status) {
  if (status === "victory") return VICTORY_IDLE_MS;
  if (
    status === "failed" ||
    status === "finished" ||
    status === "abandoned" ||
    status === "closed"
  ) {
    return TERMINAL_IDLE_MS;
  }
  return DEFAULT_IDLE_MS;
}

exports.cleanupInactiveArenaRooms = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "Europe/Paris",
    region: "europe-west1",
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async () => {
    const now = Date.now();
    const oldestCandidate = admin.firestore.Timestamp.fromMillis(
      now - TERMINAL_IDLE_MS
    );
    let deletedCount = 0;

    for (const collectionName of ROOM_COLLECTIONS) {
      const collection = db.collection(collectionName);

      // Query only potentially expired documents. This avoids reading every
      // room every minute and protects the project's Firestore read quota.
      const [activitySnapshot, heartbeatSnapshot] = await Promise.all([
        collection
          .where("last_activity_at", "<=", oldestCandidate)
          .get(),
        collection
          .where("arena_last_seen", "<=", oldestCandidate)
          .get(),
      ]);

      const candidates = new Map();
      for (const document of activitySnapshot.docs) {
        candidates.set(document.ref.path, document);
      }
      for (const document of heartbeatSnapshot.docs) {
        candidates.set(document.ref.path, document);
      }

      let batch = db.batch();
      let batchSize = 0;

      for (const document of candidates.values()) {
        const data = document.data();
        const lastActivity = roomLastActivityMillis(data);

        // Never delete a document whose age cannot be established safely.
        if (lastActivity === null) continue;

        const status = String(data.status || "waiting");
        const idleLimit = inactivityLimitForStatus(status);
        if (now - lastActivity < idleLimit) continue;

        batch.delete(document.ref);
        batchSize++;
        deletedCount++;

        // Firestore batches are limited to 500 writes.
        if (batchSize === 450) {
          await batch.commit();
          batch = db.batch();
          batchSize = 0;
        }
      }

      if (batchSize > 0) {
        await batch.commit();
      }
    }

    if (deletedCount > 0) {
      logger.info("Inactive ShadowBurn rooms deleted", { deletedCount });
    }
  }
);

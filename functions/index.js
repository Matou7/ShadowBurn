const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { randomBytes, createHash, timingSafeEqual } = require('node:crypto');
const {
  isValidRoomId,
  cleanText,
  isAllowedModeCategory,
  resolveComboDamage,
} = require('./policy');

admin.initializeApp();
const db = admin.firestore();
const REGION = 'europe-west1';
const MAX_PLAYERS = 10;
const ROOM_ALIVE_MS = 60000;
const TERMINAL_STATUSES = ['victory', 'failed', 'finished', 'abandoned', 'closed'];
const ACTIVE_STATUSES = ['waiting', 'active'];

function callable(handler) {
  return onCall({ region: REGION, maxInstances: 10 }, async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError('unauthenticated', 'Authentification Firebase requise.');
    }
    return handler(request);
  });
}

function roomIdFrom(data) {
  const roomId = data && data.roomId;
  if (!isValidRoomId(roomId)) {
    throw new HttpsError('invalid-argument', 'Identifiant de salle invalide.');
  }
  return roomId;
}

function secretHash(value) {
  return createHash('sha256').update(String(value)).digest('hex');
}

function secretMatches(value, expectedHash) {
  if (typeof value !== 'string' || !expectedHash) return false;
  const actual = Buffer.from(secretHash(value), 'hex');
  const expected = Buffer.from(String(expectedHash), 'hex');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function makeSecret(bytes = 24) {
  return randomBytes(bytes).toString('base64url');
}

function privateRoom(roomId) {
  return db.collection('arena_private').doc(roomId);
}

function publicRoom(roomId) {
  return db.collection('current_raids').doc(roomId);
}

function requireValidDeviceId(value) {
  const deviceId = cleanText(value, 128);
  if (deviceId.length < 16) {
    throw new HttpsError('invalid-argument', 'Identifiant matériel invalide.');
  }
  return deviceId;
}

exports.claimArenaRoom = callable(async (request) => {
  const roomId = roomIdFrom(request.data);
  const now = Date.now();
  const targetEndTimeMs = Number(request.data.targetEndTimeMs);
  const targetEndTime = Number.isFinite(targetEndTimeMs) &&
      targetEndTimeMs > now && targetEndTimeMs <= now + 24 * 60 * 60 * 1000
    ? targetEndTimeMs
    : now + 8 * 60 * 60 * 1000;
  const adminKey = makeSecret(24);
  const joinToken = makeSecret(24);
  const instanceToken = makeSecret(24);
  const roomRef = publicRoom(roomId);
  const privateRef = privateRoom(roomId);

  await db.runTransaction(async (tx) => {
    const roomSnap = await tx.get(roomRef);
    const privateSnap = await tx.get(privateRef);
    if (roomSnap.exists) {
      const room = roomSnap.data() || {};
      const lastSeen = room.arena_last_seen && typeof room.arena_last_seen.toMillis === 'function'
        ? room.arena_last_seen.toMillis()
        : 0;
      const terminal = TERMINAL_STATUSES.includes(String(room.status || ''));
      if (!terminal && lastSeen > now - ROOM_ALIVE_MS) {
        throw new HttpsError('already-exists', 'Cette salle possède déjà une TV active.');
      }
    }
    tx.set(roomRef, {
      roomId,
      boss_name: 'MONARQUE DU FEU',
      status: 'waiting',
      preset_label: 'RAID STANDARD (5 000 PV)',
      current_hp: 5000,
      max_hp: 5000,
      hunters: [],
      logs: [],
      target_end_time: targetEndTime,
      arena_last_seen: admin.firestore.Timestamp.fromMillis(now),
      updateTime: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.set(privateRef, {
      owner_uid: request.auth.uid,
      admin_key_hash: secretHash(adminKey),
      join_token_hash: secretHash(joinToken),
      instance_token_hash: secretHash(instanceToken),
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { roomId, adminKey, joinToken, instanceToken };
});

exports.heartbeatArenaRoom = callable(async (request) => {
  const roomId = roomIdFrom(request.data);
  const instanceToken = request.data.instanceToken;
  const roomRef = publicRoom(roomId);
  const privateRef = privateRoom(roomId);
  await db.runTransaction(async (tx) => {
    const [roomSnap, privateSnap] = await Promise.all([tx.get(roomRef), tx.get(privateRef)]);
    if (!roomSnap.exists || !privateSnap.exists ||
        !secretMatches(instanceToken, (privateSnap.data() || {}).instance_token_hash)) {
      throw new HttpsError('permission-denied', 'Session TV invalide.');
    }
    tx.update(roomRef, {
      arena_last_seen: admin.firestore.FieldValue.serverTimestamp(),
      updateTime: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return { ok: true };
});

exports.closeArenaRoom = callable(async (request) => {
  const roomId = roomIdFrom(request.data);
  const roomRef = publicRoom(roomId);
  const privateRef = privateRoom(roomId);
  await db.runTransaction(async (tx) => {
    const [roomSnap, privateSnap] = await Promise.all([tx.get(roomRef), tx.get(privateRef)]);
    if (!roomSnap.exists || !privateSnap.exists ||
        !secretMatches(request.data.instanceToken, (privateSnap.data() || {}).instance_token_hash)) {
      throw new HttpsError('permission-denied', 'Session TV invalide.');
    }
    tx.update(roomRef, {
      status: 'closed',
      arena_last_seen: admin.firestore.Timestamp.fromMillis(0),
      updateTime: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.delete(privateRef);
  });
  return { ok: true };
});

exports.setArenaTvStatus = callable(async (request) => {
  const roomId = roomIdFrom(request.data);
  const status = request.data.status;
  if (!['failed', 'victory'].includes(status)) {
    throw new HttpsError('invalid-argument', 'Transition TV non autorisée.');
  }
  const roomRef = publicRoom(roomId);
  const privateRef = privateRoom(roomId);
  await db.runTransaction(async (tx) => {
    const [roomSnap, privateSnap] = await Promise.all([tx.get(roomRef), tx.get(privateRef)]);
    if (!roomSnap.exists || !privateSnap.exists ||
        !secretMatches(request.data.instanceToken, (privateSnap.data() || {}).instance_token_hash)) {
      throw new HttpsError('permission-denied', 'Session TV invalide.');
    }
    const update = {
      status,
      updateTime: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (status === 'victory') update.current_hp = 0;
    tx.update(roomRef, update);
  });
  return { ok: true };
});

exports.pruneArenaHunters = callable(async (request) => {
  const roomId = roomIdFrom(request.data);
  const roomRef = publicRoom(roomId);
  const privateRef = privateRoom(roomId);
  const now = Date.now();
  await db.runTransaction(async (tx) => {
    const [roomSnap, privateSnap] = await Promise.all([tx.get(roomRef), tx.get(privateRef)]);
    if (!roomSnap.exists || !privateSnap.exists ||
        !secretMatches(request.data.instanceToken, (privateSnap.data() || {}).instance_token_hash)) {
      throw new HttpsError('permission-denied', 'Session TV invalide.');
    }
    const data = roomSnap.data() || {};
    const hunters = Array.isArray(data.hunters) ? data.hunters : [];
    const next = [];
    for (const hunter of hunters) {
      const lastSeen = Number(hunter && hunter.last_seen) || now;
      if (now - lastSeen <= 90000 || hunter.is_connected === false) {
        next.push(hunter);
      } else if ((Number(hunter.total_damage) || 0) > 0) {
        next.push({ ...hunter, is_connected: false });
      }
    }
    if (next.length !== hunters.length ||
        next.some((h, i) => h !== hunters[i])) {
      tx.update(roomRef, {
        hunters: next,
        updateTime: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });
  return { ok: true };
});

exports.validateArenaJoinToken = callable(async (request) => {
  const roomId = roomIdFrom(request.data);
  const token = request.data.token;
  const [roomSnap, privateSnap] = await Promise.all([
    publicRoom(roomId).get(),
    privateRoom(roomId).get(),
  ]);
  if (!roomSnap.exists || !privateSnap.exists) return { valid: false };
  const privateData = privateSnap.data() || {};
  const valid = secretMatches(token, privateData.join_token_hash);
  const status = String((roomSnap.data() || {}).status || 'closed');
  return { valid: valid && ACTIVE_STATUSES.includes(status), status };
});

exports.joinArenaRoom = callable(async (request) => {
  const roomId = roomIdFrom(request.data);
  const token = request.data.token;
  const name = cleanText(request.data.name, 24);
  const modeId = cleanText(request.data.modeId, 32);
  const modeLabel = cleanText(request.data.modeLabel, 80);
  if (!name || !modeId || !modeLabel) {
    throw new HttpsError('invalid-argument', 'Nom ou mode d’entraînement invalide.');
  }
  const uid = request.auth.uid;
  const roomRef = publicRoom(roomId);
  const privateRef = privateRoom(roomId);
  const sessionRef = privateRef.collection('hunters').doc(uid);
  const now = Date.now();

  await db.runTransaction(async (tx) => {
    const [roomSnap, privateSnap, sessionSnap] = await Promise.all([
      tx.get(roomRef), tx.get(privateRef), tx.get(sessionRef),
    ]);
    if (!roomSnap.exists || !privateSnap.exists ||
        !secretMatches(token, (privateSnap.data() || {}).join_token_hash)) {
      throw new HttpsError('permission-denied', 'Jeton du portail invalide ou expiré.');
    }
    const room = roomSnap.data() || {};
    if (!ACTIVE_STATUSES.includes(String(room.status || ''))) {
      throw new HttpsError('failed-precondition', 'Ce raid n’accepte plus de chasseurs.');
    }
    const parisHour = Number(new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Europe/Paris',
      hour: '2-digit',
      hourCycle: 'h23',
    }).format(new Date()));
    if (parisHour < 6 || parisHour >= 23) {
      throw new HttpsError('failed-precondition', 'Les portails sont fermés entre 23h et 6h.');
    }
    const hunters = Array.isArray(room.hunters) ? [...room.hunters] : [];
    const index = hunters.findIndex((h) => h && h.id === uid);
    const connected = hunters.filter((h) => h && h.is_connected !== false).length;
    if (index < 0 && connected >= MAX_PLAYERS) {
      throw new HttpsError('resource-exhausted', 'Cette salle est complète : 10 chasseurs maximum.');
    }
    const existing = index >= 0 ? hunters[index] : {};
    const entry = {
      id: uid,
      name,
      rank: 'Rang E',
      mode_id: modeId,
      mode_label: modeLabel,
      combo_step: 0,
      total_damage: Number(existing.total_damage) || 0,
      squat_reps: Number(existing.squat_reps) || 0,
      pushup_reps: Number(existing.pushup_reps) || 0,
      abs_reps: Number(existing.abs_reps) || 0,
      joined_at: Number(existing.joined_at) || now,
      last_seen: now,
      is_connected: true,
    };
    if (index >= 0) hunters[index] = entry;
    else hunters.push(entry);
    tx.update(roomRef, { hunters, updateTime: admin.firestore.FieldValue.serverTimestamp() });
    tx.set(sessionRef, {
      name,
      mode_id: modeId,
      last_strike_ms: Number(sessionSnap.exists ? (sessionSnap.data() || {}).last_strike_ms : 0) || 0,
      combo_step: 0,
      combo_expires_at: 0,
      joined_at: now,
    }, { merge: true });
  });
  return { hunterId: uid };
});

exports.leaveArenaRoom = callable(async (request) => {
  const roomId = roomIdFrom(request.data);
  const uid = request.auth.uid;
  const roomRef = publicRoom(roomId);
  const sessionRef = privateRoom(roomId).collection('hunters').doc(uid);
  await db.runTransaction(async (tx) => {
    const [roomSnap, sessionSnap] = await Promise.all([tx.get(roomRef), tx.get(sessionRef)]);
    if (!roomSnap.exists) return;
    const data = roomSnap.data() || {};
    const hunters = Array.isArray(data.hunters) ? [...data.hunters] : [];
    const index = hunters.findIndex((h) => h && h.id === uid);
    if (index >= 0) {
      const hunter = { ...hunters[index] };
      if ((Number(hunter.total_damage) || 0) === 0) hunters.splice(index, 1);
      else {
        hunter.is_connected = false;
        hunter.last_seen = Date.now();
        hunters[index] = hunter;
      }
      tx.update(roomRef, { hunters, updateTime: admin.firestore.FieldValue.serverTimestamp() });
    }
    if (sessionSnap.exists) tx.delete(sessionRef);
  });
  return { ok: true };
});

exports.submitArenaDamage = callable(async (request) => {
  const roomId = roomIdFrom(request.data);
  const uid = request.auth.uid;
  const batchId = cleanText(request.data.batchId, 100);
  if (!batchId || batchId.length < 12) {
    throw new HttpsError('invalid-argument', 'Identifiant de lot invalide.');
  }
  const strikes = request.data.strikes;
  if (!Array.isArray(strikes) || strikes.length < 1 || strikes.length > 30) {
    throw new HttpsError('invalid-argument', 'Lot de frappes invalide.');
  }
  const roomRef = publicRoom(roomId);
  const sessionRef = privateRoom(roomId).collection('hunters').doc(uid);
  const now = Date.now();

  await db.runTransaction(async (tx) => {
    const [roomSnap, sessionSnap] = await Promise.all([tx.get(roomRef), tx.get(sessionRef)]);
    if (!roomSnap.exists || !sessionSnap.exists) {
      throw new HttpsError('permission-denied', 'Chasseur non inscrit dans cette salle.');
    }
    const room = roomSnap.data() || {};
    const session = sessionSnap.data() || {};
    const processedBatches = Array.isArray(session.processed_batches)
      ? session.processed_batches
      : [];
    if (processedBatches.includes(batchId)) {
      return;
    }
    if (room.status !== 'active') {
      throw new HttpsError('failed-precondition', 'Le raid n’est pas actif.');
    }
    let previous = Number(session.last_strike_ms) || 0;
    let comboStep = Number(session.combo_step) || 0;
    let comboExpiry = Number(session.combo_expires_at) || 0;
    const computed = [];
    let totalDamage = 0;
    let squatReps = 0, pushupReps = 0, absReps = 0;

    for (const strike of strikes) {
      const category = cleanText(strike && strike.category, 16);
      const reps = Number(strike && strike.reps);
      const timestamp = Number(strike && strike.timestamp);
      if (!['squat', 'pushup', 'abs'].includes(category) || reps !== 5 ||
          !Number.isFinite(timestamp) || timestamp < now - 65000 || timestamp > now + 5000 ||
          (previous > 0 && timestamp - previous < 2000) ||
          !isAllowedModeCategory(session.mode_id, category)) {
        throw new HttpsError('failed-precondition', 'Cadence, catégorie ou répétitions invalides.');
      }
      const resolved = resolveComboDamage(comboStep, comboExpiry, timestamp);
      comboStep = resolved.step;
      comboExpiry = resolved.expiresAt;
      previous = timestamp;
      totalDamage += resolved.damage;
      if (category === 'squat') squatReps += reps;
      if (category === 'pushup') pushupReps += reps;
      if (category === 'abs') absReps += reps;
      computed.push({
        id: uid,
        name: cleanText(session.name, 24) || 'Chasseur',
        rank: 'Rang E',
        category,
        reps,
        action: cleanText(strike.action, 48),
        damage: resolved.damage,
        glowing: resolved.damage > 25,
        timestamp,
      });
    }
    if (totalDamage > 6000 || previous > now + 5000) {
      throw new HttpsError('invalid-argument', 'Lot de dégâts hors limites.');
    }

    const hunters = Array.isArray(room.hunters) ? [...room.hunters] : [];
    const index = hunters.findIndex((h) => h && h.id === uid && h.is_connected !== false);
    if (index < 0) throw new HttpsError('permission-denied', 'Session de chasseur inactive.');
    const hunter = { ...hunters[index] };
    hunter.total_damage = (Number(hunter.total_damage) || 0) + totalDamage;
    hunter.squat_reps = (Number(hunter.squat_reps) || 0) + squatReps;
    hunter.pushup_reps = (Number(hunter.pushup_reps) || 0) + pushupReps;
    hunter.abs_reps = (Number(hunter.abs_reps) || 0) + absReps;
    hunter.last_seen = now;
    hunters[index] = hunter;

    const hp = Math.max(0, (Number(room.current_hp) || 5000) - totalDamage);
    const logs = [...computed, ...(Array.isArray(room.logs) ? room.logs : [])].slice(0, 30);
    tx.update(roomRef, {
      current_hp: hp,
      logs,
      hunters,
      ...(hp <= 0 ? { status: 'victory' } : {}),
      updateTime: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(sessionRef, {
      last_strike_ms: previous,
      combo_step: comboStep,
      combo_expires_at: comboExpiry,
      processed_batches: [...processedBatches, batchId].slice(-50),
    });
  });
  return { ok: true };
});

exports.verifyArenaAdminKey = callable(async (request) => {
  const roomId = roomIdFrom(request.data);
  const privateSnap = await privateRoom(roomId).get();
  if (!privateSnap.exists ||
      !secretMatches(request.data.adminKey, (privateSnap.data() || {}).admin_key_hash)) {
    return { valid: false };
  }
  return { valid: true };
});

exports.adminArenaAction = callable(async (request) => {
  const roomId = roomIdFrom(request.data);
  const action = cleanText(request.data.action, 32);
  const roomRef = publicRoom(roomId);
  const privateRef = privateRoom(roomId);
  const now = Date.now();
  await db.runTransaction(async (tx) => {
    const [roomSnap, privateSnap] = await Promise.all([tx.get(roomRef), tx.get(privateRef)]);
    if (!roomSnap.exists || !privateSnap.exists ||
        !secretMatches(request.data.adminKey, (privateSnap.data() || {}).admin_key_hash)) {
      throw new HttpsError('permission-denied', 'Clé Monarque invalide.');
    }
    const room = roomSnap.data() || {};
    const hunters = Array.isArray(room.hunters) ? room.hunters.map((h) => ({ ...h })) : [];
    const resetHunters = () => hunters.map((h) => ({
      ...h, total_damage: 0, squat_reps: 0, pushup_reps: 0, abs_reps: 0, combo_step: 0, last_seen: now,
    }));
    const updates = { updateTime: admin.firestore.FieldValue.serverTimestamp() };
    switch (action) {
      case 'applyPreset':
      case 'resetBoss':
        Object.assign(updates, {
          max_hp: 5000, current_hp: 5000,
          boss_name: 'RAID STANDARD (5 000 PV)',
          preset_label: 'RAID STANDARD (5 000 PV)',
          status: action === 'resetBoss' ? 'active' : room.status,
          logs: [], hunters: resetHunters(),
        });
        break;
      case 'strikeBoss': {
        const damage = Number(request.data.damage);
        if (!Number.isInteger(damage) || damage < 1 || damage > 5000) {
          throw new HttpsError('invalid-argument', 'Dégâts du Maître invalides.');
        }
        const hp = Math.max(0, (Number(room.current_hp) || 5000) - damage);
        Object.assign(updates, { current_hp: hp, last_strike_at: admin.firestore.FieldValue.serverTimestamp() });
        if (hp === 0) updates.status = 'victory';
        break;
      }
      case 'setRaidStatus': {
        const status = cleanText(request.data.status, 20);
        if (!['waiting', 'active', 'failed', 'finished', 'abandoned', 'closed'].includes(status)) {
          throw new HttpsError('invalid-argument', 'Statut de raid invalide.');
        }
        updates.status = status;
        if (status === 'waiting') Object.assign(updates, { current_hp: 5000, max_hp: 5000, logs: [] });
        break;
      }
      case 'extendRaidMinutes':
      case 'reduceRaidMinutes': {
        const minutes = Number(request.data.minutes);
        if (!Number.isInteger(minutes) || minutes < 1 || minutes > 120) {
          throw new HttpsError('invalid-argument', 'Durée invalide.');
        }
        const base = Math.max(Number(room.target_end_time) || now, now);
        const delta = minutes * 60000 * (action === 'extendRaidMinutes' ? 1 : -1);
        updates.target_end_time = Math.max(now, Math.min(now + 24 * 60 * 60 * 1000, base + delta));
        break;
      }
      case 'resetToMidnight': {
        const target = Number(request.data.targetEndTimeMs);
        if (!Number.isFinite(target) || target < now || target > now + 24 * 60 * 60 * 1000) {
          throw new HttpsError('invalid-argument', 'Heure de fin invalide.');
        }
        Object.assign(updates, { target_end_time: target, status: 'active' });
        break;
      }
      case 'expireRaidNow':
        Object.assign(updates, { target_end_time: now - 1000, status: 'failed' });
        break;
      default:
        throw new HttpsError('invalid-argument', 'Action administrateur inconnue.');
    }
    tx.update(roomRef, updates);
  });
  return { ok: true };
});

exports.activateProLicense = callable(async (request) => {
  const key = cleanText(request.data.key, 128).toUpperCase();
  const deviceId = requireValidDeviceId(request.data.deviceId);
  if (!key) throw new HttpsError('invalid-argument', 'Clé Pro manquante.');
  let docRef = db.collection('pro_licenses').doc(key);
  let snap = await docRef.get();
  if (!snap.exists) {
    const query = await db.collection('pro_licenses').where('key', '==', key).limit(1).get();
    if (query.empty) throw new HttpsError('not-found', 'Licence Pro introuvable.');
    docRef = query.docs[0].ref;
    snap = query.docs[0];
  }
  let resultKey = docRef.id;
  await db.runTransaction(async (tx) => {
    const latest = await tx.get(docRef);
    if (!latest.exists) throw new HttpsError('not-found', 'Licence Pro introuvable.');
    const data = latest.data() || {};
    const bound = cleanText(data.used_by, 128);
    if (data.used === true && bound !== deviceId) {
      throw new HttpsError('already-exists', 'Cette licence est déjà liée à un autre appareil.');
    }
    tx.update(docRef, {
      used: true,
      used_by: deviceId,
      used_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    resultKey = cleanText(data.key, 128).toUpperCase() || docRef.id;
  });
  return { ok: true, key: resultKey };
});


exports.validateProLicense = callable(async (request) => {
  const key = cleanText(request.data.key, 128).toUpperCase();
  const deviceId = requireValidDeviceId(request.data.deviceId);
  if (!key) return { valid: false };
  let snap = await db.collection('pro_licenses').doc(key).get();
  if (!snap.exists) {
    const query = await db.collection('pro_licenses').where('key', '==', key).limit(1).get();
    if (query.empty) return { valid: false };
    snap = query.docs[0];
  }
  const data = snap.data() || {};
  return {
    valid: data.used === true && cleanText(data.used_by, 128) === deviceId,
  };
});

exports.restoreProLicense = callable(async (request) => {
  const email = cleanText(request.data.email, 254).toLowerCase();
  const deviceId = requireValidDeviceId(request.data.deviceId);
  const authEmail = cleanText(request.auth.token.email, 254).toLowerCase();
  if (request.auth.token.email_verified !== true || !email || email !== authEmail) {
    throw new HttpsError('permission-denied', 'Compte Firebase vérifié requis.');
  }
  const query = await db.collection('pro_licenses').where('email', '==', email).limit(1).get();
  if (query.empty) throw new HttpsError('not-found', 'Aucune licence liée à ce compte.');
  const docRef = query.docs[0].ref;
  let resultKey = docRef.id;
  await db.runTransaction(async (tx) => {
    const latest = await tx.get(docRef);
    const data = latest.data() || {};
    const bound = cleanText(data.used_by, 128);
    if (data.used === true && bound !== deviceId) {
      throw new HttpsError('already-exists', 'Licence déjà liée à un autre appareil.');
    }
    tx.update(docRef, {
      used: true,
      used_by: deviceId,
      used_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    resultKey = cleanText(data.key, 128).toUpperCase() || docRef.id;
  });
  return { ok: true, key: resultKey };
});

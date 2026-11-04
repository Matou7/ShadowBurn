const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  setDoc,
  collection,
  getDocs,
} = require('firebase/firestore');

let testEnv;

before(async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
  const [hostname, portText] = host.split(':');
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-shadowburn-rules',
    firestore: {
      host: hostname,
      port: Number(portText),
      rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
    },
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

test('unauthenticated clients cannot read raid state', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'current_raids/room_1')));
});

test('authenticated Arena clients can read public raid state', async () => {
  const db = testEnv.authenticatedContext('anonymous-hunter').firestore();
  await assertSucceeds(getDoc(doc(db, 'current_raids/room_1')));
  await assertSucceeds(getDocs(collection(db, 'current_raids')));
});

test('clients cannot create, mutate or delete raid state', async () => {
  const db = testEnv.authenticatedContext('anonymous-hunter').firestore();
  const room = doc(db, 'current_raids/room_1');
  await assertFails(setDoc(room, {
    roomId: 'room_1',
    status: 'waiting',
    current_hp: 5000,
  }));
});

test('license and private Arena secrets are never client-readable or writable', async () => {
  const db = testEnv.authenticatedContext('anonymous-hunter').firestore();
  await assertFails(getDoc(doc(db, 'pro_licenses/TEST-KEY')));
  await assertFails(setDoc(doc(db, 'pro_licenses/TEST-KEY'), { used: true }));
  await assertFails(getDoc(doc(db, 'arena_private/room_1')));
  await assertFails(setDoc(doc(db, 'arena_private/room_1'), { admin_key_hash: 'x' }));
});

test('legacy collections remain closed', async () => {
  const db = testEnv.authenticatedContext('anonymous-hunter').firestore();
  await assertFails(getDoc(doc(db, 'current_raid/room_1')));
  await assertFails(getDoc(doc(db, 'arena_tv/room_1')));
});

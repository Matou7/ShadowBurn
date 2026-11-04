const test = require('node:test');
const assert = require('node:assert/strict');
const {
  isValidRoomId,
  cleanText,
  isAllowedModeCategory,
  resolveComboDamage,
} = require('../policy');

test('room identifiers are restricted to room_1..room_100', () => {
  for (const id of ['room_1', 'room_9', 'room_10', 'room_99', 'room_100']) {
    assert.equal(isValidRoomId(id), true, id);
  }
  for (const id of ['', 'room_0', 'room_01', 'room_101', 'room_1x', '../room_1', null]) {
    assert.equal(isValidRoomId(id), false, String(id));
  }
});

test('names are normalized and bounded', () => {
  assert.equal(cleanText('  Mathis\n  ', 24), 'Mathis');
  assert.equal(cleanText('x'.repeat(40), 24).length, 24);
  assert.equal(cleanText(42, 24), '');
});

test('training modes restrict exercise categories', () => {
  assert.equal(isAllowedModeCategory('squats_only', 'squat'), true);
  assert.equal(isAllowedModeCategory('squats_only', 'pushup'), false);
  assert.equal(isAllowedModeCategory('all', 'abs'), true);
  assert.equal(isAllowedModeCategory('unknown', 'abs'), false);
});

test('combo damage is calculated server-side and expires safely', () => {
  assert.deepEqual(resolveComboDamage(0, 0, 1000), { damage: 25, step: 1, expiresAt: 11000 });
  assert.deepEqual(resolveComboDamage(1, 11000, 5000), { damage: 150, step: 2, expiresAt: 15000 });
  assert.deepEqual(resolveComboDamage(2, 15000, 9000), { damage: 200, step: 0, expiresAt: 0 });
  assert.deepEqual(resolveComboDamage(2, 5000, 9000), { damage: 25, step: 1, expiresAt: 19000 });
});

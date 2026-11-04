const ROOM_PATTERN = /^room_(?:[1-9]|[1-9][0-9]|100)$/;
const DAMAGE_BY_COMBO = Object.freeze([25, 150, 200]);

function isValidRoomId(roomId) {
  return typeof roomId === 'string' && ROOM_PATTERN.test(roomId);
}

function cleanText(value, maxLength) {
  if (typeof value !== 'string') return '';
  return value.trim().replace(/[\u0000-\u001f\u007f]/g, '').slice(0, maxLength);
}

function isAllowedModeCategory(modeId, category) {
  const allowed = {
    all: ['squat', 'pushup', 'abs'],
    squats_only: ['squat'],
    pushups_only: ['pushup'],
    abs_only: ['abs'],
    squats_pushups: ['squat', 'pushup'],
    squats_abs: ['squat', 'abs'],
    pushups_abs: ['pushup', 'abs'],
  };
  return Array.isArray(allowed[modeId]) && allowed[modeId].includes(category);
}

function resolveComboDamage(step, expiresAt, timestamp) {
  if (step === 1 && timestamp <= expiresAt) {
    return { damage: 150, step: 2, expiresAt: timestamp + 10000 };
  }
  if (step === 2 && timestamp <= expiresAt) {
    return { damage: 200, step: 0, expiresAt: 0 };
  }
  return { damage: 25, step: 1, expiresAt: timestamp + 10000 };
}

module.exports = {
  isValidRoomId,
  cleanText,
  isAllowedModeCategory,
  resolveComboDamage,
};

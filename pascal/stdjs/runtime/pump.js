let _timer = null;
const _pumps = new Map();

function _startTimer() {
  if (_timer != null) return;
  if (typeof globalThis.setInterval !== "function") return;

  _timer = setInterval(() => {
    const now = Date.now();
    for (const p of _pumps.values()) {
      if (p.count <= 0) continue;
      if (p.intervalMs > 0 && now - p.lastRun < p.intervalMs) continue;
      p.lastRun = now;
      try {
        p.fn();
      } catch (e) {
      }
    }
  }, 10);
}

function _stopTimerIfIdle() {
  if (_timer == null) return;
  if (typeof globalThis.clearInterval !== "function") return;

  for (const p of _pumps.values()) {
    if (p.count > 0) return;
  }

  try {
    clearInterval(_timer);
  } catch (e) {
  }
  _timer = null;
}

export function acquirePump(key, fn, intervalMs) {
  const k = String(key);
  if (typeof fn !== "function") throw new TypeError("acquirePump: fn must be a function");

  const existing = _pumps.get(k);
  if (existing) {
    existing.count++;
    existing.fn = fn;
    if (intervalMs !== void 0) existing.intervalMs = intervalMs | 0;
    _startTimer();
    return;
  }

  _pumps.set(k, {
    key: k,
    fn,
    intervalMs: intervalMs === void 0 ? 0 : (intervalMs | 0),
    count: 1,
    lastRun: 0,
  });
  _startTimer();
}

export function releasePump(key) {
  const k = String(key);
  const existing = _pumps.get(k);
  if (!existing) return;

  existing.count--;
  if (existing.count <= 0) {
    existing.count = 0;
    _pumps.delete(k);
  }
  _stopTimerIfIdle();
}

export function shutdown() {
  if (typeof globalThis.clearInterval === "function" && _timer != null) {
    try {
      clearInterval(_timer);
    } catch (e) {
    }
  }
  _timer = null;
  _pumps.clear();
}

let _timer = null;
let _tickMs = 0;
const _pumps = new Map();

function _getDefaultTickMs() {
  const v = globalThis.__qjspPumpTickMs;
  if (typeof v === "number" && isFinite(v) && v > 0) return v | 0;
  return 50;
}

function _handlePumpError(e, meta) {
  try {
    const hook = globalThis.__qjspOnPumpError;
    if (typeof hook === "function") {
      hook(e, meta);
      return;
    }
  } catch (e2) {
  }

  if ((globalThis.__qjspDebugLevel | 0) > 0 && typeof globalThis.print === "function") {
    try {
      const msg = e && e.stack ? String(e.stack) : String(e);
      globalThis.print("[pump:error]", meta && meta.key ? String(meta.key) : "<unknown>", msg);
    } catch (e2) {
    }
  }
}

function _restartTimerIfNeeded() {
  const nextTick = _getDefaultTickMs();
  if (_timer != null && nextTick === _tickMs) return;
  if (_timer != null && typeof globalThis.clearInterval === "function") {
    try {
      clearInterval(_timer);
    } catch (e) {
    }
    _timer = null;
  }
  _tickMs = nextTick;
  _startTimer();
}

function _startTimer() {
  if (_timer != null) return;
  if (typeof globalThis.setInterval !== "function") return;

  _tickMs = _tickMs > 0 ? _tickMs : _getDefaultTickMs();

  _timer = setInterval(() => {
    const now = Date.now();
    for (const p of _pumps.values()) {
      if (p.count <= 0) continue;
      if (p.intervalMs > 0 && now - p.lastRun < p.intervalMs) continue;
      p.lastRun = now;
      try {
        p.fn();
      } catch (e) {
        _handlePumpError(e, { key: p.key });
      }
    }
  }, _tickMs);
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
    _restartTimerIfNeeded();
    return;
  }

  _pumps.set(k, {
    key: k,
    fn,
    intervalMs: intervalMs === void 0 ? 0 : (intervalMs | 0),
    count: 1,
    lastRun: 0,
  });
  _restartTimerIfNeeded();
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

export function getPumpStats() {
  const tickMs = _timer != null ? _tickMs : 0;
  return {
    tickMs,
    pumpCount: _pumps.size,
    keys: Array.from(_pumps.keys()),
  };
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

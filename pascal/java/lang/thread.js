export class Thread {
  constructor(target, name) {
    this._target = target;
    this._name = name !== void 0 ? String(name) : void 0;
    this._started = false;
    this._alive = false;
    this._interrupted = false;
    this._done = null;
    this._resolveDone = null;
    this._rejectDone = null;
    this._promise = null;
  }

  static sleep(ms) {
    ms = Number(ms);
    if (!Number.isFinite(ms) || ms < 0) throw new RangeError("Thread.sleep: ms must be >= 0");
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  static yield() {
    return Thread.sleep(0);
  }

  static currentThread() {
    return null;
  }

  static interrupted() {
    return false;
  }

  interrupt() {
    this._interrupted = true;
  }

  isInterrupted() {
    return !!this._interrupted;
  }

  isAlive() {
    return !!this._alive;
  }

  getName() {
    return this._name !== void 0 ? this._name : "Thread";
  }

  setName(name) {
    this._name = String(name);
  }

  run() {
    const t = this._target;
    if (t == null) return;
    if (typeof t === "function") return t();
    if (typeof t.run === "function") return t.run();
    throw new TypeError("Thread target must be a function or an object with run()");
  }

  start() {
    if (this._started) throw new Error("IllegalThreadStateException");
    this._started = true;
    this._alive = true;

    this._done = new Promise((resolve, reject) => {
      this._resolveDone = resolve;
      this._rejectDone = reject;
    });

    this._promise = new Promise((resolve, reject) => {
      setTimeout(() => {
        try {
          resolve(this.run());
        } catch (e) {
          reject(e);
        }
      }, 0);
    });

    this._promise.then(
      (v) => {
        this._alive = false;
        if (this._resolveDone) this._resolveDone(v);
      },
      (e) => {
        this._alive = false;
        if (this._rejectDone) this._rejectDone(e);
      },
    );

    return;
  }

  join(millis) {
    const p = this._done || Promise.resolve();
    if (millis === void 0) return p;
    millis = Number(millis);
    if (!Number.isFinite(millis) || millis < 0) throw new RangeError("Thread.join: millis must be >= 0");
    if (millis === 0) return p;
    return Promise.race([p, Thread.sleep(millis)]);
  }
}

export default Thread;

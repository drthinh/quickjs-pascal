export class EventEmitter {
  constructor() {
    this._events = new Map();
    this._maxListeners = 0;
    this._warned = new Set();
  }

  setMaxListeners(n) {
    const v = Number(n);
    this._maxListeners = Number.isFinite(v) && v >= 0 ? v : 0;
    return this;
  }

  getMaxListeners() {
    return this._maxListeners;
  }

  on(eventName, listener) {
    return this.addListener(eventName, listener);
  }

  prependListener(eventName, listener) {
    return this._addListener(eventName, listener, true);
  }

  addListener(eventName, listener) {
    return this._addListener(eventName, listener, false);
  }

  _addListener(eventName, listener, prepend) {
    if (typeof listener !== "function") {
      throw new TypeError("listener must be a function");
    }

    const name = String(eventName);
    let arr = this._events.get(name);
    if (!arr) {
      arr = [];
      this._events.set(name, arr);
    }

    if (prepend) arr.unshift(listener);
    else arr.push(listener);

    if (this._maxListeners > 0 && arr.length > this._maxListeners && !this._warned.has(name)) {
      this._warned.add(name);
      const warn = globalThis.console && typeof globalThis.console.warn === "function" ? globalThis.console.warn : null;
      if (warn) {
        warn(`MaxListenersExceededWarning: Possible EventEmitter memory leak detected. ${arr.length} '${name}' listeners added.`);
      }
    }

    return this;
  }

  once(eventName, listener) {
    if (typeof listener !== "function") {
      throw new TypeError("listener must be a function");
    }

    const name = String(eventName);
    const self = this;

    function wrapped(...args) {
      self.off(name, wrapped);
      return listener.apply(self, args);
    }

    wrapped.listener = listener;
    return this.addListener(name, wrapped);
  }

  prependOnceListener(eventName, listener) {
    if (typeof listener !== "function") {
      throw new TypeError("listener must be a function");
    }

    const name = String(eventName);
    const self = this;

    function wrapped(...args) {
      self.off(name, wrapped);
      return listener.apply(self, args);
    }

    wrapped.listener = listener;
    return this.prependListener(name, wrapped);
  }

  off(eventName, listener) {
    return this.removeListener(eventName, listener);
  }

  removeListener(eventName, listener) {
    if (typeof listener !== "function") return this;

    const name = String(eventName);
    const arr = this._events.get(name);
    if (!arr || arr.length === 0) return this;

    for (let i = arr.length - 1; i >= 0; i--) {
      const fn = arr[i];
      if (fn === listener || fn.listener === listener) {
        arr.splice(i, 1);
        break;
      }
    }

    if (arr.length === 0) this._events.delete(name);
    return this;
  }

  removeAllListeners(eventName) {
    if (eventName === void 0) {
      this._events.clear();
      this._warned.clear();
    } else {
      const name = String(eventName);
      this._events.delete(name);
      this._warned.delete(name);
    }
    return this;
  }

  emit(eventName, ...args) {
    const name = String(eventName);
    const arr = this._events.get(name);

    if (!arr || arr.length === 0) {
      if (name === "error") {
        const err = args.length > 0 ? args[0] : void 0;
        if (err instanceof Error) throw err;
        throw new Error(err === void 0 ? "Unhandled error event" : String(err));
      }
      return false;
    }

    const snapshot = arr.slice();
    for (const fn of snapshot) {
      fn.apply(this, args);
    }

    return true;
  }

  listeners(eventName) {
    const arr = this._events.get(String(eventName));
    return arr ? arr.slice() : [];
  }

  rawListeners(eventName) {
    return this.listeners(eventName);
  }

  listenerCount(eventName) {
    const arr = this._events.get(String(eventName));
    return arr ? arr.length : 0;
  }

  eventNames() {
    return Array.from(this._events.keys());
  }
}

export default EventEmitter;

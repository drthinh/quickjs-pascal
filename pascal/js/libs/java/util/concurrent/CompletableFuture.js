import { deferred } from "qjsp:concurrent/deferred.js";
import { withTimeout } from "qjsp:concurrent/timeout.js";

function _asError(e) {
  if (e instanceof Error) return e;
  return new Error(e === void 0 ? "Error" : String(e));
}

export class CompletableFuture {
  constructor(promise) {
    this._deferred = null;
    this._promise = promise || null;
  }

  static completedFuture(value) {
    return new CompletableFuture(Promise.resolve(value));
  }

  static failedFuture(error) {
    return new CompletableFuture(Promise.reject(_asError(error)));
  }

  static supplyAsync(supplier) {
    if (typeof supplier !== "function") throw new TypeError("CompletableFuture.supplyAsync: supplier must be a function");
    return new CompletableFuture(Promise.resolve().then(() => supplier()));
  }

  static runAsync(runnable) {
    if (typeof runnable !== "function") throw new TypeError("CompletableFuture.runAsync: runnable must be a function");
    return new CompletableFuture(Promise.resolve().then(() => runnable()));
  }

  static allOf(...futures) {
    const ps = futures.map((f) => (f instanceof CompletableFuture ? f._toPromise() : Promise.resolve(f)));
    return new CompletableFuture(Promise.all(ps).then(() => void 0));
  }

  static anyOf(...futures) {
    const ps = futures.map((f) => (f instanceof CompletableFuture ? f._toPromise() : Promise.resolve(f)));
    return new CompletableFuture(Promise.race(ps));
  }

  static deferred() {
    const d = deferred();
    const cf = new CompletableFuture(d.promise);
    cf._deferred = d;
    return cf;
  }

  _toPromise() {
    if (this._promise) return this._promise;
    if (this._deferred) return this._deferred.promise;
    return Promise.resolve(void 0);
  }

  toPromise() {
    return this._toPromise();
  }

  thenApply(fn) {
    if (typeof fn !== "function") throw new TypeError("CompletableFuture.thenApply: fn must be a function");
    return new CompletableFuture(this._toPromise().then((v) => fn(v)));
  }

  thenCompose(fn) {
    if (typeof fn !== "function") throw new TypeError("CompletableFuture.thenCompose: fn must be a function");
    return new CompletableFuture(this._toPromise().then((v) => {
      const r = fn(v);
      return r instanceof CompletableFuture ? r._toPromise() : r;
    }));
  }

  thenAccept(consumer) {
    if (typeof consumer !== "function") throw new TypeError("CompletableFuture.thenAccept: consumer must be a function");
    return new CompletableFuture(this._toPromise().then((v) => {
      consumer(v);
      return void 0;
    }));
  }

  thenRun(runnable) {
    if (typeof runnable !== "function") throw new TypeError("CompletableFuture.thenRun: runnable must be a function");
    return new CompletableFuture(this._toPromise().then(() => {
      runnable();
      return void 0;
    }));
  }

  exceptionally(fn) {
    if (typeof fn !== "function") throw new TypeError("CompletableFuture.exceptionally: fn must be a function");
    return new CompletableFuture(this._toPromise().catch((e) => fn(e)));
  }

  handle(fn) {
    if (typeof fn !== "function") throw new TypeError("CompletableFuture.handle: fn must be a function");
    return new CompletableFuture(this._toPromise().then(
      (v) => fn(v, null),
      (e) => fn(null, e)
    ));
  }

  whenComplete(fn) {
    if (typeof fn !== "function") throw new TypeError("CompletableFuture.whenComplete: fn must be a function");
    return new CompletableFuture(this._toPromise().then(
      (v) => {
        fn(v, null);
        return v;
      },
      (e) => {
        fn(null, e);
        throw e;
      }
    ));
  }

  orTimeout(timeoutMs, makeError) {
    return new CompletableFuture(withTimeout(this._toPromise(), timeoutMs, makeError));
  }

  complete(value) {
    if (!this._deferred) throw new Error("CompletableFuture.complete: not a deferred CompletableFuture");
    this._deferred.resolve(value);
    return true;
  }

  completeExceptionally(error) {
    if (!this._deferred) throw new Error("CompletableFuture.completeExceptionally: not a deferred CompletableFuture");
    this._deferred.reject(_asError(error));
    return true;
  }
}

export default CompletableFuture;

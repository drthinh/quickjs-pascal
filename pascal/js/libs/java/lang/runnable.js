export class Runnable {
  constructor() {
    return;
  }

  run() {
    throw new Error("java.lang.Runnable.run is not implemented");
  }
}

export function isRunnable(obj) {
  return obj != null && typeof obj.run === "function";
}

export function toRunnable(target) {
  if (typeof target === "function") return { run: target };
  if (isRunnable(target)) return target;
  throw new TypeError("Runnable target must be a function or an object with run()");
}

export default Runnable;

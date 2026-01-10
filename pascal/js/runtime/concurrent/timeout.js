export function sleep(ms) {
  ms = Number(ms);
  if (!Number.isFinite(ms) || ms < 0) throw new RangeError("sleep: ms must be >= 0");
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function withTimeout(promise, ms, makeError) {
  ms = Number(ms);
  if (!Number.isFinite(ms) || ms < 0) throw new RangeError("withTimeout: ms must be >= 0");
  if (makeError !== void 0 && typeof makeError !== "function") {
    throw new TypeError("withTimeout: makeError must be a function");
  }

  let t;
  const timeoutPromise = new Promise((_, reject) => {
    t = setTimeout(() => {
      reject(makeError ? makeError() : new Error(`Timeout after ${ms}ms`));
    }, ms);
  });

  try {
    return await Promise.race([promise, timeoutPromise]);
  } finally {
    clearTimeout(t);
  }
}

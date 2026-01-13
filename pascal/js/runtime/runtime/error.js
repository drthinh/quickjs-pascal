export class QjspError extends Error {
  constructor(code, message, details, cause) {
    super(String(message || code || "Error"));
    this.name = "QjspError";
    this.code = code != null ? String(code) : "QJSP_E_RUNTIME_ERROR";
    if (details !== void 0) this.details = details;
    if (cause !== void 0) this.cause = cause;
  }
}

export function toQjspError(e, fallbackCode, fallbackMessage, details) {
  try {
    if (e && typeof e === "object") {
      if (typeof e.code === "string" && e.code) return e;
      if (e instanceof QjspError) return e;
      if (e instanceof Error) {
        return new QjspError(fallbackCode || "QJSP_E_RUNTIME_ERROR", fallbackMessage || e.message || String(e), details, e);
      }
    }
  } catch (_) {
  }
  return new QjspError(fallbackCode || "QJSP_E_RUNTIME_ERROR", fallbackMessage || String(e), details, e);
}

export function requireNative(featureName, obj, fnName) {
  const ok = obj && typeof obj === "object" && typeof obj[fnName] === "function";
  if (!ok) {
    throw new QjspError(
      "QJSP_E_RUNTIME_MISSING_NATIVE",
      `${String(featureName)}: native shim not installed`,
      { feature: String(featureName), fn: String(fnName) }
    );
  }
}

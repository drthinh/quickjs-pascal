import { QjspError, toQjspError } from "qjsp:index.js";
import { requireNative } from "qjsp:runtime/error.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

function assertEq(a, b, msg) {
  if (a !== b) throw new Error((msg || "assertEq failed") + `: ${String(a)} !== ${String(b)}`);
}

function assertString(x, msg) {
  assert(typeof x === "string" && x.length >= 0, msg || "expected string");
}

// QjspError basics
{
  const e = new QjspError("QJSP_E_TEST", "hello", { a: 1 });
  assertEq(e.name, "QjspError", "QjspError.name");
  assertEq(e.code, "QJSP_E_TEST", "QjspError.code");
  assertString(e.message, "QjspError.message");
  assert(e.details && e.details.a === 1, "QjspError.details");
}

// toQjspError: pass-through when e has string .code
{
  const e0 = { code: "QJSP_E_X", message: "x" };
  const e = toQjspError(e0, "QJSP_E_FALLBACK");
  assert(e === e0, "toQjspError should pass-through objects with .code");
}

// toQjspError: wrap Error
{
  const cause = new Error("boom");
  const e = toQjspError(cause, "QJSP_E_WRAP", "wrapped", { k: 1 });
  assertEq(e.name, "QjspError", "wrapped.name");
  assertEq(e.code, "QJSP_E_WRAP", "wrapped.code");
  assertString(e.message, "wrapped.message");
  assert(e.details && e.details.k === 1, "wrapped.details");
  assert(e.cause === cause, "wrapped.cause");
}

// requireNative: always throws QjspError with QJSP_E_RUNTIME_MISSING_NATIVE
{
  let ok = false;
  try {
    requireNative("feature1", {}, "missingFn");
  } catch (e) {
    ok = true;
    assert(e && typeof e === "object", "expected error object");
    assertEq(e.name, "QjspError", "requireNative.name");
    assertEq(e.code, "QJSP_E_RUNTIME_MISSING_NATIVE", "requireNative.code");
    assertString(e.message, "requireNative.message");
    assert(e.details && e.details.feature === "feature1", "requireNative.details.feature");
    assert(e.details && e.details.fn === "missingFn", "requireNative.details.fn");
  }
  assert(ok, "expected requireNative to throw");
}

console.log("error model test OK");

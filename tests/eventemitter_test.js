import { EventEmitter } from "qjsp:events/EventEmitter.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

// once
{
  const ee = new EventEmitter();
  let c = 0;
  ee.once("a", () => c++);
  ee.emit("a");
  ee.emit("a");
  assert(c === 1, "once failed");
}

// prependListener ordering
{
  const ee = new EventEmitter();
  const order = [];
  ee.on("a", () => order.push(2));
  ee.prependListener("a", () => order.push(1));
  ee.emit("a");
  assert(order.join(",") === "1,2", "prependListener ordering failed");
}

// prependOnceListener ordering + once
{
  const ee = new EventEmitter();
  const order = [];
  ee.on("a", () => order.push(2));
  ee.prependOnceListener("a", () => order.push(1));
  ee.emit("a");
  ee.emit("a");
  assert(order.join(",") === "1,2,2", "prependOnceListener failed");
}

// error semantics: unhandled 'error' should throw
{
  const ee = new EventEmitter();
  let threw = false;
  try {
    ee.emit("error", new Error("boom"));
  } catch (e) {
    threw = true;
    assert(e && String(e.message).includes("boom"), "error event threw wrong error");
  }
  assert(threw, "unhandled error should throw");
}

"ok";

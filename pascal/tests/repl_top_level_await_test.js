import * as os from "qjs:os";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

const v = await Promise.resolve(7);
assert(v === 7, "expected 7");

os.sleep(0);
console.log("repl top-level await test OK");

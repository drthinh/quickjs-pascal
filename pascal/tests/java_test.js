import { runJavaSelfTest } from "lib:java";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

(async () => {
  const r = await runJavaSelfTest({ tmpDir: "tmp/stdjs-java-test" });
  if (r && r.results) {
    for (const item of r.results) {
      if (!item.ok) {
        console.log("FAIL:", item.name, item.error || "");
      }
    }
  }
  assert(r && r.ok === true, "java selftest failed");
  console.log("java_test.js: OK");
})();

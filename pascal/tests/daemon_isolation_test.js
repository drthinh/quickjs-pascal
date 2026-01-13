import { io, os } from "qjsp:index.js";
import { spawn } from "qjsp:os/spawn.js";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

const platform = os.system.platform;

if (platform !== "win32") {
  console.log("daemon isolation test skipped (win32 only)");
} else {
  const { fs, path } = io;

  function fileUrlToPath(u) {
    const s = String(u || "");
    if (!s.startsWith("file:")) return s;
    let p = s.replace(/^file:\/\//i, "");
    p = p.replace(/^\//, "");
    try { p = decodeURIComponent(p); } catch (_) {}
    p = p.replace(/\//g, "\\");
    return p;
  }

  const scriptPath = fileUrlToPath(import.meta.url);
  const scriptDir = scriptPath ? path.dirname(scriptPath) : ".";
  // tests live under <pascalRoot>/tests
  const pascalRoot = path.dirname(scriptDir);

  // Put all artifacts under tests/tmp to satisfy spawn cwd jail and fs_watch allowed roots.
  const absBase = path.join(pascalRoot, "tests", "tmp", "daemon_isolation");
  fs.rmrf(absBase);
  fs.mkdirp(absBase);

  const jobsPath = path.join(absBase, "jobs.jsonl");
  const outPath = path.join(absBase, "out.jsonl");

  const job1 = JSON.stringify({
    id: "job1",
    code: "globalThis.x = 123; globalThis.__job_result = String(globalThis.x);",
  });
  const job2 = JSON.stringify({
    id: "job2",
    code: "globalThis.__job_result = String(globalThis.x || 0);",
  });

  fs.writeTextFile(jobsPath, job1 + "\n" + job2 + "\n");

  const exeArg0 = (os.process && Array.isArray(os.process.argv) && os.process.argv.length > 0)
    ? String(os.process.argv[0])
    : "";

  const candidates = [];
  // Preferred: <pascalRoot>/bin/qjsp.exe when pascalRoot is absolute
  if (path.isAbsolute(pascalRoot)) {
    candidates.push(path.join(pascalRoot, "bin", "qjsp.exe"));
  }
  // Fallbacks when runner path is tricky
  if (exeArg0) {
    // If argv[0] is "bin/qjsp.exe" and cwd is pascal/bin, using just basename works.
    candidates.push(path.basename(exeArg0));
    candidates.push(exeArg0);
  }
  candidates.push("qjsp.exe");

  let exe = "";
  for (const c of candidates) {
    if (!c) continue;
    try {
      if (fs.exists(c)) {
        exe = c;
        break;
      }
    } catch (_) {
    }
  }
  if (!exe) {
    throw new Error("daemon_isolation_test: cannot locate qjsp.exe; tried: " + candidates.join(", "));
  }
  const cfg = path.join(pascalRoot, "config", "qjsp_config.json");

  const p = spawn([exe, "--config", cfg, "--daemon", "--daemon-in", jobsPath, "--daemon-out", outPath], {
    mergeStderr: true,
    timeoutMs: 10000,
    maxOutputKb: 256,
  });

  const r = p.waitSync();
  assert(r && typeof r.code === "number", "expected code:number");
  assert(r.code === 0, "daemon should exit 0");

  const out = fs.readTextFile(outPath).trim().split(/\r?\n/).filter(Boolean);
  assert(out.length >= 2, "expected at least 2 result lines");

  const o1 = JSON.parse(out[0]);
  const o2 = JSON.parse(out[1]);

  assert(o1.ok === true && o1.id === "job1" && String(o1.result) === "123", "job1 result mismatch");
  assert(o2.ok === true && o2.id === "job2" && String(o2.result) === "0", "job2 should not see global state from job1");

  fs.rmrf(absBase);
  console.log("daemon isolation test OK");
}

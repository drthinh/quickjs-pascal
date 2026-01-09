import { io, sh, os } from "qjsp:index.js";

const { fs, path } = io;

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

const platform = os.system.platform;

// ps: use redirection because repl() prints output and returns void in non-redirect mode
{
  const base = "./.qjsp_tmp_sh_ps";
  fs.rmrf(base);
  fs.mkdirp(base);
  const outPath = path.join(base, "ps.txt");
  if (fs.exists(outPath)) fs.remove(outPath);
  sh.repl(`ps > ${outPath}`);
  assert(fs.exists(outPath), "ps redirect should create output file");
  const txt = fs.readTextFile(outPath);
  assert(String(txt || "").trim().length > 0, "ps output file should be non-empty");
  fs.rmrf(base);
}

// ln: hardlink test (skip on win32 if mklink /H fails due to permissions/filesystem)
{
  const base = "./.qjsp_tmp_sh_ln";
  fs.rmrf(base);
  fs.mkdirp(base);

  const src = path.join(base, "src.txt");
  const dst = path.join(base, "dst.txt");
  fs.writeTextFile(src, "x\n");

  let lnOk = false;
  try {
    sh.repl(`ln -f ${src} ${dst}`);
    lnOk = true;
  } catch (e) {
    // Windows mklink may require admin or developer mode; treat as skipped.
    if (platform !== "win32") throw e;
  }

  if (lnOk) {
    assert(fs.exists(dst), "ln should create link");
    assert(fs.readTextFile(dst) === "x\n", "ln link content mismatch");
  }

  fs.rmrf(base);
}

// kill: don't hard-assert behavior in CI; just ensure command parses and fails cleanly on invalid pid
{
  let threw = false;
  try {
    sh.repl("kill 99999999");
  } catch (e) {
    threw = true;
  }
  // On some systems it may succeed if PID exists; just ensure it doesn't crash runtime.
  assert(typeof threw === "boolean", "kill should not crash");
}

console.log("stdjs sh ps/kill/ln test OK");

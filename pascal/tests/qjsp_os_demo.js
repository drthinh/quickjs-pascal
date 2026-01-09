import * as std from "qjs:std";
import * as os from "qjsp:os";
import { EventEmitter } from "qjsp:events";

function hr(title) {
  std.printf("\n=== %s ===\n", title);
}

hr("qjsp:events alias");
{
  const ee = new EventEmitter();
  ee.on("data", (x) => {
    std.printf("event data: %s\n", String(x));
  });
  ee.emit("data", "hello");
}

hr("qjsp:os system helpers");
std.printf("platform: %s\n", os.platform);
std.printf("arch: %s\n", os.arch);
std.printf("hostname: %s\n", os.hostname);
std.printf("homedir(): %s\n", os.homedir());
std.printf("tmpdir(): %s\n", os.tmpdir());

hr("qjsp:os.path helpers");
{
  const p1 = os.path.normalize("C:/Users//demo/../demo2/file.txt");
  std.printf("normalize: %s\n", p1);
  std.printf("toPosix: %s\n", os.path.toPosix("C:\\Temp\\a\\b"));
  std.printf("toWin: %s\n", os.path.toWin("/tmp/a/b"));
  std.printf("split: %s\n", JSON.stringify(os.path.split("C:/a/b/c")));
  std.printf("isUNC(\\\\server\\share\\x): %s\n", os.path.isUNC("\\\\server\\share\\x"));

  const parsed = os.path.parse("C:/a/b/c.txt");
  std.printf("parse: %s\n", JSON.stringify(parsed));
  std.printf("format(parse): %s\n", os.path.format(parsed));
  std.printf("relative: %s\n", os.path.relative("C:/a/b", "C:/a/d/e.txt"));
}

hr("qjsp:os.fs wrapper (re-export from qjsp:io/fs)");
{
  const demoDir = os.path.join(os.tmpdir(), "qjsp_demo");
  const demoFile = os.path.join(demoDir, "hello.txt");

  os.fs.mkdirp(demoDir);
  os.fs.writeTextFile(demoFile, "hello from qjsp:os.fs\n");
  const text = os.fs.readTextFile(demoFile);
  std.printf("read back: %s", text);
  std.printf("exists: %s\n", os.fs.exists(demoFile));

  const list = os.fs.readdir(demoDir);
  std.printf("readdir: %s\n", JSON.stringify(list));
}

hr("qjsp:os exec/execFile (Node-lite)");
{
  // Prefer very portable commands.
  // On Windows: 'cmd /c echo ...'
  // On POSIX: 'sh -lc echo ...'
  const isWin = os.platform === "win32";
  const r1 = os.exec(isWin ? "cmd /c echo exec_ok" : "sh -lc 'echo exec_ok'");
  std.printf("exec: code=%s\n", String(r1.code));
  if (r1.stdout) std.printf("stdout: %s\n", r1.stdout.trim());

  const r2 = os.execFile(isWin ? "cmd" : "sh", isWin ? ["/c", "echo", "execFile_ok"] : ["-lc", "echo execFile_ok"]);
  std.printf("execFile: code=%s\n", String(r2.code));
  if (r2.stdout) std.printf("stdout: %s\n", r2.stdout.trim());
}

hr("done");

import { io } from "qjsp:index.js";

const { path, fs } = io;

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

const base = "./.qjsp_tmp_glob";
const src = path.join(base, "src");

fs.rmrf(base);
fs.mkdirp(path.join(src, "a", "b"));

fs.writeTextFile(path.join(src, "root.txt"), "root\n");
fs.writeTextFile(path.join(src, "a", "a.js"), "a\n");
fs.writeTextFile(path.join(src, "a", "b", "b.js"), "b\n");
fs.writeTextFile(path.join(src, "a", "b", "b.ts"), "b\n");

const jsFiles = fs.glob("**/*.js", { cwd: src }).map((p) => path.normalize(p));
assert(jsFiles.length === 2, "glob should find 2 .js files");
assert(jsFiles.some((p) => p.endsWith(path.join("a", "a.js"))), "glob should include a/a.js");
assert(jsFiles.some((p) => p.endsWith(path.join("a", "b", "b.js"))), "glob should include a/b/b.js");

assert(fs.matchGlob("**/*.js", "a/b/c.js"), "matchGlob should match nested js");
assert(!fs.matchGlob("**/*.js", "a/b/c.ts"), "matchGlob should not match ts");
assert(fs.matchGlob("a/?.js", "a/x.js"), "matchGlob should support ?");
assert(!fs.matchGlob("a/?.js", "a/xx.js"), "matchGlob ? should be single char");

const tmp = fs.mkdtemp("qjsp-test");
assert(fs.exists(tmp), "mkdtemp should create directory");

const created = await fs.withTempDir((d) => {
  fs.writeTextFile(path.join(d, "x.txt"), "x\n");
  return d;
}, { prefix: "qjsp-with" });
assert(!fs.exists(created), "withTempDir should cleanup directory");

fs.rmrf(base);

console.log("stdjs io glob/temp test OK");

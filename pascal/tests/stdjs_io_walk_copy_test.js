import { io } from "qjsp:index.js";

const { path, fs } = io;

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

const base = "./.qjsp_tmp_walk";
const src = path.join(base, "src");
const dst = path.join(base, "dst");

fs.rmrf(base);
fs.mkdirp(path.join(src, "a", "b"));

fs.writeTextFile(path.join(src, "root.txt"), "root\n");
fs.writeTextFile(path.join(src, "a", "a.txt"), "a\n");
fs.writeTextFile(path.join(src, "a", "b", "b.txt"), "b\n");

const walked = Array.from(fs.walk(src));
assert(walked.some((p) => p.endsWith("root.txt")), "walk should include root.txt");
assert(walked.some((p) => p.endsWith(path.join("a", "a.txt"))), "walk should include a/a.txt");
assert(walked.some((p) => p.endsWith(path.join("a", "b", "b.txt"))), "walk should include a/b/b.txt");

const files = Array.from(fs.walkFiles(src));
assert(files.length === walked.length, "walkFiles should match walk default (files only)");

const dirs = Array.from(fs.walkDirs(src));
assert(dirs.some((p) => p.endsWith(path.join("a"))), "walkDirs should include a");
assert(dirs.some((p) => p.endsWith(path.join("a", "b"))), "walkDirs should include a/b");

fs.copyDir(src, dst, { overwrite: true });
assert(fs.exists(path.join(dst, "root.txt")), "copyDir should copy root.txt");
assert(fs.readTextFile(path.join(dst, "a", "b", "b.txt")) === "b\n", "copyDir content mismatch");

fs.rmrf(base);
assert(!fs.exists(base), "rmrf should remove tree");

console.log("stdjs io walk/copy test OK");

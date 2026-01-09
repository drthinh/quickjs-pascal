import { io, sh } from "qjsp:index.js";

const { fs, path } = io;

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

const base = "./.qjsp_tmp_sh_redirect";
fs.rmrf(base);
fs.mkdirp(base);

const out1 = path.join(base, "out1.txt");
const out2 = path.join(base, "out2.txt");
const out3 = path.join(base, "out3.txt");

if (fs.exists(out1)) fs.remove(out1);
if (fs.exists(out2)) fs.remove(out2);
if (fs.exists(out3)) fs.remove(out3);

sh.repl(`echo hello 1> ${out1}`);
assert(fs.exists(out1), "1> should create output file");
assert(fs.readTextFile(out1).trim() === "hello", "1> should write stdout to file");

sh.repl(`echo world 1>> ${out1}`);
assert(fs.readTextFile(out1).replace(/\r\n/g, "\n").trimEnd().endsWith("world"), "1>> should append");

sh.repl(`echo a > ${out2}`);
assert(fs.readTextFile(out2).trim() === "a", "> should still work");

// &> is implemented by sh and should work for builtins; for system cmds it depends on shell.
sh.repl(`echo both &> ${out3}`);
assert(fs.readTextFile(out3).trim() === "both", "&> should redirect stdout (and stderr) for builtins");

fs.rmrf(base);

console.log("stdjs sh redirect test OK");

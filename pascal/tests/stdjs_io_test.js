import { io } from "qjsp:index.js";

const { path, fs } = io;

const tmpDir = "./.qjsp_tmp";
fs.mkdirp(tmpDir);

const p = path.join(tmpDir, "hello.txt");
fs.writeTextFile(p, "hello\n");

if (!fs.exists(p)) throw new Error("fs.exists failed");

const s = fs.readTextFile(p);
if (s !== "hello\n") throw new Error("fs.readTextFile failed");

const files = fs.readdir(tmpDir);
if (!Array.isArray(files)) throw new Error("fs.readdir should return array");

fs.remove(p);
fs.remove(tmpDir);

console.log("stdjs io test OK");

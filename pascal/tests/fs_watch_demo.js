import { io } from "qjsp:index.js";

const { fs, path } = io;

const dir = "./.qjsp_tmp_watch_demo";
fs.rmrf(dir);
fs.mkdirp(dir);

console.log("Watching:", dir);

const w = fs.watch(dir, (ev) => {
  console.log("event", ev.type, ev.path, "(id=" + ev.id + ")");
});

fs.writeTextFile(path.join(dir, "a.txt"), "a\n");

setTimeout(() => {
  fs.writeTextFile(path.join(dir, "a.txt"), "b\n");
}, 200);

setTimeout(() => {
  fs.rename(path.join(dir, "a.txt"), path.join(dir, "b.txt"));
}, 400);

setTimeout(() => {
  fs.remove(path.join(dir, "b.txt"));
}, 600);

setTimeout(() => {
  w.close();
  fs.rmrf(dir);
  console.log("watch demo done");
}, 1000);

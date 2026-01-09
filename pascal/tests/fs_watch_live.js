import { io } from "qjsp:index.js";

const { fs } = io;

const dir = String(scriptArgs[1] || "./.qjsp_tmp_watch_demo");
const recursive = true;

console.log("Watching (live):", dir);
console.log("- Make changes now: create/modify/rename/delete files");
console.log("- Press Ctrl+C to exit\n");

const w = fs.watch(dir, (ev) => {
  console.log("event", ev.type, ev.path, "(id=" + ev.id + ")");
}, { recursive });

// Keep process alive
for (;;) {
  await new Promise((r) => setTimeout(r, 1000));
}

import { formatLine } from "qjsp:log/format.js";
import * as std from "qjs:std";

export function consoleSink() {
  return {
    write(entry) {
      const line = formatLine(entry);
      if (entry.level >= 40) console.error(line);
      else console.log(line);
    },
  };
}

export function fileSink(filename) {
  filename = String(filename);
  return {
    write(entry) {
      const line = formatLine(entry) + "\n";
      const f = std.open(filename, "a");
      if (!f) throw new Error(`fileSink: cannot open ${filename}`);
      try {
        f.puts(line);
        f.flush();
      } finally {
        f.close();
      }
    },
  };
}

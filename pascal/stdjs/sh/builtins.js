export function runBuiltin(cmd, args, stdinText, api) {
  const a0 = args.length >= 2 ? args[1] : "";

  const {
    pwd,
    echo,
    platform,
    exec,
    toStr,
    quoteArgShell,
    trimFinalNewline,
    expandShortFlags,
    isFlag,
    expandArg,
    resolvePathExpanded,
    fs,
    path,
    proc,
    env,
    system,
    cat,
    head,
    tail,
    grep,
    find,
    which,
    buildSystemCommandWithInput,
    cleanupTemp,
    warnCompat,
    splitLines,
    writeRedirectText,
    http,
  } = api;

  if (cmd === "pwd") return pwd();
  if (cmd === "echo") return echo(...args.slice(1));

  if (cmd === "wget" || cmd === "curl") {
    if (stdinText != null) throw new Error(cmd + ": stdin piping not supported");
    if (!http || typeof http.request !== "function") throw new Error(cmd + ": http client not available");

    let url = "";
    let outFile = "";
    let followRedirects = cmd === "curl" ? true : true;
    let method = "GET";
    const headersObj = {};
    let data = void 0;

    // Minimal arg parsing
    for (let i = 1; i < args.length; i++) {
      const rawA = toStr(args[i]);
      const expanded = expandShortFlags(rawA);
      const list = expanded ? expanded : [rawA];

      for (let j = 0; j < list.length; j++) {
        const a = toStr(list[j]);

        if (a === "-L") {
          followRedirects = true;
          continue;
        }

        if (a === "-O") {
          // wget: use last path segment
          continue;
        }

        if (a === "-o" || a === "-O" || a === "--output") {
          const v = (j + 1 < list.length) ? list[j + 1] : (i + 1 < args.length ? toStr(args[i + 1]) : "");
          if (!v) throw new Error(cmd + ": missing output file after " + a);
          outFile = resolvePathExpanded(expandArg(v));
          if (j + 1 < list.length) j++;
          else i++;
          continue;
        }

        if (a === "-X" || a === "--request") {
          const v = (j + 1 < list.length) ? list[j + 1] : (i + 1 < args.length ? toStr(args[i + 1]) : "");
          if (!v) throw new Error(cmd + ": missing method after " + a);
          method = String(v).toUpperCase();
          if (j + 1 < list.length) j++;
          else i++;
          continue;
        }

        if (a === "-H" || a === "--header") {
          const v = (j + 1 < list.length) ? list[j + 1] : (i + 1 < args.length ? toStr(args[i + 1]) : "");
          if (!v) throw new Error(cmd + ": missing header after " + a);
          const s = String(v);
          const p = s.indexOf(":");
          if (p <= 0) throw new Error(cmd + ": invalid header: " + s);
          const k = s.slice(0, p).trim();
          const vv = s.slice(p + 1).trim();
          headersObj[k] = vv;
          if (j + 1 < list.length) j++;
          else i++;
          continue;
        }

        if (a === "-d" || a === "--data") {
          const v = (j + 1 < list.length) ? list[j + 1] : (i + 1 < args.length ? toStr(args[i + 1]) : "");
          if (v === "") throw new Error(cmd + ": missing data after " + a);
          data = String(v);
          if (method === "GET") method = "POST";
          if (j + 1 < list.length) j++;
          else i++;
          continue;
        }

        if (!isFlag(a) && !url) {
          url = String(expandArg(a));
          continue;
        }
      }
    }

    if (!url) throw new Error("Usage: " + cmd + " [options] <url>");

    // wget -O: infer output name
    if (cmd === "wget" && outFile === "" && args.includes("-O")) {
      try {
        const u = String(url);
        const clean = u.split("?")[0].split("#")[0];
        const b = clean.replace(/\\/g, "/");
        const name = b.endsWith("/") ? "index.html" : b.slice(b.lastIndexOf("/") + 1) || "index.html";
        outFile = resolvePathExpanded(name);
      } catch (e) {
        outFile = resolvePathExpanded("index.html");
      }
    }

    const r = http.request(method, url, {
      headers: headersObj,
      body: data,
      followRedirects,
      responseType: outFile ? "arraybuffer" : "text",
    });

    if (!r || typeof r.status !== "number") throw new Error(cmd + ": invalid response");
    if (r.status < 200 || r.status >= 300) throw new Error(cmd + ": HTTP " + r.status);

    if (outFile) {
      fs.writeFile(outFile, r.body);
      return "";
    }

    return r.text();
  }

  if (cmd === "ps") {
    if (stdinText != null) throw new Error("ps: stdin piping not supported");
    const argv = args.slice(1).map(toStr).map(quoteArgShell);
    if (platform === "win32") {
      const r = exec(["tasklist", ...argv].join(" "));
      return r && typeof r.stdout === "string" ? trimFinalNewline(r.stdout) : "";
    }
    const r = exec(["ps", ...argv].join(" "));
    return r && typeof r.stdout === "string" ? trimFinalNewline(r.stdout) : "";
  }

  if (cmd === "kill") {
    if (stdinText != null) throw new Error("kill: stdin piping not supported");
    const pos = [];
    let sig = "";
    for (let i = 1; i < args.length; i++) {
      const a = toStr(args[i]);
      if (a.startsWith("-") && a.length > 1 && pos.length === 0) {
        sig = a;
      } else {
        pos.push(a);
      }
    }
    if (pos.length < 1) throw new Error("Usage: kill [-SIGNAL|-9] <pid>");
    const pid = pos[0];

    if (platform === "win32") {
      const force = sig === "-9" || sig.toUpperCase() === "-KILL";
      const parts = ["taskkill", "/PID", quoteArgShell(pid), "/T"];
      if (force) parts.push("/F");
      const rr = exec(parts.join(" "));
      const code = rr && typeof rr.code === "number" ? rr.code : 0;
      if (code !== 0) throw new Error("kill: failed (code=" + code + ")");
      return rr && typeof rr.stdout === "string" ? trimFinalNewline(rr.stdout) : "";
    }

    const parts = ["kill"];
    if (sig) parts.push(sig);
    parts.push(quoteArgShell(pid));
    const rr = exec(parts.join(" "));
    const code = rr && typeof rr.code === "number" ? rr.code : 0;
    if (code !== 0) throw new Error("kill: failed (code=" + code + ")");
    return rr && typeof rr.stdout === "string" ? trimFinalNewline(rr.stdout) : "";
  }

  if (cmd === "ln") {
    if (stdinText != null) throw new Error("ln: stdin piping not supported");

    let symbolic = false;
    let force = false;
    const pos = [];
    for (let i = 1; i < args.length; i++) {
      const rawA = toStr(args[i]);
      const expanded = expandShortFlags(rawA);
      const list = expanded ? expanded : [rawA];
      for (const a of list) {
        if (a === "-s") symbolic = true;
        else if (a === "-f") force = true;
        else if (isFlag(a)) {
        } else pos.push(expandArg(a));
      }
    }
    if (pos.length < 2) throw new Error("Usage: ln [-s] [-f] <target> <linkpath>");

    const target = resolvePathExpanded(pos[0]);
    const linkPath = resolvePathExpanded(pos[1]);

    if (force && fs.exists(linkPath)) {
      try {
        fs.remove(linkPath);
      } catch (e) {
      }
    }

    if (platform === "win32") {
      const mk = symbolic ? "mklink" : "mklink /H";
      const cmdline = `cmd /c ${mk} ${quoteArgShell(linkPath)} ${quoteArgShell(target)}`;
      const rr = exec(cmdline);
      const code = rr && typeof rr.code === "number" ? rr.code : 0;
      if (code !== 0) throw new Error("ln: failed (code=" + code + ")");
      return rr && typeof rr.stdout === "string" ? trimFinalNewline(rr.stdout) : "";
    }

    const rr = exec(["ln", ...(symbolic ? ["-s"] : []), quoteArgShell(target), quoteArgShell(linkPath)].join(" "));
    const code = rr && typeof rr.code === "number" ? rr.code : 0;
    if (code !== 0) throw new Error("ln: failed (code=" + code + ")");
    return rr && typeof rr.stdout === "string" ? trimFinalNewline(rr.stdout) : "";
  }

  if (cmd === "ls") {
    let all = false;
    let target = "";
    for (let i = 1; i < args.length; i++) {
      const rawA = String(args[i]);
      const expanded = expandShortFlags(rawA);
      const list = expanded ? expanded : [rawA];
      for (const a of list) {
        if (a === "-a" || a === "--all") all = true;
        else if (isFlag(a)) {
        } else if (!target) {
          target = expandArg(a);
        }
      }
    }
    if (!target) target = ".";
    const items = api.ls(target, all ? { all: true } : void 0);
    return Array.isArray(items) ? items.join("\n") : toStr(items);
  }

  if (cmd === "cat") {
    if (!a0) {
      if (stdinText != null) return String(stdinText);
      throw new Error("Usage: cat <file>");
    }
    return String(cat(expandArg(a0)));
  }

  if (cmd === "head") {
    if (!a0) {
      if (stdinText == null) throw new Error("Usage: head <file> [n]");
      const n = args.length >= 2 ? Number(args[1]) : void 0;
      const count = n === void 0 ? 10 : Math.max(0, Math.floor(Number(n)));
      return splitLines(stdinText).slice(0, count).join("\n");
    }
    const n = args.length >= 3 ? Number(args[2]) : void 0;
    return String(head(expandArg(a0), n));
  }

  if (cmd === "tail") {
    if (!a0) {
      if (stdinText == null) throw new Error("Usage: tail <file> [n]");
      const n = args.length >= 2 ? Number(args[1]) : void 0;
      const count = n === void 0 ? 10 : Math.max(0, Math.floor(Number(n)));
      const lines = splitLines(stdinText);
      return lines.slice(Math.max(0, lines.length - count)).join("\n");
    }
    const n = args.length >= 3 ? Number(args[2]) : void 0;
    return String(tail(expandArg(a0), n));
  }

  if (cmd === "grep") {
    let recursive = false;
    let ignoreCase = false;
    let lineNumber = false;
    const pos = [];
    for (let i = 1; i < args.length; i++) {
      const rawA = String(args[i]);
      const expanded = expandShortFlags(rawA);
      const list = expanded ? expanded : [rawA];
      for (const a of list) {
        if (a === "-r" || a === "-R" || a === "--recursive") recursive = true;
        else if (a === "-i" || a === "--ignore-case") ignoreCase = true;
        else if (a === "-n" || a === "--line-number") lineNumber = true;
        else if (isFlag(a)) {
        } else pos.push(a);
      }
    }

    if (stdinText != null && pos.length >= 1) {
      const pat = pos[0] instanceof RegExp ? pos[0] : new RegExp(toStr(pos[0]), ignoreCase ? "i" : "");
      const lines = splitLines(stdinText);
      const out = [];
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (pat.test(line)) out.push(lineNumber ? `${i + 1}:${line}` : line);
      }
      return out.join("\n");
    }

    if (pos.length < 2) throw new Error("Usage: grep [-r] [-i] [-n] <pattern> <path>");
    return String(grep(pos[0], expandArg(pos[1]), { ...(recursive ? { recursive: true } : {}), ...(ignoreCase ? { ignoreCase: true } : {}), ...(lineNumber ? { lineNumber: true } : {}) }));
  }

  if (cmd === "find") {
    const haveStdin = stdinText != null;
    const hasFsFlags = args.some((x) => x === "-name" || x === "-type" || x === "-maxdepth");

    if (haveStdin && !hasFsFlags) {
      if (!a0) throw new Error("Usage: find <text>");
      const needle = toStr(a0);
      const lines = splitLines(stdinText);
      const out = [];
      for (const line of lines) {
        if (line.includes(needle)) out.push(line);
      }
      return out.join("\n");
    }

    let start = ".";
    let name = "";
    let type = "";
    let maxDepth = void 0;

    const pos = [];
    for (let i = 1; i < args.length; i++) pos.push(String(args[i]));

    let i = 0;
    if (pos.length && !isFlag(pos[0])) {
      start = expandArg(pos[0]);
      i = 1;
    }

    for (; i < pos.length; i++) {
      const a = pos[i];
      if (a === "-name") {
        i++;
        name = i < pos.length ? String(pos[i]) : "";
      } else if (a === "-type") {
        i++;
        type = i < pos.length ? String(pos[i]) : "";
      } else if (a === "-maxdepth") {
        i++;
        maxDepth = i < pos.length ? Number(pos[i]) : void 0;
      }
    }

    const res = find(start, { ...(name ? { name } : {}), ...(type ? { type } : {}), ...(maxDepth != null ? { maxDepth } : {}) });
    return Array.isArray(res) ? res.join("\n") : toStr(res);
  }

  if (cmd === "sed") {
    let ignoreCase = false;
    const pos = [];
    for (let i = 1; i < args.length; i++) {
      const rawA = String(args[i]);
      const expanded = expandShortFlags(rawA);
      const list = expanded ? expanded : [rawA];
      for (const a of list) {
        if (a === "-i") ignoreCase = true;
        else if (isFlag(a)) {
        } else pos.push(a);
      }
    }
    if (pos.length < 1) throw new Error("Usage: sed <s/pat/repl/[g]> [file]");

    const expr = String(pos[0]);
    const inputText = pos.length >= 2 ? String(cat(expandArg(pos[1]))) : (stdinText != null ? String(stdinText) : "");

    if (!expr.startsWith("s")) throw new Error("sed: only s/// supported");
    const delim = expr.length >= 2 ? expr[1] : "/";
    const parts = expr.slice(2).split(delim);
    if (parts.length < 3) throw new Error("sed: invalid expression");
    const patSrc = parts[0];
    const repl = parts[1];
    const flagsRaw = parts[2] || "";
    const g = flagsRaw.includes("g");
    const re = new RegExp(patSrc, (g ? "g" : "") + (ignoreCase ? "i" : ""));
    return inputText.replace(re, repl);
  }

  if (cmd === "awk") {
    const pos = [];
    for (let i = 1; i < args.length; i++) {
      const a = String(args[i]);
      if (isFlag(a)) {
      } else pos.push(a);
    }
    if (pos.length < 1) throw new Error("Usage: awk '{print $1,$2}' [file]");

    const prog = String(pos[0]).trim();
    const inputText = pos.length >= 2 ? String(cat(expandArg(pos[1]))) : (stdinText != null ? String(stdinText) : "");
    const lines = splitLines(inputText);

    let fields = null;
    if (prog === "{print}" || prog === "{ print }" || prog === "{print $0}" || prog === "{ print $0 }") {
      fields = null;
    } else {
      const m = prog.match(/\{\s*print\s+([^}]*)\}/);
      if (!m) throw new Error("awk: only '{print ...}' supported");
      const expr = m[1].trim();
      if (!expr || expr === "$0") {
        fields = null;
      } else {
        const nums = [];
        const re = /\$([0-9]+)/g;
        let mm;
        while ((mm = re.exec(expr))) nums.push(Number(mm[1]));
        fields = nums.length ? nums : null;
      }
    }

    const out = [];
    for (const line of lines) {
      if (fields == null) {
        out.push(line);
        continue;
      }
      const cols = String(line).trim().split(/\s+/g);
      out.push(fields.map((n) => (n <= 0 ? "" : (cols[n - 1] != null ? cols[n - 1] : ""))).join(" ").trimEnd());
    }
    return out.join("\n");
  }

  if (cmd === "curl" || cmd === "tar") {
    if (stdinText != null) throw new Error(cmd + ": stdin piping not supported");
    const argv = args.slice(1).map(toStr).map(quoteArgShell);
    const fullCmd = [cmd, ...argv].join(" ");
    const r = exec(fullCmd);
    return r && typeof r.stdout === "string" ? r.stdout.replace(/\r\n/g, "\n").replace(/\r/g, "\n").replace(/\n$/, "") : "";
  }

  if (cmd === "which") {
    if (!a0) throw new Error("Usage: which <cmd>");
    const r = which(expandArg(a0));
    return r == null ? "" : String(r);
  }

  if (cmd === "run") {
    if (!a0) throw new Error("Usage: run <command>");
    const built = buildSystemCommandWithInput(expandArg(a0), stdinText);
    let sysCmd = typeof built === "string" ? built : built.cmd;
    const tmp = typeof built === "string" ? null : built.tmp;
    const r = exec(sysCmd);
    cleanupTemp(tmp);
    return r && typeof r.stdout === "string" ? trimFinalNewline(r.stdout) : "";
  }

  if (cmd === "basename") {
    if (!a0) throw new Error("Usage: basename <path> [ext]");
    return String(path.basename(expandArg(a0), args.length >= 3 ? expandArg(args[2]) : void 0));
  }

  if (cmd === "dirname") {
    if (!a0) throw new Error("Usage: dirname <path>");
    return String(path.dirname(expandArg(a0)));
  }

  if (cmd === "realpath") {
    if (!a0) throw new Error("Usage: realpath <path>");
    return String(resolvePathExpanded(a0));
  }

  if (cmd === "stat") {
    if (!a0) throw new Error("Usage: stat <path>");
    const p = resolvePathExpanded(a0);
    const st = fs.stat(p);
    if (!st) throw new Error("stat: not found: " + p);
    const isDir = (st.mode & 0o170000) === 0o040000;
    const isFile = (st.mode & 0o170000) === 0o100000;
    const mtime = api.formatTime(st);
    return [`path=${p}`, `size=${st.size}`, `mode=${(st.mode & 0o777).toString(8)}`, `isDir=${isDir}`, `isFile=${isFile}`, `mtime=${mtime}`].join("\n");
  }

  if (cmd === "env") {
    if (args.length >= 2) {
      const key = toStr(args[1]);
      if (key.includes("=")) {
        const i = key.indexOf("=");
        const k = key.slice(0, i);
        const v = key.slice(i + 1);
        env.set(k, v, true);
        return "";
      }
      return toStr(env.get(key, ""));
    }
    warnCompat("env: listing all variables not supported in this build; try 'run " + (platform === "win32" ? "set" : "env") + "'");
    return "";
  }

  if (cmd === "export") {
    if (!a0) throw new Error("Usage: export NAME=VALUE");
    const kv = toStr(a0);
    const i = kv.indexOf("=");
    if (i < 0) throw new Error("export: expected NAME=VALUE");
    env.set(kv.slice(0, i), kv.slice(i + 1), true);
    return "";
  }

  if (cmd === "unset") {
    if (!a0) throw new Error("Usage: unset NAME");
    env.unset(toStr(a0));
    return "";
  }

  if (cmd === "sleep") {
    if (!a0) throw new Error("Usage: sleep <seconds>");
    const sec = Number(a0);
    if (!Number.isFinite(sec) || sec < 0) throw new Error("sleep: invalid seconds");
    proc.sleep(sec * 1000);
    return "";
  }

  if (cmd === "date") {
    const now = new Date();
    if (!a0) return now.toISOString();
    const fmt = toStr(a0);
    if (!fmt.startsWith("+")) return now.toISOString();
    const z = (n, w) => String(n).padStart(w, "0");
    return fmt.slice(1)
      .replace(/%Y/g, String(now.getFullYear()))
      .replace(/%m/g, z(now.getMonth() + 1, 2))
      .replace(/%d/g, z(now.getDate(), 2))
      .replace(/%H/g, z(now.getHours(), 2))
      .replace(/%M/g, z(now.getMinutes(), 2))
      .replace(/%S/g, z(now.getSeconds(), 2));
  }

  if (cmd === "clear") {
    if (platform === "win32") {
      exec("cls");
      return "";
    }
    return "\u001b[2J\u001b[H";
  }

  if (cmd === "rmdir") {
    if (!a0) throw new Error("Usage: rmdir <dir>");
    const p = resolvePathExpanded(a0);
    fs.remove(p);
    return "";
  }

  if (cmd === "mktemp") {
    let dir = false;
    let template = "tmp";
    for (let i = 1; i < args.length; i++) {
      const a = toStr(args[i]);
      if (a === "-d") dir = true;
      else if (!isFlag(a)) template = a;
    }
    const p = fs.mkdtemp(template);
    if (!dir) {
      const f = path.join(p, "file");
      fs.writeTextFile(f, "");
      return f;
    }
    return p;
  }

  if (cmd === "wc") {
    let countLines = false;
    let countWords = false;
    let countBytes = false;
    let countChars = false;
    const files = [];
    for (let i = 1; i < args.length; i++) {
      const a = toStr(args[i]);
      const ex = expandShortFlags(a);
      const list = ex ? ex : [a];
      for (const x of list) {
        if (x === "-l") countLines = true;
        else if (x === "-w") countWords = true;
        else if (x === "-c") countBytes = true;
        else if (x === "-m") countChars = true;
        else if (isFlag(x)) {
        } else files.push(expandArg(x));
      }
    }
    if (!countLines && !countWords && !countBytes && !countChars) {
      countLines = countWords = countBytes = true;
    }

    const calc = (text) => {
      const t = toStr(text);
      const norm = t.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
      const m = norm.match(/\n/g);
      let lines = m ? m.length : 0;
      if (norm !== "" && !norm.endsWith("\n")) lines++;
      const wm = norm.match(/\S+/g);
      const words = wm ? wm.length : 0;
      const bytes = new TextEncoder().encode(norm).length;
      const chars = norm.length;
      const parts = [];
      if (countLines) parts.push(String(lines));
      if (countWords) parts.push(String(words));
      if (countBytes) parts.push(String(bytes));
      if (countChars) parts.push(String(chars));
      return parts.join(" ");
    };

    if (files.length === 0) {
      if (stdinText == null) throw new Error("Usage: wc [-l] [-w] [-c] [-m] [file]");
      return calc(stdinText);
    }
    const out = [];
    for (const f of files) {
      const p = resolvePathExpanded(f);
      const txt = fs.readTextFile(p);
      out.push(calc(txt) + " " + p);
    }
    return out.join("\n");
  }

  if (cmd === "sort") {
    let reverse = false;
    let numeric = false;
    let unique = false;
    const pos = [];
    for (let i = 1; i < args.length; i++) {
      const a = toStr(args[i]);
      const ex = expandShortFlags(a);
      const list = ex ? ex : [a];
      for (const x of list) {
        if (x === "-r") reverse = true;
        else if (x === "-n") numeric = true;
        else if (x === "-u") unique = true;
        else if (isFlag(x)) {
        } else pos.push(expandArg(x));
      }
    }
    const inputText = pos.length ? String(cat(pos[0])) : (stdinText != null ? String(stdinText) : "");
    let lines = splitLines(inputText);
    if (lines.length && lines[lines.length - 1] === "") lines = lines.slice(0, -1);
    lines.sort((a, b) => {
      if (numeric) return Number(a) - Number(b);
      return String(a).localeCompare(String(b));
    });
    if (reverse) lines.reverse();
    if (unique) {
      const u = [];
      for (const l of lines) {
        if (!u.length || u[u.length - 1] !== l) u.push(l);
      }
      lines = u;
    }
    return lines.join("\n");
  }

  if (cmd === "uniq") {
    const pos = [];
    for (let i = 1; i < args.length; i++) {
      const a = toStr(args[i]);
      if (isFlag(a)) {
      } else pos.push(expandArg(a));
    }
    const inputText = pos.length ? String(cat(pos[0])) : (stdinText != null ? String(stdinText) : "");
    let lines = splitLines(inputText);
    if (lines.length && lines[lines.length - 1] === "") lines = lines.slice(0, -1);
    const out = [];
    for (const l of lines) {
      if (!out.length || out[out.length - 1] !== l) out.push(l);
    }
    return out.join("\n");
  }

  if (cmd === "cut") {
    let delim = "\t";
    let fields = "";
    const pos = [];
    for (let i = 1; i < args.length; i++) {
      const a = toStr(args[i]);
      if (a === "-d") {
        i++;
        delim = i < args.length ? toStr(args[i]) : delim;
      } else if (a === "-f") {
        i++;
        fields = i < args.length ? toStr(args[i]) : "";
      } else if (isFlag(a)) {
      } else pos.push(expandArg(a));
    }
    if (!fields) throw new Error("cut: requires -f");
    const idx = fields.split(",").map((x) => Math.max(1, Math.floor(Number(x)))).filter((x) => Number.isFinite(x) && x > 0);
    const inputText = pos.length ? String(cat(pos[0])) : (stdinText != null ? String(stdinText) : "");
    let lines = splitLines(inputText);
    if (lines.length && lines[lines.length - 1] === "") lines = lines.slice(0, -1);
    const out = [];
    for (const l of lines) {
      const cols = String(l).split(delim);
      out.push(idx.map((n) => (cols[n - 1] != null ? cols[n - 1] : "")).join(delim));
    }
    return out.join("\n");
  }

  if (cmd === "tr") {
    let del = false;
    const pos = [];
    for (let i = 1; i < args.length; i++) {
      const a = toStr(args[i]);
      if (a === "-d") del = true;
      else if (isFlag(a)) {
      } else pos.push(toStr(args[i]));
    }
    const inputText = stdinText != null ? String(stdinText) : (pos.length >= 3 ? String(cat(expandArg(pos[2]))) : "");
    const set1 = pos.length >= 1 ? pos[0] : "";
    const set2 = pos.length >= 2 ? pos[1] : "";
    if (!set1) throw new Error("tr: requires SET1");
    if (!del && set2 === "") throw new Error("tr: requires SET2 (or -d)");
    const map = new Map();
    for (let i = 0; i < set1.length; i++) {
      map.set(set1[i], del ? "" : (set2[i] != null ? set2[i] : set2[set2.length - 1] || ""));
    }
    let out = "";
    for (const ch of inputText) {
      if (map.has(ch)) out += map.get(ch);
      else out += ch;
    }
    return out;
  }

  if (cmd === "tee") {
    let append = false;
    const files = [];
    for (let i = 1; i < args.length; i++) {
      const a = toStr(args[i]);
      if (a === "-a") append = true;
      else if (isFlag(a)) {
      } else files.push(expandArg(a));
    }
    const inputText = stdinText != null ? String(stdinText) : "";
    for (const f of files) {
      writeRedirectText(f, inputText, append);
    }
    return inputText;
  }

  if (cmd === "xargs") {
    if (stdinText == null) throw new Error("Usage: xargs <cmd> [args...]");
    const base = args.slice(1).map(toStr);
    if (!base.length) throw new Error("Usage: xargs <cmd> [args...]");
    const extra = toStr(stdinText).trim().split(/\s+/g).filter((x) => x);
    const argv = base.concat(extra);
    const cmd2 = String(argv[0]).toLowerCase();
    const out = runBuiltin(cmd2, argv, null, api);
    if (out == null) throw new Error("xargs: only supports builtin commands");
    return toStr(out);
  }

  return null;
}

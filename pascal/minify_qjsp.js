// Minify/Uglify helper for QuickJS (qjsp/qjs).
// Public domain JSMin variant by Douglas Crockford, adapted for QuickJS CLI.
// Usage:
//   qjsp pascal/minify_qjsp.js input.js output.min.js
//   qjsp pascal/minify_qjsp.js input.js      # write to stdout
//   qjsp pascal/minify_qjsp.js input.js -    # write to stdout
// No npm dependencies.

import * as std from 'qjs:std';
import * as os from 'qjs:os';

function isAlphanum(c) {
  if (!c) return false;
  const code = c.charCodeAt(0);
  return (
    (code >= 97 && code <= 122) || // a-z
    (code >= 65 && code <= 90) || // A-Z
    (code >= 48 && code <= 57) || // 0-9
    c === '_' ||
    c === '$' ||
    code > 126
  );
}

// ---------- Identifier rename helpers (simple, tokenizer-based) ----------

const RESERVED_KEYWORDS = new Set([
  'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger', 'default', 'delete', 'do', 'else', 'export', 'extends', 'finally', 'for', 'function', 'if', 'import', 'in', 'instanceof', 'new', 'return', 'super', 'switch', 'this', 'throw', 'try', 'typeof', 'var', 'void', 'while', 'with', 'yield', 'let', 'enum', 'await', 'implements', 'package', 'protected', 'static', 'interface', 'private', 'public', 'null', 'true', 'false',
]);

const RESERVED_GLOBALS = new Set([
  'arguments', 'Array', 'ArrayBuffer', 'Atomics', 'BigInt', 'BigInt64Array', 'BigUint64Array', 'Boolean', 'DataView', 'Date', 'decodeURI', 'decodeURIComponent', 'encodeURI', 'encodeURIComponent', 'Error', 'escape', 'eval', 'Float32Array', 'Float64Array', 'Function', 'Infinity', 'Int16Array', 'Int32Array', 'Int8Array', 'Intl', 'isFinite', 'isNaN', 'JSON', 'Map', 'Math', 'NaN', 'Number', 'Object', 'parseFloat', 'parseInt', 'Promise', 'Proxy', 'RangeError', 'ReferenceError', 'Reflect', 'RegExp', 'Set', 'SharedArrayBuffer', 'String', 'Symbol', 'SyntaxError', 'TypeError', 'Uint16Array', 'Uint32Array', 'Uint8Array', 'Uint8ClampedArray', 'undefined', 'unescape', 'URIError', 'WeakMap', 'WeakSet', 'globalThis', 'window', 'self', 'global', 'console', 'require', 'module', 'exports', '__dirname', '__filename', 'std', 'os',
  // QuickJS Pascal DLL helpers
  'LoadDLL', 'LoadLib', 'CallDllFunction', 'FreeDLL',
]);

const NAME_ALPHABET = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ$_';

function isIdentStart(ch) {
  if (!ch) return false;
  const code = ch.charCodeAt(0);
  return (
    (code >= 97 && code <= 122) ||
    (code >= 65 && code <= 90) ||
    ch === '_' ||
    ch === '$'
  );
}

function isIdentPart(ch) {
  if (!ch) return false;
  const code = ch.charCodeAt(0);
  return (
    (code >= 97 && code <= 122) ||
    (code >= 65 && code <= 90) ||
    (code >= 48 && code <= 57) ||
    ch === '_' ||
    ch === '$'
  );
}

function isWhitespace(ch) {
  return ch === ' ' || ch === '\n' || ch === '\r' || ch === '\t' || ch === '\f';
}

function createNameAllocator(reserved) {
  let counter = 0;
  return function nextName() {
    while (true) {
      let n = counter++;
      let name = '';
      const base = NAME_ALPHABET.length;
      do {
        name = NAME_ALPHABET[n % base] + name;
        n = Math.floor(n / base) - 1;
      } while (n >= 0);
      if (!reserved.has(name)) return name;
    }
  };
}

function getPrevNonSpace(str) {
  for (let i = str.length - 1; i >= 0; i--) {
    const ch = str[i];
    if (!isWhitespace(ch)) return ch;
  }
  return '';
}

function getNextNonSpace(str, start) {
  for (let i = start; i < str.length; i++) {
    const ch = str[i];
    if (!isWhitespace(ch)) return ch;
  }
  return '';
}

function isRegexStart(prevTokenType, prevValue) {
  if (prevTokenType === 'start') return true;
  if (prevTokenType === 'operator' || prevTokenType === 'punct') return true;
  if (prevTokenType === 'keyword') {
    return [
      'return',
      'case',
      'throw',
      'else',
      'do',
      'typeof',
      'delete',
      'void',
      'in',
      'of',
      'instanceof',
      'await',
      'yield',
      'new',
    ].includes(prevValue);
  }
  return false;
}

function skipString(source, i, quote) {
  let out = '';
  out += source[i++];
  while (i < source.length) {
    const ch = source[i++];
    out += ch;
    if (ch === '\\') {
      if (i < source.length) {
        out += source[i];
        i++;
      }
      continue;
    }
    if (ch === quote) break;
  }
  return { text: out, nextIndex: i };
}

function skipRegex(source, i) {
  let out = '';
  out += source[i++]; // '/'
  while (i < source.length) {
    const ch = source[i++];
    out += ch;
    if (ch === '\\') {
      if (i < source.length) {
        out += source[i];
        i++;
      }
      continue;
    }
    if (ch === '[') {
      // character class
      while (i < source.length) {
        const c = source[i++];
        out += c;
        if (c === '\\') {
          if (i < source.length) {
            out += source[i];
            i++;
          }
          continue;
        }
        if (c === ']') break;
      }
      continue;
    }
    if (ch === '/') break;
  }
  // flags
  while (i < source.length && isIdentPart(source[i])) {
    out += source[i++];
  }
  return { text: out, nextIndex: i };
}

function skipTemplate(source, i, state) {
  let out = '';
  out += source[i++]; // `
  while (i < source.length) {
    const ch = source[i++];
    out += ch;
    if (ch === '\\') {
      if (i < source.length) {
        out += source[i];
        i++;
      }
      continue;
    }
    if (ch === '`') break;
    if (ch === '$' && source[i] === '{') {
      out += '{';
      i++;
      // parse inner expression until matching }
      let depth = 1;
      let expr = '';
      let prevType = 'start';
      let prevValue = '';
      while (i < source.length && depth > 0) {
        const c = source[i];
        if (c === '\'' || c === '"' || c === '`') {
          const s = skipString(source, i, c);
          expr += s.text;
          i = s.nextIndex;
          prevType = 'string';
          prevValue = '';
          continue;
        }
        if (c === '/' && isRegexStart(prevType, prevValue)) {
          const r = skipRegex(source, i);
          expr += r.text;
          i = r.nextIndex;
          prevType = 'regex';
          prevValue = '';
          continue;
        }
        if (c === '{') {
          depth++;
          expr += c;
          i++;
          prevType = 'punct';
          prevValue = c;
          continue;
        }
        if (c === '}') {
          depth--;
          if (depth === 0) {
            i++; // consume }
            break;
          }
          expr += c;
          i++;
          prevType = 'punct';
          prevValue = c;
          continue;
        }
        if (isIdentStart(c)) {
          let start = i;
          i++;
          while (i < source.length && isIdentPart(source[i])) i++;
          const id = source.slice(start, i);
          expr += id;
          prevType = RESERVED_KEYWORDS.has(id) ? 'keyword' : 'ident';
          prevValue = id;
          continue;
        }
        expr += c;
        i++;
        if ('(){}[],:?.+-*/%<>=!&|^~'.includes(c)) {
          prevType = 'operator';
          prevValue = c;
        } else if (isWhitespace(c)) {
          // keep previous
        } else {
          prevType = 'punct';
          prevValue = c;
        }
      }
      out += renameIdentifiers(expr, state);
      out += '}';
    }
  }
  return { text: out, nextIndex: i };
}

function renameIdentifiers(source, opts = {}) {
  const enabled = opts.enabled !== false;
  if (!enabled) return source;

  const keepSet = opts.keepSet || new Set(opts.keep || []);
  const reserved =
    opts.reserved || new Set([...RESERVED_KEYWORDS, ...RESERVED_GLOBALS, ...keepSet]);
  const mapping = opts.mapping || new Map();
  const nextName = createNameAllocator(reserved);

  const renameFn =
    opts.renameFn ||
    ((id, ctx) => {
      const skip =
        reserved.has(id) ||
        ctx.prev === '.' ||
        ctx.prev === '?' || // ?. optional chaining member
        ctx.next === ':' || // label or ternary
        ctx.inImport ||
        ctx.inExport;
      if (skip) return id;
      let renamed = mapping.get(id);
      if (!renamed) {
        renamed = nextName();
        mapping.set(id, renamed);
      }
      return renamed;
    });

  let result = '';
  let i = 0;
  let prevTokenType = 'start';
  let prevValue = '';
  let inExport = false;
  let inImport = false;

  while (i < source.length) {
    const ch = source[i];

    if (isWhitespace(ch)) {
      result += ch;
      i++;
      continue;
    }

    // comments (unlikely after minify but keep safe)
    if (ch === '/' && source[i + 1] === '/') {
      while (i < source.length && source[i] !== '\n') {
        result += source[i++];
      }
      continue;
    }
    if (ch === '/' && source[i + 1] === '*') {
      const end = source.indexOf('*/', i + 2);
      if (end === -1) {
        result += source.slice(i);
        break;
      }
      result += source.slice(i, end + 2);
      i = end + 2;
      continue;
    }

    if (ch === '\'' || ch === '"') {
      const skipped = skipString(source, i, ch);
      result += skipped.text;
      i = skipped.nextIndex;
      prevTokenType = 'string';
      prevValue = '';
      continue;
    }

    if (ch === '`') {
      const skipped = skipTemplate(source, i, { reserved, mapping, renameFn, keepSet });
      result += skipped.text;
      i = skipped.nextIndex;
      prevTokenType = 'string';
      prevValue = '';
      continue;
    }

    if (ch === '/' && isRegexStart(prevTokenType, prevValue)) {
      const skipped = skipRegex(source, i);
      result += skipped.text;
      i = skipped.nextIndex;
      prevTokenType = 'regex';
      prevValue = '';
      continue;
    }

    if (isIdentStart(ch)) {
      const start = i;
      i++;
      while (i < source.length && isIdentPart(source[i])) i++;
      const ident = source.slice(start, i);
      if (RESERVED_KEYWORDS.has(ident)) {
        result += ident;
        prevTokenType = 'keyword';
        prevValue = ident;
        if (ident === 'export') {
          inExport = true;
          inImport = false;
        } else if (ident === 'import') {
          inImport = true;
          inExport = false;
        }
        continue;
      }
      const prev = getPrevNonSpace(result);
      const next = getNextNonSpace(source, i);
      const replaced = renameFn(ident, { prev, next, inExport, inImport });
      result += replaced;
      prevTokenType = 'ident';
      prevValue = ident;
      continue;
    }

    result += ch;
    if (ch === ';' || ch === '\n') {
      inExport = false;
      inImport = false;
    }
    if ('(){}[],:?.+-*/%<>=!&|^~'.includes(ch)) {
      prevTokenType = 'operator';
    } else {
      prevTokenType = 'punct';
    }
    prevValue = ch;
    i++;
  }

  return result;
}

// ---------- JSMin (original) ----------

function JsMin(input) {
  this.input = input;
  this.index = 0;
  this.theA = '';
  this.theB = '';
  this.theLookahead = null;
  this.output = '';
}

JsMin.prototype.get = function () {
  let c = this.theLookahead;
  this.theLookahead = null;
  if (c === null) {
    if (this.index >= this.input.length) return null;
    c = this.input.charAt(this.index++);
  }
  if (c === '\r') return '\n';
  if (c === null) return null;
  if (c.charCodeAt(0) < 32 && c !== '\n' && c !== '\t') return ' ';
  return c;
};

JsMin.prototype.peek = function () {
  this.theLookahead = this.get();
  return this.theLookahead;
};

JsMin.prototype.next = function () {
  let c = this.get();
  if (c === '/') {
    const p = this.peek();
    // // comment
    if (p === '/') {
      while (true) {
        c = this.get();
        if (c === null || c === '\n') return c;
      }
    }
    // /* */ comment
    if (p === '*') {
      this.get();
      while (true) {
        c = this.get();
        if (c === null) throw new Error('Unterminated comment.');
        if (c === '*') {
          if (this.peek() === '/') {
            this.get();
            return ' ';
          }
        }
      }
    }
  }
  return c;
};

JsMin.prototype.action = function (d) {
  if (d <= 1) {
    if (this.theA !== null) this.output += this.theA;
  }
  if (d <= 2) {
    this.theA = this.theB;
    if (this.theA === '\'' || this.theA === '"' || this.theA === '`') {
      // String or template literal
      while (true) {
        this.output += this.theA;
        this.theA = this.get();
        if (this.theA === null) throw new Error('Unterminated string literal.');
        if (this.theA === this.theB) break;
        if (this.theA === '\\') {
          this.output += this.theA;
          this.theA = this.get();
        }
      }
    }
  }
  if (d <= 3) {
    this.theB = this.next();
    if (
      this.theB === '/' &&
      (this.theA === '(' ||
        this.theA === ',' ||
        this.theA === '=' ||
        this.theA === ':' ||
        this.theA === '[' ||
        this.theA === '!' ||
        this.theA === '&' ||
        this.theA === '|' ||
        this.theA === '?' ||
        this.theA === '{' ||
        this.theA === '}' ||
        this.theA === ';' ||
        this.theA === '\n')
    ) {
      // RegExp literal
      this.output += this.theA;
      this.output += this.theB;
      while (true) {
        this.theA = this.get();
        if (this.theA === null) throw new Error('Unterminated RegExp literal.');
        if (this.theA === '/') break;
        if (this.theA === '\\') {
          this.output += this.theA;
          this.theA = this.get();
        }
        this.output += this.theA;
        if (this.theA === '[') {
          // Character class
          while (true) {
            this.theA = this.get();
            this.output += this.theA;
            if (this.theA === null) throw new Error('Unterminated RegExp class.');
            if (this.theA === ']') break;
            if (this.theA === '\\') {
              this.theA = this.get();
              this.output += this.theA;
            }
          }
        }
      }
      this.theB = this.next();
    }
  }
};

function minify(source) {
  const m = new JsMin(source);
  m.theA = '\n';
  m.theB = m.next();
  while (m.theA !== null) {
    switch (m.theA) {
      case ' ':
        m.action(isAlphanum(m.theB) ? 1 : 2);
        break;
      case '\n':
        if ('{[(+-'.includes(m.theB)) {
          m.action(1);
        } else if (m.theB === ' ') {
          m.action(3);
        } else if (isAlphanum(m.theB)) {
          m.action(1);
        } else {
          m.action(2);
        }
        break;
      default:
        if (m.theB === ' ') {
          m.action(isAlphanum(m.theA) ? 1 : 3);
        } else if (m.theB === '\n') {
          if ('}])+-"\''.includes(m.theA) || m.theA === '`' || isAlphanum(m.theA)) {
            m.action(1);
          } else {
            m.action(3);
          }
        } else {
          m.action(1);
        }
    }
  }
  return m.output;
}

function toHex(str) {
  let out = '';
  for (let i = 0; i < str.length; i++) {
    const h = str.charCodeAt(i).toString(16).padStart(2, '0');
    out += h;
  }
  return out;
}

function wrapHexEval(code) {
  const hex = toHex(code);
  const decoder =
    "const _d=h=>{let r='';for(let i=0;i<h.length;i+=2){r+=String.fromCharCode(parseInt(h.slice(i,i+2),16));}return r;};";
  return `(function(){${decoder}eval(_d('${hex}'));})();`;
}

function obfuscate(source, opts = {}) {
  const renameEnabled = opts.rename !== false;
  const encodeEnabled = opts.encode !== false;
  const mini = minify(source);
  const renamed = renameEnabled ? renameIdentifiers(mini) : mini;
  return encodeEnabled ? wrapHexEval(renamed) : renamed;
}

function usage() {
  std.err.puts(
    'Usage: qjsp pascal/minify_qjsp.js <input.js> [output.js|-] [flags]\n' +
      'Default: obfuscate (rename + hex-encode). Disable with flags below.\n' +
      'Flags:\n' +
      '  --no-obf | --plain | --minify-only   Minify only (no rename, no encode)\n' +
      '  --no-rename                          Keep original identifiers (still encode)\n' +
      '  --no-encode                          Skip hex wrapping (still rename)\n'
  );
  os.exit(1);
}

function main(args) {
  let obf = true; // default obfuscation on
  let rename = true;
  let encode = true;
  const files = [];
  for (const a of args) {
    if (a === '--no-obf' || a === '--plain' || a === '--minify-only') {
      obf = false;
      rename = false;
      encode = false;
    } else if (a === '--no-rename') {
      rename = false;
    } else if (a === '--no-encode') {
      encode = false;
    } else {
      files.push(a);
    }
  }

  if (files.length < 1) usage();
  const input = files[0];
  const output = files.length >= 2 ? files[1] : '-';
  const source = std.loadFile(input);
  if (source === null) {
    std.err.puts(`Cannot read input file: ${input}\n`);
    os.exit(1);
  }
  let result;
  try {
    if (obf) {
      result = obfuscate(source, { rename, encode });
    } else {
      result = minify(source);
    }
  } catch (e) {
    std.err.puts(`Minify error: ${e.message}\n`);
    os.exit(1);
  }
  if (output === '-' || output === '/dev/stdout') {
    std.out.puts(result);
  } else {
    const f = std.open(output, 'w');
    if (!f) {
      std.err.puts(`Cannot open output file: ${output}\n`);
      os.exit(1);
    }
    f.puts(result);
    f.close();
  }
}

main(scriptArgs.slice(1));

$ErrorActionPreference = 'Stop'

$root = 'd:\Projects\quickjs\quickjs-master'
$src = Join-Path $root 'pascal\java_api\lang'
$dst = Join-Path $root 'pascal\java\lang'

New-Item -ItemType Directory -Force -Path $dst | Out-Null

function Write-Utf8NoBom([string]$path, [string]$text) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $enc)
}

function Emit-Lines([string[]]$lines) {
  return (($lines -join "`n") + "`n")
}

$files = Get-ChildItem -LiteralPath $src -Filter '*.java' -File

foreach ($f in $files) {
  $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
  $out = Join-Path $dst ($base.ToLower() + '.js')

  if (Test-Path -LiteralPath $out) {
    continue
  }

  $lines = @()

  switch ($base) {
    'Object' {
      $lines = @(
        'export class Object {',
        '  constructor() {}',
        '  equals(other) { return this === other; }',
        '  hashCode() { return 0; }',
        '  toString() { return "[object java.lang.Object]"; }',
        '}',
        '',
        'export default Object;'
      )
    }

    'Throwable' {
      $lines = @(
        'export class Throwable extends globalThis.Error {',
        '  constructor(message, cause) {',
        '    super(message === void 0 ? null : String(message));',
        '    this.name = "Throwable";',
        '    this.cause = cause;',
        '  }',
        '}',
        '',
        'export default Throwable;'
      )
    }

    'Exception' {
      $lines = @(
        'import { Throwable } from "qjsp:java/lang/throwable.js";',
        '',
        'export class Exception extends Throwable {',
        '  constructor(message, cause) {',
        '    super(message, cause);',
        '    this.name = "Exception";',
        '  }',
        '}',
        '',
        'export default Exception;'
      )
    }

    'RuntimeException' {
      $lines = @(
        'import { Exception } from "qjsp:java/lang/exception.js";',
        '',
        'export class RuntimeException extends Exception {',
        '  constructor(message, cause) {',
        '    super(message, cause);',
        '    this.name = "RuntimeException";',
        '  }',
        '}',
        '',
        'export default RuntimeException;'
      )
    }

    'Error' {
      $lines = @(
        'import { Throwable } from "qjsp:java/lang/throwable.js";',
        '',
        'export class Error extends Throwable {',
        '  constructor(message, cause) {',
        '    super(message, cause);',
        '    this.name = "Error";',
        '  }',
        '}',
        '',
        'export default Error;'
      )
    }

    'Math' {
      $lines = @(
        'const _M = globalThis.Math;',
        '',
        'export const Math = Object.freeze({',
        '  E: _M.E,',
        '  PI: _M.PI,',
        '  abs(x) { return _M.abs(Number(x)); },',
        '  max(a, b) { return _M.max(Number(a), Number(b)); },',
        '  min(a, b) { return _M.min(Number(a), Number(b)); },',
        '  floor(x) { return _M.floor(Number(x)); },',
        '  ceil(x) { return _M.ceil(Number(x)); },',
        '  round(x) { return _M.round(Number(x)); },',
        '  random() { return _M.random(); },',
        '  sqrt(x) { return _M.sqrt(Number(x)); },',
        '  pow(a, b) { return _M.pow(Number(a), Number(b)); },',
        '  sin(x) { return _M.sin(Number(x)); },',
        '  cos(x) { return _M.cos(Number(x)); },',
        '  tan(x) { return _M.tan(Number(x)); },',
        '  log(x) { return _M.log(Number(x)); },',
        '  exp(x) { return _M.exp(Number(x)); },',
        '});',
        '',
        'export default Math;'
      )
    }

    'String' {
      $lines = @(
        'export class String {',
        '  constructor(value) {',
        '    if (value instanceof String) this._s = value._s;',
        '    else if (value === void 0) this._s = "";',
        '    else this._s = globalThis.String(value);',
        '  }',
        '',
        '  length() { return this._s.length; }',
        '  charAt(i) { return this._s.charAt(Number(i)); }',
        '  substring(begin, end) {',
        '    const b = Number(begin);',
        '    if (end === void 0) return new String(this._s.substring(b));',
        '    return new String(this._s.substring(b, Number(end)));',
        '  }',
        '  concat(str) { return new String(this._s + globalThis.String(str instanceof String ? str._s : str)); }',
        '  replace(oldCh, newCh) {',
        '    return new String(this._s.split(globalThis.String(oldCh)).join(globalThis.String(newCh)));',
        '  }',
        '  toLowerCase() { return new String(this._s.toLowerCase()); }',
        '  toUpperCase() { return new String(this._s.toUpperCase()); }',
        '  trim() { return new String(this._s.trim()); }',
        '  toString() { return this._s; }',
        '  valueOf() { return this._s; }',
        '',
        '  equals(other) {',
        '    const o = other instanceof String ? other._s : (other === null || other === void 0 ? null : globalThis.String(other));',
        '    return o !== null && this._s === o;',
        '  }',
        '  equalsIgnoreCase(other) {',
        '    const o = other instanceof String ? other._s : (other === null || other === void 0 ? null : globalThis.String(other));',
        '    return o !== null && this._s.toLowerCase() === o.toLowerCase();',
        '  }',
        '  compareTo(other) {',
        '    const o = other instanceof String ? other._s : globalThis.String(other);',
        '    if (this._s === o) return 0;',
        '    return this._s < o ? -1 : 1;',
        '  }',
        '  startsWith(prefix) { return this._s.startsWith(globalThis.String(prefix instanceof String ? prefix._s : prefix)); }',
        '  endsWith(suffix) { return this._s.endsWith(globalThis.String(suffix instanceof String ? suffix._s : suffix)); }',
        '  indexOf(x, fromIndex) {',
        '    const fi = fromIndex === void 0 ? 0 : Number(fromIndex);',
        '    return this._s.indexOf(globalThis.String(x instanceof String ? x._s : x), fi);',
        '  }',
        '  lastIndexOf(x, fromIndex) {',
        '    const fi = fromIndex === void 0 ? this._s.length : Number(fromIndex);',
        '    return this._s.lastIndexOf(globalThis.String(x instanceof String ? x._s : x), fi);',
        '  }',
        '',
        '  static valueOf(x) { return new String(x); }',
        '}',
        '',
        'export default String;'
      )
    }

    default {
      $lines = @(
        "export class $base {",
        '  constructor() {',
        ('    throw new Error("java.lang.' + $base + ' is not implemented");'),
        '  }',
        '}',
        '',
        "export default $base;"
      )
    }
  }

  Write-Utf8NoBom $out (Emit-Lines $lines)
}

$index = Join-Path $dst 'index.js'
if (-not (Test-Path -LiteralPath $index)) {
  $idxLines = @(
    'export { System } from "qjsp:java/lang/system.js";',
    'export { Object } from "qjsp:java/lang/object.js";',
    'export { String } from "qjsp:java/lang/string.js";',
    'export { Math } from "qjsp:java/lang/math.js";',
    'export { Throwable } from "qjsp:java/lang/throwable.js";',
    'export { Exception } from "qjsp:java/lang/exception.js";',
    'export { RuntimeException } from "qjsp:java/lang/runtimeexception.js";',
    'export { Error } from "qjsp:java/lang/error.js";'
  )

  Write-Utf8NoBom $index (Emit-Lines $idxLines)
}

Write-Host ('Generated java.lang stubs into: ' + $dst)

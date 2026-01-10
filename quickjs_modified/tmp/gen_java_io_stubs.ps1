$ErrorActionPreference = 'Stop'

$root = 'd:\Projects\quickjs\quickjs-master'
$src = Join-Path $root 'pascal\java_api\io'
$dst = Join-Path $root 'pascal\java\io'

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
    'IOException' {
      $lines = @(
        'import { Exception } from "qjsp:java/lang/exception.js";',
        '',
        'export class IOException extends Exception {',
        '  constructor(message, cause) {',
        '    super(message, cause);',
        '    this.name = "IOException";',
        '  }',
        '}',
        '',
        'export default IOException;'
      )
    }

    'FileNotFoundException' {
      $lines = @(
        'import { IOException } from "qjsp:java/io/ioexception.js";',
        '',
        'export class FileNotFoundException extends IOException {',
        '  constructor(message, cause) {',
        '    super(message, cause);',
        '    this.name = "FileNotFoundException";',
        '  }',
        '}',
        '',
        'export default FileNotFoundException;'
      )
    }

    'EOFException' {
      $lines = @(
        'import { IOException } from "qjsp:java/io/ioexception.js";',
        '',
        'export class EOFException extends IOException {',
        '  constructor(message, cause) {',
        '    super(message, cause);',
        '    this.name = "EOFException";',
        '  }',
        '}',
        '',
        'export default EOFException;'
      )
    }

    'InterruptedIOException' {
      $lines = @(
        'import { IOException } from "qjsp:java/io/ioexception.js";',
        '',
        'export class InterruptedIOException extends IOException {',
        '  constructor(message, cause) {',
        '    super(message, cause);',
        '    this.name = "InterruptedIOException";',
        '  }',
        '}',
        '',
        'export default InterruptedIOException;'
      )
    }

    'UTFDataFormatException' {
      $lines = @(
        'import { IOException } from "qjsp:java/io/ioexception.js";',
        '',
        'export class UTFDataFormatException extends IOException {',
        '  constructor(message, cause) {',
        '    super(message, cause);',
        '    this.name = "UTFDataFormatException";',
        '  }',
        '}',
        '',
        'export default UTFDataFormatException;'
      )
    }

    'File' {
      $lines = @(
        'import * as fs from "qjsp:io/fs.js";',
        'import * as p from "qjsp:io/path.js";',
        'import { Path } from "qjsp:java/nio/file/path.js";',
        '',
        'export class File {',
        '  constructor(path) {',
        '    if (path instanceof File) this._path = path._path;',
        '    else this._path = p.normalize(String(path));',
        '  }',
        '',
        '  getPath() { return this._path; }',
        '  toString() { return this._path; }',
        '  exists() { return fs.exists(this._path); }',
        '  isDirectory() { return fs.isDirectory(this._path); }',
        '  isFile() { return fs.isFile(this._path); }',
        '  length() { return fs.isFile(this._path) ? fs.stat(this._path).size : 0; }',
        '  delete() { if (!fs.exists(this._path)) return false; fs.remove(this._path); return true; }',
        '  mkdirs() { fs.mkdirp(this._path); return true; }',
        '  getName() { return p.basename(this._path); }',
        '  getParent() { const d = p.dirname(this._path); if (d === "." || d === this._path) return null; return d; }',
        '  toPath() {',
        '    // java.nio.file.Path facade',
        '    return new Path(this._path);',
        '  }',
        '',
        '  static separatorChar() { return p.sep; }',
        '}',
        '',
        'export default File;'
      )
    }

    default {
      $lines = @(
        "export class $base {",
        '  constructor() {',
        ('    throw new Error("java.io.' + $base + ' is not implemented");'),
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
    'export { File } from "qjsp:java/io/file.js";',
    'export { IOException } from "qjsp:java/io/ioexception.js";',
    'export { FileNotFoundException } from "qjsp:java/io/filenotfoundexception.js";',
    'export { EOFException } from "qjsp:java/io/eofexception.js";',
    'export { InterruptedIOException } from "qjsp:java/io/interruptedioexception.js";',
    'export { UTFDataFormatException } from "qjsp:java/io/utfdataformatexception.js";'
  )
  Write-Utf8NoBom $index (Emit-Lines $idxLines)
}

Write-Host ('Generated java.io stubs into: ' + $dst)

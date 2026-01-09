$ErrorActionPreference = 'Stop'

$root = 'd:\Projects\quickjs\quickjs-master'
$src = Join-Path $root 'pascal\java_api\net'
$dst = Join-Path $root 'pascal\java\net'

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

  # Keep existing facades (these are not in java_api, but are used by current code):
  #   uri.js, url.js, http/*
  $out = Join-Path $dst ($base.ToLower() + '.js')
  if (Test-Path -LiteralPath $out) {
    continue
  }

  $lines = @()

  switch ($base) {
    'URLEncoder' {
      $lines = @(
        'export class URLEncoder {',
        '  static encode(s, enc) {',
        '    if (enc !== void 0 && enc !== null && String(enc).toLowerCase() !== "utf-8") {',
        '      throw new Error("URLEncoder.encode: only utf-8 is supported");',
        '    }',
        '    // Java URLEncoder uses application/x-www-form-urlencoded semantics.',
        '    return encodeURIComponent(String(s)).replace(/%20/g, "+");',
        '  }',
        '}',
        '',
        'export default URLEncoder;'
      )
    }

    'MalformedURLException' {
      $lines = @(
        'import { IOException } from "qjsp:java/io/ioexception.js";',
        '',
        'export class MalformedURLException extends IOException {',
        '  constructor(message, cause) {',
        '    super(message, cause);',
        '    this.name = "MalformedURLException";',
        '  }',
        '}',
        '',
        'export default MalformedURLException;'
      )
    }

    'ProtocolException' {
      $lines = @(
        'import { IOException } from "qjsp:java/io/ioexception.js";',
        '',
        'export class ProtocolException extends IOException {',
        '  constructor(message, cause) {',
        '    super(message, cause);',
        '    this.name = "ProtocolException";',
        '  }',
        '}',
        '',
        'export default ProtocolException;'
      )
    }

    'SocketException' {
      $lines = @(
        'import { IOException } from "qjsp:java/io/ioexception.js";',
        '',
        'export class SocketException extends IOException {',
        '  constructor(message, cause) {',
        '    super(message, cause);',
        '    this.name = "SocketException";',
        '  }',
        '}',
        '',
        'export default SocketException;'
      )
    }

    'UnknownHostException' {
      $lines = @(
        'import { IOException } from "qjsp:java/io/ioexception.js";',
        '',
        'export class UnknownHostException extends IOException {',
        '  constructor(message, cause) {',
        '    super(message, cause);',
        '    this.name = "UnknownHostException";',
        '  }',
        '}',
        '',
        'export default UnknownHostException;'
      )
    }

    'UnknownServiceException' {
      $lines = @(
        'import { IOException } from "qjsp:java/io/ioexception.js";',
        '',
        'export class UnknownServiceException extends IOException {',
        '  constructor(message, cause) {',
        '    super(message, cause);',
        '    this.name = "UnknownServiceException";',
        '  }',
        '}',
        '',
        'export default UnknownServiceException;'
      )
    }

    default {
      $lines = @(
        "export class $base {",
        '  constructor() {',
        ('    throw new Error("java.net.' + $base + ' is not implemented");'),
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
    'export { URI } from "qjsp:java/net/uri.js";',
    'export { URL } from "qjsp:java/net/url.js";',
    'export { URLEncoder } from "qjsp:java/net/urlencoder.js";',
    'export * as http from "qjsp:java/net/http/index.js";'
  )
  Write-Utf8NoBom $index (Emit-Lines $idxLines)
}

Write-Host ('Generated java.net stubs into: ' + $dst)

import { System } from "qjsp:java/lang/system.js";
import { Random } from "qjsp:java/util/random.js";
import { Base64 } from "qjsp:java/util/base64.js";
import { URI } from "qjsp:java/net/uri.js";
import { URL } from "qjsp:java/net/url.js";
import { HttpClient, HttpRequest, BodyHandlers } from "qjsp:java/net/http/index.js";
import { Path } from "qjsp:java/nio/file/path.js";
import { Files } from "qjsp:java/nio/file/files.js";

function _assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

function _eq(a, b, msg) {
  if (a !== b) throw new Error((msg ? msg + ": " : "") + `expected ${String(b)} but got ${String(a)}`);
}

export async function runJavaSelfTest(opts) {
  const o = opts && typeof opts === "object" ? opts : {};

  const results = [];
  function ok(name) {
    results.push({ name, ok: true });
  }
  function fail(name, err) {
    results.push({ name, ok: false, error: String(err && err.message ? err.message : err) });
  }

  // System
  try {
    _assert(typeof System.currentTimeMillis === "function", "System.currentTimeMillis missing");
    const t = System.currentTimeMillis();
    _assert(typeof t === "number" && t > 0, "System.currentTimeMillis invalid");
    _assert(typeof System.nanoTime() === "bigint", "System.nanoTime should return bigint");
    ok("java.lang.System");
  } catch (e) {
    fail("java.lang.System", e);
  }

  // Random (deterministic)
  try {
    const r = new Random(123);
    _eq(r.nextInt(10), 2, "Random deterministic mismatch");
    ok("java.util.Random");
  } catch (e) {
    fail("java.util.Random", e);
  }

  // Base64
  try {
    const enc = Base64.getEncoder();
    const dec = Base64.getDecoder();
    const s = enc.encodeToString(new Uint8Array([1, 2, 3]));
    _eq(s, "AQID", "Base64 encodeToString mismatch");
    const u8 = dec.decode(s);
    _eq(u8.length, 3, "Base64 decode length");
    _eq(u8[0], 1, "Base64 decode[0]");
    _eq(u8[1], 2, "Base64 decode[1]");
    _eq(u8[2], 3, "Base64 decode[2]");
    ok("java.util.Base64");
  } catch (e) {
    fail("java.util.Base64", e);
  }

  // URI/URL
  try {
    const uri = URI.create("https://example.com/a?b=1#c");
    _eq(uri.getHost(), "example.com", "URI host");
    _eq(uri.getPath(), "/a", "URI path");
    _eq(uri.getQuery(), "b=1", "URI query");
    _eq(uri.getFragment(), "c", "URI fragment");

    const url = new URL("https://example.com/a?b=1#c");
    _eq(url.getHost(), "example.com", "URL host");
    _eq(url.getPath(), "/a", "URL path");
    _eq(url.getQuery(), "b=1", "URL query");
    _eq(url.getRef(), "c", "URL ref");

    ok("java.net.URI_URL");
  } catch (e) {
    fail("java.net.URI_URL", e);
  }

  // Files/Path
  try {
    const baseDir = o.tmpDir ? Path.of(String(o.tmpDir)) : Path.of("tmp", "stdjs-java");
    Files.createDirectories(baseDir);

    const p = baseDir.resolve("selftest.txt");
    Files.writeString(p, "hello");
    const text = Files.readString(p);
    _eq(text, "hello", "Files readString");
    _assert(Files.exists(p), "Files.exists after write");
    _assert(Files.deleteIfExists(p) === true, "Files.deleteIfExists");

    ok("java.nio.file.Files_Path");
  } catch (e) {
    fail("java.nio.file.Files_Path", e);
  }

  // HttpClient (optional; requires native http helpers)
  try {
    if (typeof globalThis.HttpRequest !== "function" && typeof globalThis.HttpRequestAsync !== "function") {
      ok("java.net.http.HttpClient (skipped: http helpers not registered)");
    } else {
      const client = HttpClient.newHttpClient();
      const req = HttpRequest.newBuilder(URI.create("https://example.com/"))
        .GET()
        .build();
      const resp = await client.sendAsync(req, BodyHandlers.ofString());
      _assert(resp.statusCode() > 0, "HttpResponse statusCode");
      _assert(typeof resp.body() === "string", "HttpResponse body type");
      ok("java.net.http.HttpClient");
    }
  } catch (e) {
    fail("java.net.http.HttpClient", e);
  }

  const okCount = results.filter((r) => r.ok).length;
  const failCount = results.length - okCount;

  return { ok: failCount === 0, okCount, failCount, results };
}

import { System } from "qjsp:java/lang/system.js";
import { Random } from "qjsp:java/util/random.js";
import { Base64 } from "qjsp:java/util/base64.js";
import { Optional } from "qjsp:java/util/optional.js";
import { ArrayList } from "qjsp:java/util/arraylist.js";
import { HashMap } from "qjsp:java/util/hashmap.js";
import { HashSet } from "qjsp:java/util/hashset.js";
import { Arrays } from "qjsp:java/util/arrays.js";
import { Objects } from "qjsp:java/util/objects.js";
import { Collections } from "qjsp:java/util/collections.js";
import { URI } from "qjsp:java/net/uri.js";
import { URL } from "qjsp:java/net/url.js";
import { URLEncoder } from "qjsp:java/net/urlencoder.js";
import { HttpClient, HttpRequest, BodyHandlers } from "qjsp:java/net/http/index.js";
import { Path } from "qjsp:java/nio/file/path.js";
import { Files } from "qjsp:java/nio/file/files.js";
import * as Nio from "qjsp:java/nio/index.js";
import { ZipFile } from "qjsp:java/util/zip/ZipFile.js";
import { File } from "qjsp:java/io/file.js";
import { ByteArrayInputStream } from "qjsp:java/io/bytearrayinputstream.js";
import { ByteArrayOutputStream } from "qjsp:java/io/bytearrayoutputstream.js";
import { FileInputStream } from "qjsp:java/io/fileinputstream.js";
import { FileOutputStream } from "qjsp:java/io/fileoutputstream.js";
import { DataInputStream } from "qjsp:java/io/datainputstream.js";
import { DataOutputStream } from "qjsp:java/io/dataoutputstream.js";
import { BufferedInputStream } from "qjsp:java/io/bufferedinputstream.js";
import { BufferedOutputStream } from "qjsp:java/io/bufferedoutputstream.js";
import { FilterInputStream } from "qjsp:java/io/filterinputstream.js";
import { FilterOutputStream } from "qjsp:java/io/filteroutputstream.js";
import { PrintStream } from "qjsp:java/io/printstream.js";
import { RandomAccessFile } from "qjsp:java/io/randomaccessfile.js";
import { Object as JObject } from "qjsp:java/lang/object.js";
import { String as JString } from "qjsp:java/lang/string.js";
import { Math as JMath } from "qjsp:java/lang/math.js";
import { Throwable } from "qjsp:java/lang/throwable.js";
import { Exception } from "qjsp:java/lang/exception.js";
import { RuntimeException } from "qjsp:java/lang/runtimeexception.js";
import { Error as JError } from "qjsp:java/lang/error.js";
import { Boolean as JBoolean } from "qjsp:java/lang/boolean.js";
import { Integer } from "qjsp:java/lang/integer.js";
import { Long } from "qjsp:java/lang/long.js";
import { Double } from "qjsp:java/lang/double.js";
import { Character } from "qjsp:java/lang/character.js";
import { StringBuffer } from "qjsp:java/lang/stringbuffer.js";
import { NumberFormatException } from "qjsp:java/lang/numberformatexception.js";

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

  // java.lang basic facades
  try {
    const o = new JObject();
    _assert(typeof o.toString === "function", "Object.toString missing");
    _assert(o.equals(o) === true, "Object.equals self");

    const s = new JString("AbC");
    _eq(s.length(), 3, "String.length");
    _eq(s.toLowerCase().toString(), "abc", "String.toLowerCase");
    _eq(s.toUpperCase().toString(), "ABC", "String.toUpperCase");
    _assert(s.equalsIgnoreCase(new JString("aBc")) === true, "String.equalsIgnoreCase");

    _eq(JMath.floor(1.9), 1, "Math.floor");
    _eq(JMath.max(2, 9), 9, "Math.max");

    const th = new Throwable("t");
    _assert(th instanceof globalThis.Error, "Throwable should extend Error");
    const ex = new Exception("e");
    const rex = new RuntimeException("re");
    const er = new JError("err");
    _assert(ex instanceof Throwable, "Exception instanceof Throwable");
    _assert(rex instanceof Exception, "RuntimeException instanceof Exception");
    _assert(er instanceof Throwable, "java.lang.Error instanceof Throwable");

    ok("java.lang (Object/String/Math/Throwable)");
  } catch (e) {
    fail("java.lang (Object/String/Math/Throwable)", e);
  }

  // java.lang wrappers/exceptions
  try {
    const b = new JBoolean(1);
    _eq(b.booleanValue(), true, "Boolean.booleanValue");
    _eq(JBoolean.parseBoolean("TrUe"), true, "Boolean.parseBoolean");

    _eq(Integer.parseInt("ff", 16), 255, "Integer.parseInt radix");
    _eq(Integer.toString(255, 16), "ff", "Integer.toString radix");

    _eq(Long.parseLong("-10"), -10n, "Long.parseLong");
    _eq(Long.toString(255n, 16), "ff", "Long.toString radix");

    _eq(Double.isInfinite(Infinity), true, "Double.isInfinite");

    _eq(Character.isDigit("7"), true, "Character.isDigit");
    _eq(Character.toUpperCase("a"), "A", "Character.toUpperCase");

    const sb = new StringBuffer("a");
    sb.append("b").insert(1, "X");
    _eq(sb.toString(), "aXb", "StringBuffer append/insert");
    sb.delete(1, 2);
    _eq(sb.toString(), "ab", "StringBuffer delete");

    let threw = false;
    try {
      Integer.parseInt("not-a-number");
    } catch (e) {
      threw = e instanceof NumberFormatException;
    }
    _assert(threw, "Integer.parseInt should throw NumberFormatException");

    ok("java.lang wrappers (Boolean/Integer/Long/Character/StringBuffer)");
  } catch (e) {
    fail("java.lang wrappers (Boolean/Integer/Long/Character/StringBuffer)", e);
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

  // java.util core collections/util
  try {
    const o1 = Optional.ofNullable("hello");
    _assert(o1.isPresent(), "Optional.isPresent");
    _eq(o1.map((s) => s.toUpperCase()).get(), "HELLO", "Optional.map");
    _eq(Optional.ofNullable(null).orElse("fallback"), "fallback", "Optional.orElse");

    const list = new ArrayList();
    list.add(1);
    list.add(2);
    _eq(list.size(), 2, "ArrayList.size");
    _eq(list.get(0), 1, "ArrayList.get");
    list.set(1, 3);
    _eq(list.get(1), 3, "ArrayList.set");
    list.remove(0);
    _eq(list.get(0), 3, "ArrayList.remove(index)");

    const m = new HashMap();
    _eq(m.put("a", 1), null, "HashMap.put first");
    _eq(m.put("a", 2), 1, "HashMap.put overwrite");
    _eq(m.get("a"), 2, "HashMap.get");
    _assert(m.containsKey("a"), "HashMap.containsKey");
    _eq(m.remove("a"), 2, "HashMap.remove");

    const s = new HashSet();
    _eq(s.add("x"), true, "HashSet.add first");
    _eq(s.add("x"), false, "HashSet.add duplicate");
    _assert(s.contains("x"), "HashSet.contains");
    _eq(s.remove("x"), true, "HashSet.remove");

    _assert(Arrays.equals([1, 2], [1, 2]), "Arrays.equals");
    _eq(Arrays.copyOf([1, 2], 3).length, 3, "Arrays.copyOf");

    _eq(Objects.toString(null, "n"), "n", "Objects.toString nullDefault");
    _eq(Objects.equals(1, 1), true, "Objects.equals");

    const xs = [3, 1, 2];
    Collections.sort(xs);
    _eq(xs.join(","), "1,2,3", "Collections.sort");

    ok("java.util core (Optional/ArrayList/HashMap/HashSet/Arrays/Objects/Collections)");
  } catch (e) {
    fail("java.util core (Optional/ArrayList/HashMap/HashSet/Arrays/Objects/Collections)", e);
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

  // URLEncoder
  try {
    _eq(URLEncoder.encode("a b"), "a+b", "URLEncoder space");
    _eq(URLEncoder.encode("a+b"), "a%2Bb", "URLEncoder plus");
    ok("java.net.URLEncoder");
  } catch (e) {
    fail("java.net.URLEncoder", e);
  }

  // java.nio index
  try {
    _assert(Nio && Nio.file && typeof Nio.file === "object", "java.nio.index missing file namespace");
    _assert(typeof Nio.file.Path === "function", "java.nio.file.Path missing");
    _assert(typeof Nio.file.Files === "object", "java.nio.file.Files missing");
    ok("java.nio.index");
  } catch (e) {
    fail("java.nio.index", e);
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

  // java.io.File
  try {
    const baseDir = o.tmpDir ? String(o.tmpDir) : Path.of("tmp", "stdjs-java").toString();
    const dir = new File(baseDir);
    dir.mkdirs();

    const f = new File(Path.of(baseDir, "selftest-io.txt"));
    Files.writeString(f.toPath(), "hello-io");
    _assert(f.exists(), "File.exists after write");
    _assert(f.isFile(), "File.isFile");
    _assert(f.length() > 0, "File.length");
    _assert(f.delete() === true, "File.delete");
    ok("java.io.File");
  } catch (e) {
    fail("java.io.File", e);
  }

  // java.io ByteArray streams
  try {
    const baos = new ByteArrayOutputStream();
    baos.write(0x41);
    baos.writeBytes(new Uint8Array([0x42, 0x43]));
    _eq(baos.size(), 3, "ByteArrayOutputStream.size");
    const bytes = baos.toByteArray();
    _eq(bytes.length, 3, "ByteArrayOutputStream.toByteArray length");
    _eq(bytes[0], 0x41, "ByteArrayOutputStream byte0");
    _eq(bytes[2], 0x43, "ByteArrayOutputStream byte2");

    const bais = new ByteArrayInputStream(bytes);
    _eq(bais.available(), 3, "ByteArrayInputStream.available");
    _eq(bais.read(), 0x41, "ByteArrayInputStream.read 1");
    _eq(bais.skip(1), 1, "ByteArrayInputStream.skip");
    _eq(bais.read(), 0x43, "ByteArrayInputStream.read 2");
    _eq(bais.read(), -1, "ByteArrayInputStream eof");
    bais.reset();
    const buf = new Uint8Array(3);
    _eq(bais.readBytes(buf), 3, "ByteArrayInputStream.readBytes");
    _eq(new TextDecoder().decode(buf), "ABC", "ByteArray streams roundtrip");
    ok("java.io.ByteArrayInputStream_OutputStream");
  } catch (e) {
    fail("java.io.ByteArrayInputStream_OutputStream", e);
  }

  // java.io FileInputStream/FileOutputStream + Data* + Buffered*
  try {
    const baseDir = o.tmpDir ? String(o.tmpDir) : Path.of("tmp", "stdjs-java").toString();
    const tmp = new File(Path.of(baseDir, "selftest-streams.bin"));

    // write via FileOutputStream
    {
      const fos = new FileOutputStream(tmp, false);
      fos.writeBytes(new Uint8Array([1, 2, 3]));
      fos.close();
    }

    // append via BufferedOutputStream + DataOutputStream
    {
      const fos = new FileOutputStream(tmp, true);
      const bos = new BufferedOutputStream(fos, 4);
      const dos = new DataOutputStream(bos);
      dos.writeInt(0x01020304);
      dos.writeLong(0x0102030405060708n);
      dos.writeBoolean(true);
      dos.close();
    }

    // read via BufferedInputStream + DataInputStream
    {
      const fis = new FileInputStream(tmp);
      const bis = new BufferedInputStream(fis, 4);
      const dis = new DataInputStream(bis);

      const first3 = new Uint8Array(3);
      dis.readFully(first3);
      _eq(first3[0], 1, "FileInputStream first byte");
      _eq(first3[2], 3, "FileInputStream third byte");

      _eq(dis.readInt(), 0x01020304 | 0, "DataInputStream.readInt");
      _eq(dis.readLong(), 0x0102030405060708n, "DataInputStream.readLong");
      _eq(dis.readBoolean(), true, "DataInputStream.readBoolean");

      dis.close();
    }

    _assert(tmp.delete() === true, "cleanup selftest-streams.bin");
    ok("java.io.FileStream_DataStream_BufferedStream");
  } catch (e) {
    fail("java.io.FileStream_DataStream_BufferedStream", e);
  }

  // java.io Filter* + PrintStream
  try {
    const baseDir = o.tmpDir ? String(o.tmpDir) : Path.of("tmp", "stdjs-java").toString();
    const tmp = new File(Path.of(baseDir, "selftest-print.txt"));

    {
      const fos = new FileOutputStream(tmp, false);
      const fout = new FilterOutputStream(fos);
      const ps = new PrintStream(fout, true);
      ps.print("A");
      ps.println("B");
      ps.println();
      ps.close();
    }

    {
      const fis = new FileInputStream(tmp);
      const fin = new FilterInputStream(fis);
      const bytes = new Uint8Array(fin.available());
      _assert(fin.readBytes(bytes) > 0, "FilterInputStream.readBytes");
      fin.close();
      const s = new TextDecoder().decode(bytes);
      _assert(s.indexOf("AB") >= 0, "PrintStream wrote content");
    }

    _assert(tmp.delete() === true, "cleanup selftest-print.txt");
    ok("java.io.Filter_PrintStream");
  } catch (e) {
    fail("java.io.Filter_PrintStream", e);
  }

  // java.io RandomAccessFile
  try {
    const baseDir = o.tmpDir ? String(o.tmpDir) : Path.of("tmp", "stdjs-java").toString();
    const tmp = new File(Path.of(baseDir, "selftest-raf.bin"));

    {
      const raf = new RandomAccessFile(tmp, "rw");
      raf.writeBytes(new Uint8Array([0x41, 0x42, 0x43, 0x44]));
      _eq(raf.length(), 4, "RandomAccessFile.length");
      raf.seek(1);
      raf.write(0x7a);
      raf.seek(0);
      const out = new Uint8Array(4);
      raf.readFully(out);
      raf.close();
      _eq(new TextDecoder().decode(out), "AzCD", "RandomAccessFile overwrite");
    }

    _assert(tmp.delete() === true, "cleanup selftest-raf.bin");
    ok("java.io.RandomAccessFile");
  } catch (e) {
    fail("java.io.RandomAccessFile", e);
  }

  // Zip (native qjs:zip facade)
  try {
    const ab = new TextEncoder().encode("hello").buffer;
    const zipBytes = globalThis.Zip && typeof globalThis.Zip.create === "function"
      ? globalThis.Zip.create([{ name: "a.txt", data: ab }])
      : (await import("qjs:zip")).create([{ name: "a.txt", data: ab }]);

    const zf = ZipFile.fromBytes(zipBytes);
    _assert(zf.size() >= 1, "ZipFile size");
    const entry = zf.getEntry("a.txt");
    _eq(entry.getName(), "a.txt", "ZipEntry name");
    const bytes = zf.getEntryBytes("a.txt");
    _eq(new TextDecoder().decode(bytes), "hello", "Zip read contents");
    zf.close();
    ok("java.util.zip.ZipFile");
  } catch (e) {
    fail("java.util.zip.ZipFile", e);
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

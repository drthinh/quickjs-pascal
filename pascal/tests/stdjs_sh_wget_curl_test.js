import { io, sh } from "qjsp:index.js";

const { fs, path } = io;

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

function eq(a, b, msg) {
  if (a !== b) throw new Error((msg || "eq failed") + ` (got=${String(a)} expected=${String(b)})`);
}

function u8ToString(u8) {
  if (u8 == null) return "";
  if (typeof u8 === "string") return u8;
  if (u8 instanceof Uint8Array) return new TextDecoder().decode(u8);
  if (u8 instanceof ArrayBuffer) return new TextDecoder().decode(new Uint8Array(u8));
  if (typeof ArrayBuffer !== "undefined" && ArrayBuffer.isView && ArrayBuffer.isView(u8)) {
    return new TextDecoder().decode(new Uint8Array(u8.buffer, u8.byteOffset, u8.byteLength));
  }
  return String(u8);
}

function makeResponse(status, bodyText, headers) {
  const u8 = new TextEncoder().encode(String(bodyText || ""));
  return {
    status,
    headers: headers || {},
    body: u8,
    bodyText: String(bodyText || ""),
    text() {
      return String(bodyText || "");
    },
  };
}

(function test_sh_wget_curl_with_mock_http() {
  const base = "./.qjsp_tmp_sh_wget_curl";
  fs.rmrf(base);
  fs.mkdirp(base);

  const savedHttpRequest = globalThis.HttpRequest;

  const calls = [];
  let failCount = 0;

  globalThis.HttpRequest = function (method, url, headers, body, opts) {
    calls.push({ method: String(method), url: String(url), headers: headers || [], body, opts: opts || {} });

    // retry test: first 2 attempts return 503, then OK
    if (String(url).includes("/retry")) {
      if (failCount < 2) {
        failCount++;
        return makeResponse(503, "temporary", { server: "mock" });
      }
      return makeResponse(200, "ok", { server: "mock" });
    }

    // resume test endpoint: return only the remaining bytes
    if (String(url).includes("/resume")) {
      const range = (headers || []).find((kv) => kv && String(kv[0] || "").toLowerCase() === "range");
      const rangeVal = range ? String(range[1] || "") : "";
      // expected: bytes=3-
      if (rangeVal.includes("bytes=3-")) {
        return makeResponse(200, "DEF", { server: "mock" });
      }
      return makeResponse(200, "ABCDEF", { server: "mock" });
    }

    // form tests
    if (String(url).includes("/form")) {
      return makeResponse(200, u8ToString(body), { server: "mock" });
    }

    // default
    return makeResponse(200, "ok", { server: "mock" });
  };

  try {
    // 1) curl --data-urlencode
    calls.length = 0;
    sh.repl(`curl --data-urlencode a=b --data-urlencode "c=hello world" https://example.com/form > ${path.join(base, "curl_urlenc.txt")}`);
    assert(calls.length >= 1, "curl should call HttpRequest");
    eq(calls[0].method, "POST", "curl data-urlencode should switch to POST");
    const ct0 = (calls[0].headers || []).find((kv) => kv && String(kv[0] || "").toLowerCase() === "content-type");
    assert(ct0 && String(ct0[1]).includes("application/x-www-form-urlencoded"), "curl data-urlencode should set content-type");
    assert(String(calls[0].body).includes("a%3Db") || String(calls[0].body).includes("a=b"), "curl data-urlencode body present");

    // 2) curl -F multipart (basic)
    calls.length = 0;
    sh.repl(`curl -F a=b -F x=y https://example.com/form > ${path.join(base, "curl_form.txt")}`);
    eq(calls[0].method, "POST", "curl -F should switch to POST");
    const ct1 = (calls[0].headers || []).find((kv) => kv && String(kv[0] || "").toLowerCase() === "content-type");
    assert(ct1 && String(ct1[1]).includes("multipart/form-data"), "curl -F should set multipart content-type");
    const body1 = String(calls[0].body);
    assert(body1.includes("Content-Disposition: form-data"), "multipart body should have Content-Disposition");
    assert(body1.includes("name=\"a\""), "multipart should include field a");

    // 3) batch URLs (wget): should create 2 files under output dir
    calls.length = 0;
    const outDir = path.join(base, "batch");
    fs.mkdirp(outDir);
    sh.repl(`wget -o ${outDir} https://example.com/a.txt https://example.com/b.txt`);
    assert(fs.exists(path.join(outDir, "a.txt")), "wget batch should write a.txt");
    assert(fs.exists(path.join(outDir, "b.txt")), "wget batch should write b.txt");

    // 4) retry
    calls.length = 0;
    failCount = 0;
    sh.repl(`curl --retry 3 --retry-delay 0 https://example.com/retry > ${path.join(base, "retry.txt")}`);
    assert(calls.length >= 3, "curl retry should call multiple times");

    // 5) resume -C -
    calls.length = 0;
    const resumeFile = path.join(base, "resume.bin");
    fs.writeTextFile(resumeFile, "ABC");
    sh.repl(`wget -C - -o ${resumeFile} https://example.com/resume`);
    const final = fs.readTextFile(resumeFile);
    eq(final, "ABCDEF", "wget resume should append downloaded data");
    const rangeCall = calls.find((c) => (c.headers || []).some((kv) => kv && String(kv[0] || "").toLowerCase() === "range"));
    assert(!!rangeCall, "resume should include Range header");

    console.log("stdjs sh wget/curl test OK");
  } finally {
    globalThis.HttpRequest = savedHttpRequest;
    fs.rmrf(base);
  }
})();

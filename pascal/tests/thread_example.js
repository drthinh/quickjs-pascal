import Thread from "qjsp:java/lang/thread.js";
import Runnable from "qjsp:java/lang/runnable.js";
import { URI } from "qjsp:java/net/uri.js";
import { HttpClient, HttpRequest, BodyHandlers } from "qjsp:java/net/http/index.js";

class MyTask extends Runnable {
  constructor(name, steps) {
    super();
    this.name = name;
    this.steps = steps | 0;
  }

  async run() {
    for (let i = 0; i < this.steps; i++) {
      // simulate async I/O
      await Thread.sleep(50);
      print(`[MyTask:${this.name}] step ${i + 1}/${this.steps}`);
    }
    return `${this.name}:done`;
  }
}

async function main() {
  print("=== Thread + Runnable example ===");

  const client = HttpClient.newHttpClient();
  const t0 = Date.now();

  const urls = [
    "https://example.com/",
    "https://www.wikipedia.org/",
    "https://httpbin.org/get",
    "https://api.github.com/",
  ];

  const threads = urls.map((url) => {
    return new Thread(async () => {
      const startedAt = Date.now();
      print(`[START +${startedAt - t0}ms] ${url}`);
      const uri = URI.create(url);
      const req = HttpRequest.newBuilder(uri)
        .timeout(8000)
        .followRedirects(true)
        .GET()
        .build();

      try {
        const resp = await client.sendAsync(req, BodyHandlers.ofString());
        const body = resp.body();
        const bodyLen = typeof body === "string" ? body.length : 0;
        const preview = typeof body === "string" ? body.slice(0, 80).replace(/\s+/g, " ") : "";
        const doneAt = Date.now();
        print(`[DONE  +${doneAt - t0}ms] ${resp.statusCode()} ${url} len=${bodyLen} preview="${preview}"`);
        return { ok: true, url, status: resp.statusCode(), bodyLen };
      } catch (e) {
        const doneAt = Date.now();
        const msg = String(e && e.message ? e.message : e);
        print(`[ERR   +${doneAt - t0}ms] ${url} error=${msg}`);
        return { ok: false, url, error: msg };
      }
    }, `fetch:${url}`);
  });

  for (const t of threads) t.start();

  await Promise.all(threads.map((t) => t.join()));

  // Runnable object (with run())
  const t1 = new Thread(new MyTask("A", 3), "worker-A");
  t1.start();
  const r1 = await t1.join();
  print(`t1 result: ${String(r1)}`);

  print("=== done ===");
}

await main();

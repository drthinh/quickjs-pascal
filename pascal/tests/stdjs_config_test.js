import * as std from "qjs:std";
import { assert } from "qjsp:util";
import * as fs from "qjsp:io/fs.js";
import * as os from "qjsp:os";
import { loadAndMergeJsonFiles, deepMergeAll } from "qjsp:config";

function hr(title) {
  std.printf("\n=== %s ===\n", title);
}

hr("deepMergeAll");
{
  const a = { a: 1, nested: { x: 1, y: 2 } };
  const b = { b: 2, nested: { y: 999 } };
  const c = deepMergeAll(a, b);
  assert(c.a === 1, "merge keep a");
  assert(c.b === 2, "merge add b");
  assert(c.nested.x === 1, "merge keep nested.x");
  assert(c.nested.y === 999, "merge override nested.y");
}

hr("loadAndMergeJsonFiles");
{
  const dir = os.path.join(os.tmpdir(), "qjsp_config_demo");
  const f1 = os.path.join(dir, "a.json");
  const f2 = os.path.join(dir, "b.json");

  fs.mkdirp(dir);
  fs.writeTextFile(f1, JSON.stringify({ a: 1, nested: { x: 1, y: 2 } }, null, 2));
  fs.writeTextFile(f2, JSON.stringify({ b: 2, nested: { y: 999 } }, null, 2));

  const merged = loadAndMergeJsonFiles([f1, f2]);
  std.printf("merged: %s\n", JSON.stringify(merged));

  assert(merged.a === 1, "file merge keep a");
  assert(merged.b === 2, "file merge add b");
  assert(merged.nested.x === 1, "file merge keep nested.x");
  assert(merged.nested.y === 999, "file merge override nested.y");
}

hr("done");

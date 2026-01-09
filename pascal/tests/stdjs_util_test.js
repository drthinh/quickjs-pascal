import { util } from "qjsp:index.js";

const { Optional, collections } = util;

// Optional
const o1 = Optional.ofNullable("hello");
if (!o1.isPresent()) throw new Error("Optional.ofNullable failed");
if (o1.map((s) => s.toUpperCase()).get() !== "HELLO") throw new Error("Optional.map failed");

const o2 = Optional.ofNullable(null);
if (!o2.isEmpty()) throw new Error("Optional.empty failed");
if (o2.orElse("fallback") !== "fallback") throw new Error("Optional.orElse failed");

// collections
const xs = [1, 2, 3, 4, 5];
const chunks = collections.chunk(xs, 2);
if (chunks.length !== 3 || chunks[0].length !== 2 || chunks[2].length !== 1) throw new Error("collections.chunk failed");

const g = collections.groupBy(["a", "bb", "c", "dd"], (s) => s.length);
if (g.get(1).length !== 2 || g.get(2).length !== 2) throw new Error("collections.groupBy failed");

console.log("stdjs util test OK");

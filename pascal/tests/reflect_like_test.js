function assert(cond, msg) {
  if (!cond) throw new Error("ASSERT FAIL: " + (msg || ""));
}

function eq(a, b, msg) {
  if (a !== b) {
    throw new Error(
      "ASSERT FAIL: " + (msg || "") + " (got=" + String(a) + ", expected=" + String(b) + ")"
    );
  }
}

function has(arr, x, msg) {
  assert(Array.isArray(arr), "has(): arr must be array");
  assert(arr.indexOf(x) >= 0, msg || ("missing: " + String(x)));
}

(function test_object_introspection() {
  const sym = Symbol("s");
  const o = {};
  Object.defineProperty(o, "hidden", { value: 1, enumerable: false });
  o.visible = 2;
  o[sym] = 3;

  const keys = Object.keys(o);
  has(keys, "visible", "Object.keys includes enumerable string keys");
  assert(keys.indexOf("hidden") < 0, "Object.keys excludes non-enumerable");

  const own = Object.getOwnPropertyNames(o);
  has(own, "visible", "getOwnPropertyNames has visible");
  has(own, "hidden", "getOwnPropertyNames has hidden");

  const syms = Object.getOwnPropertySymbols(o);
  eq(syms.length, 1, "getOwnPropertySymbols length");

  const d = Object.getOwnPropertyDescriptor(o, "hidden");
  eq(d.enumerable, false, "descriptor.enumerable");
  eq(d.value, 1, "descriptor.value");
})();

(function test_reflect() {
  const o = { x: 1 };
  eq(Reflect.get(o, "x"), 1, "Reflect.get");
  eq(Reflect.has(o, "x"), true, "Reflect.has");

  Reflect.set(o, "x", 2);
  eq(o.x, 2, "Reflect.set");

  function add(a, b) {
    return a + b;
  }
  eq(Reflect.apply(add, null, [2, 3]), 5, "Reflect.apply");

  function C(a) {
    this.a = a;
  }
  const inst = Reflect.construct(C, [7]);
  eq(inst.a, 7, "Reflect.construct");
})();

(function test_prototype() {
  function A() {}
  A.prototype.m = function () {
    return 123;
  };

  const a = new A();
  eq(Object.getPrototypeOf(a), A.prototype, "getPrototypeOf");
  eq(a instanceof A, true, "instanceof");
  eq(a.m(), 123, "method from prototype");
})();

(function test_proxy() {
  const target = { x: 1 };
  let getCount = 0,
    setCount = 0,
    hasCount = 0;

  const p = new Proxy(target, {
    get(t, prop, recv) {
      getCount++;
      return Reflect.get(t, prop, recv);
    },
    set(t, prop, val, recv) {
      setCount++;
      return Reflect.set(t, prop, val, recv);
    },
    has(t, prop) {
      hasCount++;
      return Reflect.has(t, prop);
    },
    ownKeys(t) {
      return Reflect.ownKeys(t);
    },
  });

  eq(p.x, 1, "proxy get");
  p.x = 2;
  eq(target.x, 2, "proxy set");
  eq("x" in p, true, "proxy has");

  assert(getCount >= 1, "get trap called");
  assert(setCount >= 1, "set trap called");
  assert(hasCount >= 1, "has trap called");
})();

console.log("reflect_like_test.js: OK");

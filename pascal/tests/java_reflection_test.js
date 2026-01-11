import { lang } from "lib:java";

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assert failed");
}

function eq(a, b, msg) {
  if (a !== b) throw new Error((msg || "eq failed") + ` (got=${String(a)} expected=${String(b)})`);
}

class Base {
  baseMethod() {
    return "base";
  }
}

class Person extends Base {
  constructor(name) {
    super();
    this.name = name;
  }

  hello(x) {
    return `hello ${this.name}:${x}`;
  }
}

(function test_java_lang_class_reflection() {
  const { Class } = lang;

  const p = new Person("Alice");
  const c = Class.of(p);

  eq(c.getName(), "Person", "Class.getName");

  const sc = c.getSuperclass();
  assert(sc !== null, "getSuperclass not null");
  eq(sc.getName(), "Base", "getSuperclass name");

  const mHello = c.getMethod("hello");
  assert(mHello !== null, "getMethod(hello)");
  eq(mHello.getParameterCount(), 1, "Method.getParameterCount");
  eq(mHello.invoke(p, ["X"]), "hello Alice:X", "Method.invoke");

  const mBase = c.getMethod("baseMethod");
  assert(mBase !== null, "inherited method");
  eq(mBase.invoke(p, []), "base", "inherited invoke");

  const fName = c.getField("name");
  assert(fName !== null, "getField(name)");
  eq(fName.getType(), "string", "Field.getType");
  eq(fName.get(p), "Alice", "Field.get");
  fName.set(p, "Bob");
  eq(p.name, "Bob", "Field.set");

  const inst = Class.of(Person).newInstance("Carol");
  eq(inst instanceof Person, true, "newInstance instanceof");
  eq(inst.name, "Carol", "newInstance sets field");

  assert(Class.of(Person).isInstance(p) === true, "Class.isInstance");
  assert(Class.of(Base).isAssignableFrom(Class.of(Person)) === true, "Class.isAssignableFrom superclass");

  Person.__interfaces = ["Serializable", { name: "Runnable" }];
  const ifs = Class.of(Person).getInterfaces();
  eq(Array.isArray(ifs), true, "Class.getInterfaces returns array");
  eq(ifs.length, 2, "Class.getInterfaces length");
  eq(ifs[0].name, "Serializable", "Class.getInterfaces[0]");
  eq(ifs[1].name, "Runnable", "Class.getInterfaces[1]");

  function IS() {}
  IS.__interfaces = ["Serializable"];
  assert(Class.of(IS).isAssignableFrom(Class.of(Person)) === true, "Class.isAssignableFrom interface satisfied");

  function IR() {}
  IR.__interfaces = ["Runnable"];
  assert(Class.of(IR).isAssignableFrom(Class.of(Person)) === true, "Class.isAssignableFrom interface satisfied 2");

  function ISR() {}
  ISR.__interfaces = ["Serializable", "Runnable"];
  assert(Class.of(ISR).isAssignableFrom(Class.of(Person)) === true, "Class.isAssignableFrom interface satisfied 3");

  function IX() {}
  IX.__interfaces = ["MissingInterface"];
  assert(Class.of(IX).isAssignableFrom(Class.of(Person)) === false, "Class.isAssignableFrom interface missing");
})();

console.log("java_reflection_test.js: OK");

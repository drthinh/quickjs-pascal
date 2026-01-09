export class Object {
  constructor() {}
  equals(other) { return this === other; }
  hashCode() { return 0; }
  toString() { return "[object java.lang.Object]"; }
}

export default Object;

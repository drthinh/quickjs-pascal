export class Optional {
  constructor(hasValue, value) {
    this._hasValue = !!hasValue;
    this._value = value;
    Object.freeze(this);
  }

  static of(value) {
    if (value === null || value === undefined) {
      throw new TypeError("Optional.of: value is null/undefined");
    }
    return new Optional(true, value);
  }

  static ofNullable(value) {
    return value === null || value === undefined ? Optional.empty() : new Optional(true, value);
  }

  static empty() {
    return EMPTY_OPTIONAL;
  }

  static from(fn) {
    return Optional.ofNullable(fn());
  }

  isPresent() {
    return this._hasValue;
  }

  isEmpty() {
    return !this._hasValue;
  }

  get() {
    if (!this._hasValue) throw new Error("Optional.get: no value present");
    return this._value;
  }

  orElse(other) {
    return this._hasValue ? this._value : other;
  }

  orElseGet(supplier) {
    if (this._hasValue) return this._value;
    if (typeof supplier !== "function") throw new TypeError("Optional.orElseGet: supplier must be a function");
    return supplier();
  }

  orElseThrow(errorFactory) {
    if (this._hasValue) return this._value;
    if (errorFactory === void 0) throw new Error("Optional.orElseThrow: no value present");
    if (typeof errorFactory !== "function") throw new TypeError("Optional.orElseThrow: errorFactory must be a function");
    throw errorFactory();
  }

  ifPresent(consumer) {
    if (!this._hasValue) return;
    if (typeof consumer !== "function") throw new TypeError("Optional.ifPresent: consumer must be a function");
    consumer(this._value);
  }

  map(mapper) {
    if (typeof mapper !== "function") throw new TypeError("Optional.map: mapper must be a function");
    return this._hasValue ? Optional.ofNullable(mapper(this._value)) : this;
  }

  flatMap(mapper) {
    if (typeof mapper !== "function") throw new TypeError("Optional.flatMap: mapper must be a function");
    if (!this._hasValue) return this;
    const out = mapper(this._value);
    if (!(out instanceof Optional)) {
      throw new TypeError("Optional.flatMap: mapper must return Optional");
    }
    return out;
  }

  filter(predicate) {
    if (typeof predicate !== "function") throw new TypeError("Optional.filter: predicate must be a function");
    if (!this._hasValue) return this;
    return predicate(this._value) ? this : Optional.empty();
  }

  toString() {
    return this._hasValue ? `Optional(${String(this._value)})` : "Optional.empty";
  }
}

const EMPTY_OPTIONAL = new Optional(false, undefined);
Object.freeze(EMPTY_OPTIONAL);

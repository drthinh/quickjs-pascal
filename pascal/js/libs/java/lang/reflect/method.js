export class Method {
  constructor(declaringClass, name, fn, isStatic) {
    this._declaringClass = declaringClass;
    this._name = name;
    this._fn = fn;
    this._isStatic = !!isStatic;
  }

  getName() {
    return this._name;
  }

  getParameterCount() {
    const fn = this._fn;
    if (typeof fn !== "function") return 0;
    return fn.length >>> 0;
  }

  getDeclaringClass() {
    return this._declaringClass;
  }

  isStatic() {
    return this._isStatic;
  }

  invoke(target, args) {
    let argv;
    if (arguments.length === 2 && Array.isArray(args)) {
      argv = args;
    } else {
      argv = Array.prototype.slice.call(arguments, 1);
    }

    if (this._isStatic) {
      return this._fn.apply(null, argv);
    }
    return this._fn.apply(target, argv);
  }
}

export default Method;

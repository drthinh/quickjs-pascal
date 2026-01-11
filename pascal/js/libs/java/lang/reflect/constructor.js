export class Constructor {
  constructor(declaringClass, ctorFn) {
    this._declaringClass = declaringClass;
    this._ctorFn = ctorFn;
  }

  getName() {
    return this._declaringClass ? this._declaringClass.getName() : "(anonymous)";
  }

  getDeclaringClass() {
    return this._declaringClass;
  }

  newInstance(args) {
    let argv;
    if (arguments.length === 1 && Array.isArray(args)) {
      argv = args;
    } else {
      argv = Array.prototype.slice.call(arguments, 0);
    }
    return Reflect.construct(this._ctorFn, argv);
  }
}

export default Constructor;

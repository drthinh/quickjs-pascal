const _M = globalThis.Math;

export const Math = Object.freeze({
  E: _M.E,
  PI: _M.PI,
  abs(x) { return _M.abs(Number(x)); },
  max(a, b) { return _M.max(Number(a), Number(b)); },
  min(a, b) { return _M.min(Number(a), Number(b)); },
  floor(x) { return _M.floor(Number(x)); },
  ceil(x) { return _M.ceil(Number(x)); },
  round(x) { return _M.round(Number(x)); },
  random() { return _M.random(); },
  sqrt(x) { return _M.sqrt(Number(x)); },
  pow(a, b) { return _M.pow(Number(a), Number(b)); },
  sin(x) { return _M.sin(Number(x)); },
  cos(x) { return _M.cos(Number(x)); },
  tan(x) { return _M.tan(Number(x)); },
  log(x) { return _M.log(Number(x)); },
  exp(x) { return _M.exp(Number(x)); },
});

export default Math;

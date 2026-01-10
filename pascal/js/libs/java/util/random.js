function _toSeed48(seed) {
  let s;
  if (typeof seed === "bigint") s = seed;
  else if (typeof seed === "number") {
    if (!Number.isFinite(seed)) throw new TypeError("Random(seed): seed must be finite");
    s = BigInt(Math.trunc(seed));
  } else if (seed === void 0) {
    // Similar to Java: default uses current time.
    s = BigInt(Date.now());
  } else {
    throw new TypeError("Random(seed): seed must be number|bigint");
  }

  // Java Random uses: (seed ^ multiplier) & mask
  const MULT = 0x5DEECE66Dn;
  const MASK = (1n << 48n) - 1n;
  return (s ^ MULT) & MASK;
}

export class Random {
  constructor(seed) {
    this._seed = _toSeed48(seed);
  }

  setSeed(seed) {
    this._seed = _toSeed48(seed);
  }

  next(bits) {
    const b = Number(bits);
    if (!Number.isInteger(b) || b <= 0 || b > 32) throw new RangeError("Random.next(bits): bits must be 1..32");

    const MULT = 0x5DEECE66Dn;
    const ADD = 0xBn;
    const MASK = (1n << 48n) - 1n;

    this._seed = (this._seed * MULT + ADD) & MASK;
    const v = this._seed >> (48n - BigInt(b));
    return Number(v);
  }

  nextInt(bound) {
    if (arguments.length === 0) {
      // full 32-bit signed
      const x = this.next(32) | 0;
      return x;
    }

    const n = Number(bound);
    if (!Number.isInteger(n) || n <= 0) throw new RangeError("Random.nextInt(bound): bound must be positive integer");

    // Java algorithm to avoid modulo bias.
    if ((n & -n) === n) {
      // power of two
      return (n * this.next(31)) >> 31;
    }

    let bits, val;
    do {
      bits = this.next(31);
      val = bits % n;
    } while (bits - val + (n - 1) < 0);

    return val;
  }

  nextLong() {
    // 64-bit signed via two 32-bit chunks.
    const hi = BigInt(this.next(32));
    const lo = BigInt(this.next(32));
    const u64 = (hi << 32n) | lo;

    // Convert unsigned 64 -> signed 64.
    if (u64 & (1n << 63n)) return u64 - (1n << 64n);
    return u64;
  }

  nextBoolean() {
    return this.next(1) !== 0;
  }

  nextDouble() {
    // Java: (((long)next(26) << 27) + next(27)) / (double)(1L << 53)
    const a = BigInt(this.next(26));
    const b = BigInt(this.next(27));
    const n = (a << 27n) + b;
    return Number(n) / 9007199254740992; // 2^53
  }

  nextBytes(bytes) {
    if (!(bytes instanceof Uint8Array)) throw new TypeError("Random.nextBytes(bytes): bytes must be Uint8Array");

    for (let i = 0; i < bytes.length; ) {
      let rnd = this.nextInt();
      for (let n = Math.min(bytes.length - i, 4); n-- > 0; rnd >>= 8) {
        bytes[i++] = rnd & 0xff;
      }
    }
  }
}

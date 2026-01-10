export class Character {
  constructor(ch) {
    const s = String(ch);
    this._ch = s.length ? s[0] : "\0";
  }

  charValue() {
    return this._ch;
  }

  toString() {
    return this._ch;
  }

  valueOf() {
    return this._ch;
  }

  static isDigit(ch) {
    return /^[0-9]$/.test(String(ch).slice(0, 1));
  }

  static isLetter(ch) {
    return /^\p{L}$/u.test(String(ch).slice(0, 1));
  }

  static toLowerCase(ch) {
    return String(ch).slice(0, 1).toLowerCase();
  }

  static toUpperCase(ch) {
    return String(ch).slice(0, 1).toUpperCase();
  }

  static codePointAt(seq, index) {
    const s = String(seq);
    const i = Number(index) | 0;
    return s.codePointAt(i);
  }
}

export default Character;

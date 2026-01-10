import { IllegalArgumentException } from "qjsp:java/lang/illegalargumentexception.js";

export class NumberFormatException extends IllegalArgumentException {
  constructor(message, cause) {
    super(message, cause);
    this.name = "NumberFormatException";
  }
}

export default NumberFormatException;

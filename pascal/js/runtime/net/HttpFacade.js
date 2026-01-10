import * as http from "qjsp:net/http.js";

export class Http {
  static request(method, url, options) {
    return http.request(method, url, options);
  }

  static get(url, options) {
    return http.get(url, options);
  }

  static post(url, body, options) {
    return http.post(url, body, options);
  }

  static getText(url, options) {
    return http.getText(url, options);
  }

  static getJson(url, options) {
    return http.getJson(url, options);
  }

  static postJson(url, obj, options) {
    return http.postJson(url, obj, options);
  }
}

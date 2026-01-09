export function deferred() {
  /** @type {(v:any)=>void} */
  let resolve;
  /** @type {(e:any)=>void} */
  let reject;

  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });

  return { promise, resolve, reject };
}

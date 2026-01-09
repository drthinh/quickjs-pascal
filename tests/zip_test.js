import * as zip from 'qjs:zip';
import * as std from 'qjs:std';

function assert(cond, msg) {
  if (!cond) throw new Error(msg || 'assert failed');
}

const payload = 'hello from zip\n';
const zipBuf = zip.create([
  { name: 'hello.txt', data: payload },
  { name: 'dir/', data: '' },
  { name: 'dir/nested.txt', data: 'nested\n' },
]);

const za = zip.open(zipBuf);
const n = za.numFiles();
assert(n > 0, 'zip should contain at least one entry');

const entries = za.list();
assert(entries.length === n, 'list() length mismatch');

const first = entries[0];
assert(typeof first.name === 'string' && first.name.length > 0, 'entry name');

const st = za.stat('hello.txt');
assert(st.name === 'hello.txt', 'stat name mismatch');

const data = za.read('hello.txt');
assert(data instanceof ArrayBuffer, 'read() must return ArrayBuffer');
assert(data.byteLength === st.uncompressedSize, 'size mismatch');

const text = new TextDecoder().decode(new Uint8Array(data));
assert(text === payload, 'content mismatch');

za.close();

std.out.puts('zip_test OK\n');

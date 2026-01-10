import * as zip from 'qjsp:zip';
import * as std from 'qjs:std';

std.out.puts('[zip_test] start\n');

function assert(cond, msg) {
  if (!cond) throw new Error(msg || 'assert failed');
}

const payload = 'hello from zip\n';

std.out.puts('[zip_test] creating zip...\n');
const zipBuf = zip.create([
  { name: 'hello.txt', data: payload },
  { name: 'dir/', data: '' },
  { name: 'dir/nested.txt', data: 'nested\n' },
]);

std.out.puts('[zip_test] zip created, size=' + zipBuf.byteLength + '\n');

std.out.puts('[zip_test] opening zip...\n');
const za = zip.open(zipBuf);

std.out.puts('[zip_test] opened zip\n');
const n = za.numFiles();

std.out.puts('[zip_test] numFiles=' + n + '\n');
assert(n > 0, 'zip should contain at least one entry');

std.out.puts('[zip_test] listing...\n');
const entries = za.list();

std.out.puts('[zip_test] list ok, entries=' + entries.length + '\n');
assert(entries.length === n, 'list() length mismatch');

const first = entries[0];
assert(typeof first.name === 'string' && first.name.length > 0, 'entry name');

std.out.puts('[zip_test] stat hello.txt...\n');
const st = za.stat('hello.txt');

std.out.puts('[zip_test] stat ok, uncompressedSize=' + st.uncompressedSize + '\n');
assert(st.name === 'hello.txt', 'stat name mismatch');

std.out.puts('[zip_test] read hello.txt...\n');
const data = za.read('hello.txt');

std.out.puts('[zip_test] read ok, byteLength=' + data.byteLength + '\n');
assert(data instanceof ArrayBuffer, 'read() must return ArrayBuffer');
assert(data.byteLength === st.uncompressedSize, 'size mismatch');

const text = new TextDecoder().decode(new Uint8Array(data));

std.out.puts('[zip_test] decoded\n');
assert(text === payload, 'content mismatch');

std.out.puts('[zip_test] close...\n');
za.close();

std.out.puts('[zip_test] closed\n');

std.out.puts('zip_test OK\n');

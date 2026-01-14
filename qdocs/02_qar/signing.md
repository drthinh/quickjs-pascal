# QAR Signing (Ed25519)

## Overview

**VI:** QAR có thể nhúng chữ ký Ed25519 vào `manifest.json` (manifest nội bộ trong file `.qar`). Chữ ký được dùng để xác thực tính toàn vẹn và nguồn gốc (pubkey) của QAR khi runtime load.

**EN:** QAR can embed an Ed25519 signature into the internal `manifest.json`. The signature is used to validate integrity and origin (pubkey) when loading a QAR at runtime.

Trong repo này, signing được implement bằng Pascal:

- `pascal/std/crypto/qcrypto_ed25519_sign.pas`
- `pascal/std/crypto/qcrypto_ed25519_keyload.pas`
- tích hợp tại `pascal/std/qar/qar.pas`

## Key formats supported

QAR signing hỗ trợ **private key** theo 2 dạng:

### 1) raw64 (binary)

- **64 bytes**: `seed32 || pubkey32`
- `seed32` là seed Ed25519 (32 bytes)
- `pubkey32` là public key Ed25519 (32 bytes)

Đây là format phù hợp nhất cho tool nội bộ vì load nhanh và rõ ràng.

### 2) PEM PKCS#8 (Ed25519)

- File text PEM:
  - `-----BEGIN PRIVATE KEY-----`
  - base64 DER
  - `-----END PRIVATE KEY-----`
- Kiểu key là **PKCS#8 PrivateKeyInfo** (RFC 8410) với **OID Ed25519**.

## Generate keys in qjsp

Tạo key bằng `qjsp` REPL:

```text
js> .qar keygen mykey
Ed25519 key generated:
  raw64: mykey.bin
  pem:   mykey.pem
```

Chỉ định trực tiếp PEM (không cần `<out>`):

```text
js> .qar keygen --pem hello.pem
```

Mặc định raw64 sẽ được tạo cùng basename:

- `hello.pem`
- `hello.bin`

## Sign QAR at build/rebuild time

### Sign when building

```text
js> .qar build out.qar src/ --sign-key mykey.pem
```

### Sign when rebuilding

```text
js> .qar rebuild in.qar out2.qar --sign-key mykey.bin
```

## Verify / Inspect

### Inspect signature info

```text
js> .qar inspect out.qar
```

Khi QAR có chữ ký, manifest sẽ chứa:

- `sig_payload_b64`
- `sig.alg` (dự kiến: `ed25519`)
- `sig.pubkey` (base64)
- `sig.sig` (base64)

### Runtime verification mode

`qjsp` có thể kiểm soát mức verify khi load QAR (CLI flag):

- `--verify off`
- `--verify warn`
- `--verify strict`

## Notes / Security

- **Private key phải được bảo vệ**: không commit lên git.
- PEM/RAW64 chỉ là container format; bảo mật phụ thuộc vào cách bạn lưu trữ file key.
- Nếu đổi `built_at`/manifest payload thì signature sẽ khác. QAR build đã cố gắng tạo payload deterministic cho signing.

## Troubleshooting

- Nếu `.qar keygen --pem hello.pem` tạo ra file tên sai: hãy update `qjsp` lên version mới nhất trong repo (đã fix parser).
- Nếu `--sign-key` báo lỗi load key: kiểm tra file có đúng raw64 (64 bytes) hoặc PEM PKCS#8 Ed25519.

## JavaScript helper APIs (options object)

Ngoài REPL command `.qar ...`, `qjsp` còn expose helper functions trực tiếp trong JS (global) để bạn dùng trong console / script.

### 1) Keygen

```javascript
// Create key pair files. Provide at least one of { pem, raw64 }.
// If only pem is provided, raw64 defaults to same basename + ".bin".
// If only raw64 is provided, pem defaults to same basename + ".pem".
const k = QarKeygen({ pem: "hello.pem" });
// => { raw64: "hello.bin", pem: "hello.pem" }
```

### 2) Build + sign

```javascript
BuildQar("out.qar", ["src/"], {
  signKey: "hello.pem",
  createdBy: "me",
  tool: "qjsp",
  meta: { env: "dev" }
});
```

### 3) Rebuild + sign

```javascript
RebuildQar("in.qar", "out2.qar", { signKey: "hello.bin" });
```

### Options fields

- `signKey` (string): path tới private key file (raw64 hoặc PEM PKCS#8)
- `createdBy` (string): ghi vào manifest `created_by`
- `tool` (string): ghi vào manifest `tool`
- `meta` (object): `{k: v}` → được convert thành list `k=v` trong manifest

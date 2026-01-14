# stdjs events

## Mục tiêu

`qjsp:events` cung cấp `EventEmitter` theo phong cách Node-lite.

Trong `stdjs/events/` có 2 lớp module khác nhau:

- **Implementation module**: file chứa code thật (vd: `EventEmitter.js`).
- **Aggregator / barrel module**: file gom export để import ngắn (vd: `index.js`).

## Files

- `qjsp:events/EventEmitter.js`
  - Chứa implementation của `class EventEmitter`.
  - Export:
    - `export class EventEmitter { ... }`
    - `export default EventEmitter`

- `qjsp:events/index.js`
  - Là “barrel” để re-export cho import ngắn.
  - Nội dung hiện tại:

```js
export { EventEmitter } from "qjsp:events/EventEmitter.js";
export { default } from "qjsp:events/EventEmitter.js";
```

## Import (khuyến nghị)

### Import ngắn (qua `index.js`)

```js
import { EventEmitter } from "qjsp:events";
```

Dạng này ổn định hơn khi bạn muốn “public API” của namespace `events`.

### Import thẳng implementation

```js
import EventEmitter from "qjsp:events/EventEmitter.js";
// hoặc
import { EventEmitter } from "qjsp:events/EventEmitter.js";
```

Dùng khi bạn muốn chỉ rõ file implementation.

## Vì sao đôi khi loader thử `events.js`?

Cơ chế resolver cho prefix `qjsp:` (trong `qjsp_module_loader`) hoạt động kiểu Node-lite:

Khi import `"qjsp:events"`, loader sẽ thử lần lượt:

1. `stdjs/events`
2. `stdjs/events.js`
3. `stdjs/events/index.js`

File tồn tại thực tế là `stdjs/events/index.js`, nên bước (3) sẽ thành công.

Nếu bước (2) fail thì runtime có thể tạo `ReferenceError` (không tìm thấy module). Vì vậy loader cần clear exception giữa các lần thử (đã được xử lý trong loader) để tránh việc thông báo lỗi bị in ra muộn khi chương trình kết thúc.

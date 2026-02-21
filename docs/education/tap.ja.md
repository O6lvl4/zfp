# tap — サイドエフェクトの注入

```zig
const tap = @import("zfp").tap;
```

## これは何？

`tap` は、ログ・トレース・アサーションといったサイドエフェクトを持つ関数を、
パイプラインの値の流れを壊さずに差し込むためのモジュールです。

値が入り、サイドエフェクトが実行され、同じ値がそのまま出てきます。

```
tap.run(x, f)  ≡  f(x); x
```

---

## 問題

パイプラインをデバッグするには、現状では分解するしかありません：

```zig
// Before — ログのためにパイプラインを分断
const parsed = parse(raw);
std.debug.print("parsed: {}\n", .{parsed});
const validated = validate(parsed);
std.debug.print("validated: {}\n", .{validated});
const result = transform(validated);
```

`tap` を使えばパイプラインをそのまま保てます：

```zig
const tap  = @import("zfp").tap;
const pipe = @import("zfp").pipe;

const result = pipe.run(raw, .{
    parse,
    tap.typed(ParsedData, logParsed),
    validate,
    tap.typed(ValidData, logValidated),
    transform,
});
```

---

## `tap.run` — 直接使う形

`f` をサイドエフェクトのために呼び出し、`value` をそのまま返します。

```zig
const tap = @import("zfp").tap;

const value: i32 = 42;
const same  = tap.run(value, logFn); // logFn(42) が呼ばれる
// same == 42
```

`f` の戻り値は捨てられます。サイドエフェクトだけが重要です。
`f` が `void` を返しても、何か値を返しても、どちらでも動作します。

```zig
tap.run(value, logFn)       // f が void を返す場合
tap.run(value, inspectFn)   // f が値を返す場合 — 戻り値は捨てられる
```

---

## `tap.typed` — パイプラインステップ

`pipe.run` のタプルに入れられる具体的な `fn(T) T` を返します。

```zig
const tap  = @import("zfp").tap;
const pipe = @import("zfp").pipe;

const logParsed = struct {
    fn call(x: ParsedData) void {
        std.debug.print("parse後: {}\n", .{x});
    }
}.call;

const result = pipe.run(raw, .{
    parse,
    tap.typed(ParsedData, logParsed),  // ← ここに差し込む
    validate,
    transform,
});
```

**なぜ型を明示する必要があるのか？**

`pipe.run` は実行前にすべてのステップの戻り型をコンパイル時に解決します。
そのため、各ステップは具体的な関数シグネチャを持つ必要があります。
`tap.typed(T, f)` はまさにそれを提供します：`fn(T) T`。

---

## なぜゼロコストなのか？

`tap.run` は `pub inline fn` です。コンパイラが呼び出し元に展開します。
`tap.typed` が返す関数の本体も同様にインライン化されます。

生成されるコードは以下と同一です：

```zig
logFn(value);
// value で続行
```

ラッパー構造体なし、間接参照なし、アロケーションなし。

---

## 合成の例

```zig
const tap  = @import("zfp").tap;
const pipe = @import("zfp").pipe;
const std  = @import("std");

const logRaw = struct {
    fn call(s: []const u8) void {
        std.debug.print("[raw]    {s}\n", .{s});
    }
}.call;

const logParsed = struct {
    fn call(n: i32) void {
        std.debug.print("[parsed] {d}\n", .{n});
    }
}.call;

const result = pipe.run(input, .{
    tap.typed([]const u8, logRaw),
    parseInt,
    tap.typed(i32, logParsed),
    double,
});
```

出力：

```
[raw]    "21"
[parsed] 21
```

結果：`42`

---

## 対応表

| 概念 | zfp | 内容 |
|------|-----|------|
| 値をその場で観察する | `tap.run(value, f)` | `f(value)` を呼び、`value` を返す |
| `pipe.run` の中で観察する | `tap.typed(T, f)` | `fn(T) T` のステップを返す |

---

## 参考リンク

- [Haskell Data.Function — (&)](https://hackage.haskell.org/package/base/docs/Data-Function.html)
- [Rust tap クレート](https://docs.rs/tap/latest/tap/)
- [Zig インライン関数](https://ziglang.org/documentation/master/#inline-functions)

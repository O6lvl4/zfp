# compose — 再利用可能な関数合成

## pipe と compose の違い

`pipe` は値に関数を即座に適用して結果を返します。
`compose` は後で呼び出せる**再利用可能な関数オブジェクト**を返します。

```zig
const pipe    = @import("zfp").pipe;
const compose = @import("zfp").compose;

// pipe：今すぐ適用して結果を得る
const result = pipe.pipe(3, .{ double, addOne }); // 7

// compose：再利用できる関数を作り、後で適用する
const f = compose.compose(.{ double, addOne });
const result = f.call(3); // 7
const again  = f.call(5); // 11  — 同じ変換を別の入力に
```

---

## 問題：変換タプルの繰り返し

同じパイプラインを複数箇所で使う場合、`pipe` ではタプルを繰り返す必要があります：

```zig
const a = normalize(clamp(parse(raw_a)));
const b = normalize(clamp(parse(raw_b)));
const c = normalize(clamp(parse(raw_c)));
```

`pipe` を使っても同じ問題が残ります：

```zig
const a = pipe.pipe(raw_a, .{ parse, clamp, normalize });
const b = pipe.pipe(raw_b, .{ parse, clamp, normalize }); // 繰り返し
const c = pipe.pipe(raw_c, .{ parse, clamp, normalize }); // 繰り返し
```

---

## 解決策：名前付きの再利用可能な合成

`compose` を使えば変換を一度だけ定義して名前を付けられます：

```zig
const compose = @import("zfp").compose;

const process = compose.compose(.{ parse, clamp, normalize });

const a = process.call(raw_a);
const b = process.call(raw_b);
const c = process.call(raw_c);
```

変換の定義が一箇所にまとまります。生成されるマシンコードは同一です。

---

## API

```zig
compose.compose(fns: tuple) Callable
```

- `fns` — 無名構造体（タプルリテラル）。関数を左から右の順に並べる
- 戻り値は `call` メソッドを持つ**ゼロサイズ構造体**

```zig
callable.call(value: A) ReturnType
```

- 合成された関数を `value` に適用する
- 戻り値の型はタプルの最後の関数から自動推論される

### 型として使う

`compose.Compose(fns)` で型に名前をつけることもできます：

```zig
const compose = @import("zfp").compose;

const MyFn = compose.Compose(.{ double, addOne });
// MyFn.call(3) == 7
```

---

## 型推論

型はコンパイル時に左から右へ流れます。各ステップの返り値の型が次のステップの入力型になります：

```zig
// i32 → i32 → bool
const check = compose.compose(.{ double, isPositive });
const ok: bool = check.call(3); // true  (3 → 6 → true)
const no: bool = check.call(0); // false (0 → 0 → false)
```

---

## 使用例

### 基本的な合成

```zig
const compose = @import("zfp").compose;

fn double(x: i32) i32  { return x * 2; }
fn addOne(x: i32) i32  { return x + 1; }
fn negate(x: i32) i32  { return -x; }

const f = compose.compose(.{ double, addOne, negate });
// f.call(3) → double(3)=6 → addOne(6)=7 → negate(7)=-7
```

### 型が変わる合成

```zig
const compose = @import("zfp").compose;

fn length(s: []const u8) usize { return s.len; }
fn doubled(n: usize) usize     { return n * 2; }

const f = compose.compose(.{ length, doubled });
// f.call("hello") → 5 → 10   (型: usize)
// f.call("hi")    → 2 → 4
```

### バッチ処理

```zig
const compose = @import("zfp").compose;
const std = @import("std");

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " ");
}
fn toUpperFirst(s: []const u8) u8 {
    return if (s.len > 0) std.ascii.toUpper(s[0]) else 0;
}

const firstChar = compose.compose(.{ trim, toUpperFirst });

const inputs = [_][]const u8{ "  hello", " world ", "zig " };
for (inputs) |input| {
    const c = firstChar.call(input);
    // 'H', 'W', 'Z'
    _ = c;
}
```

---

## ゼロコスト

`Compose` が返す構造体は**フィールドがない**のでサイズはゼロです。`call` はインライン展開されて：

```zig
negate(addOne(double(x)))
```

と同一のコードになります。ヒープアロケーションなし。間接参照なし。実行時コストなし。
構造体はコンパイル時の名前空間としてのみ存在します。

---

## compose と pipe の使い分け

| ユースケース | ツール |
|------------|-------|
| 一度だけの変換 | `pipe` |
| 複数箇所で同じ変換を使う | `compose` |
| 変換に名前をつけて可読性を上げる | `compose` |
| 別の関数に渡す（`.call` を参照） | `compose` |
| ループの中で繰り返し適用する | `compose`（ループ外で定義する） |

# pipe — 左から右へ関数をつなぐパイプライン

## 問題：コードを逆から読む

多くの言語では、関数を合成するとネストが深くなり、内側から外側へ読む必要があります：

```zig
const result = normalize(clamp(parse(raw)));
//                                  ^^^^ ここから読む
//                         ^^^^^
//              ^^^^^^^^^
```

実行順序は `parse → clamp → normalize` ですが、コードは右から左に読まなければなりません。
パイプラインが長くなるほどネストが深まり、可読性が低下します。

---

## 解決策：pipe

`pipe` は関数の列を値に対して**左から右へ**適用します：

```zig
const pipe = @import("zfp").pipe;

const result = pipe.pipe(raw, .{ parse, clamp, normalize });
//                             ^^^^  ^^^^^  ^^^^^^^^^
//                             第1段 第2段  第3段 ← 左から右に読める
```

実行順序とコードの読み順が一致します。ステップを追加するにはタプルに関数を追加するだけです。

---

## API

```zig
pipe.pipe(value: A, fns: tuple) ReturnType
```

- `value` — 最初の入力値
- `fns` — 無名構造体（タプルリテラル）。関数を左から右の順に並べる
- 戻り値の型は最後の関数の返り値の型

空のタプルは恒等変換：

```zig
pipe.pipe(x, .{}) // x をそのまま返す
```

---

## 型推論

型は**コンパイル時**にパイプラインを流れます。各関数の返り値の型が次の関数の入力型になります：

```zig
// i32 → i32 → bool
const positive = pipe.pipe(@as(i32, 3), .{ double, isPositive });
//                                              ^       ^
//                                         i32→i32  i32→bool
// `positive` の型は bool
```

型注釈は不要です。コンパイラが各ステップの型の整合性を検証します。

---

## 使用例

### 基本的なパイプライン

```zig
const pipe = @import("zfp").pipe;

fn double(x: i32) i32 { return x * 2; }
fn addOne(x: i32) i32 { return x + 1; }
fn negate(x: i32) i32 { return -x; }

// 3 → 6 → 7 → -7
const result = pipe.pipe(@as(i32, 3), .{ double, addOne, negate });
// result == -7
```

### 型が変わるパイプライン

```zig
const pipe = @import("zfp").pipe;

fn length(s: []const u8) usize { return s.len; }
fn doubled(n: usize) usize { return n * 2; }

// "hello" → 5 → 10
const result = pipe.pipe(@as([]const u8, "hello"), .{ length, doubled });
// result == 10、型は usize
```

### 実用例：テキスト処理

```zig
const pipe = @import("zfp").pipe;
const std = @import("std");

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " ");
}

// Before（右から左に読む必要がある）
const result = try validate(parseInt(trim(raw)));

// After（左から右に自然に読める）
const result = pipe.pipe(raw, .{ trim, parseInt, validate });
```

---

## option・result との組み合わせ

`pipe` は `option` や `result` モジュールと自然に組み合わせられます。すべて普通の関数を扱うためです：

```zig
const zfp = @import("zfp");
const pipe = zfp.pipe;
const option = zfp.option;

fn parseInt(s: []const u8) ?i32 {
    return std.fmt.parseInt(i32, s, 10) catch null;
}
fn doubleIfPositive(n: i32) ?i32 {
    return if (n > 0) n * 2 else null;
}

// option を返す関数を option.andThen でつなぎ、
// 最後に pipe で変換を追加する
const raw: ?[]const u8 = "21";
const result = option.andThen(
    option.andThen(raw, parseInt),
    doubleIfPositive,
);
// result == ?i32(42)
```

---

## ゼロコスト

`pipe` は**コンパイル時の構造体**です。関数のタプルはコンパイル時にのみ存在します。
`PipeReturn` がコンパイル時に各ステップの型を再帰的に計算します。
`applyFrom` は再帰的にインライン展開され、コンパイラは各特殊化を個別に最適化します。

生成されるマシンコードは次と同一です：

```zig
negate(addOne(double(x)))
```

間接参照なし。クロージャなし。アロケーションなし。

---

## pipe を使うべき場面

| 状況 | 推奨 |
|------|------|
| 1〜2段の変換 | 直接ネストで問題なし |
| 3段以上の変換 | `pipe` で可読性が向上する |
| 各ステップで型が変わる | `pipe` の型推論を活用 |
| 条件分岐を含む変換 | `option` / `result` と組み合わせる |
| 中間値に名前をつけたい | `const` で個別に束縛する |

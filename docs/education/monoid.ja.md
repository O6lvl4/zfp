# monoid — Semigroup / Monoid コンビネータ

```zig
const monoid = @import("zfp").monoid;
```

## これは何？

**Monoid（モノイド）** は 3 つを持つ型です：

1. **単位元 `empty`** — 何かと組み合わせても相手を変えない
2. **結合的な二項演算 `append`** — グループ化の順番を変えても結果が変わらない
3. **`concat`** — `empty` から始めてスライス全体を `append` で畳み込む

`monoid` は 6 つの名前付きモノイドをコンパイル時の名前空間として提供します。各モノイドは `empty`、`append`、`concat` を持ちます：

| 名前空間 | 単位元 | 演算 |
|---------|--------|------|
| `Sum` | `0` | `a + b` |
| `Product` | `1` | `a * b` |
| `Any` | `false` | `a or b` |
| `All` | `true` | `a and b` |
| `First` | `null` | 最初の非 null |
| `Last` | `null` | 最後の非 null |

---

## 問題

異なる「結合」のセマンティクスでスライスを畳み込むには、毎回パターンを繰り返す必要があります：

```zig
// Before — 単位元と演算を毎回書く
var total: i32 = 1;
for (items) |x| total *= x;

var any_true = false;
for (flags) |f| any_true = any_true or f;

var first: ?i32 = null;
for (opts) |o| if (first == null) { first = o; };
```

`monoid` を使えば意図が名前に現れます：

```zig
const monoid = @import("zfp").monoid;

const total     = monoid.Product.concat(&items);
const any_true  = monoid.Any.concat(&flags);
const first_val = monoid.First.concat(&opts);
```

---

## `Sum` — 数値加算

**Haskell**: `newtype Sum a = Sum { getSum :: a }`

```zig
const monoid = @import("zfp").monoid;

monoid.Sum.empty(i32)                 // → 0
monoid.Sum.append(@as(i32, 3), 4)     // → 7
monoid.Sum.concat(&.{ 1, 2, 3, 4 })  // → 10
monoid.Sum.concat(&([_]i32{})[0..])  // → 0（空）
```

`i32`、`u64`、`f32` など任意の数値型に対して動作します。

---

## `Product` — 数値乗算

**Haskell**: `newtype Product a = Product { getProduct :: a }`

```zig
const monoid = @import("zfp").monoid;

monoid.Product.empty(i32)                 // → 1
monoid.Product.append(@as(i32, 3), 4)     // → 12
monoid.Product.concat(&.{ 1, 2, 3, 4 })  // → 24
monoid.Product.concat(&([_]i32{})[0..])  // → 1（空）
```

---

## `Any` — 論理和（OR）

**Haskell**: `newtype Any = Any { getAny :: Bool }`

```zig
const monoid = @import("zfp").monoid;

monoid.Any.empty()                           // → false
monoid.Any.append(false, true)               // → true
monoid.Any.concat(&.{ false, false, true })  // → true
monoid.Any.concat(&.{ false, false, false }) // → false
monoid.Any.concat(&([_]bool{})[0..])         // → false（空）
```

`concat` は短絡評価します — 最初の `true` で停止します。

---

## `All` — 論理積（AND）

**Haskell**: `newtype All = All { getAll :: Bool }`

```zig
const monoid = @import("zfp").monoid;

monoid.All.empty()                           // → true
monoid.All.append(true, false)               // → false
monoid.All.concat(&.{ true, true, true })    // → true
monoid.All.concat(&.{ true, false, true })   // → false
monoid.All.concat(&([_]bool{})[0..])         // → true（空は真）
```

`concat` は短絡評価します — 最初の `false` で停止します。

---

## `First` — 最初の非 null オプショナル

**Haskell**: `newtype First a = First { getFirst :: Maybe a }`

```zig
const monoid = @import("zfp").monoid;

monoid.First.empty(i32)                               // → null
monoid.First.append(@as(?i32, 1), @as(?i32, 2))      // → 1
monoid.First.append(@as(?i32, null), @as(?i32, 2))   // → 2
monoid.First.concat(&.{ @as(?i32, null), 2, 3 })     // → 2
monoid.First.concat(&([_]?i32{})[0..])               // → null（空）
```

---

## `Last` — 最後の非 null オプショナル

**Haskell**: `newtype Last a = Last { getLast :: Maybe a }`

```zig
const monoid = @import("zfp").monoid;

monoid.Last.empty(i32)                                // → null
monoid.Last.append(@as(?i32, 1), @as(?i32, 2))       // → 2
monoid.Last.append(@as(?i32, 1), @as(?i32, null))    // → 1
monoid.Last.concat(&.{ @as(?i32, 1), 2, null })      // → 2
monoid.Last.concat(&([_]?i32{})[0..])                // → null（空）
```

---

## モノイド則

すべてのモノイドはこれらの法則を満たします。`zfp` はテストで検証しています：

```
append(empty, x)        ≡  x         （左単位元）
append(x, empty)        ≡  x         （右単位元）
append(append(x,y), z)  ≡  append(x, append(y,z))  （結合律）
```

`concat(items) ≡ fold(items, empty, append)` — 空でも非空でも成立します。

---

## なぜゼロコストなのか？

すべての関数は `pub inline fn` です。各関数は最もシンプルな式にコンパイルされます：

```zig
// Sum.concat は以下にコンパイルされます：
var acc: T = 0;
for (items) |item| acc += item;

// Any.concat は以下にコンパイルされます：
for (items) |item| if (item) return true;
return false;
```

仮想ディスパッチなし。実行時型情報なし。アロケーションなし。

---

## 合成の例

バッチ処理結果を集計 — 成功数のカウントと最初のエラーの取得：

```zig
const monoid = @import("zfp").monoid;
const slice  = @import("zfp").slice;

const results = [_]?[]const u8{
    null,        // 成功（エラーメッセージなし）
    "タイムアウト",  // 失敗
    null,        // 成功
    "未検出",     // 失敗
};

// 成功数（null = 成功）
const successes = slice.count(&results, struct {
    fn call(r: ?[]const u8) bool { return r == null; }
}.call);
// → 2

// 最初のエラーメッセージ
const first_error = monoid.First.concat(&results);
// → @as(?[]const u8, "タイムアウト")

// 最後のエラーメッセージ
const last_error = monoid.Last.concat(&results);
// → @as(?[]const u8, "未検出")
```

---

## 対応表

| Haskell | zfp | 単位元 | 演算 |
|---------|-----|--------|------|
| `Sum` | `monoid.Sum` | `Sum.empty(T)` = `0` | `Sum.append(a, b)` = `a + b` |
| `Product` | `monoid.Product` | `Product.empty(T)` = `1` | `Product.append(a, b)` = `a * b` |
| `Any` | `monoid.Any` | `Any.empty()` = `false` | `Any.append(a, b)` = `a or b` |
| `All` | `monoid.All` | `All.empty()` = `true` | `All.append(a, b)` = `a and b` |
| `First` | `monoid.First` | `First.empty(T)` = `null` | `First.append(a, b)` = `a orelse b` |
| `Last` | `monoid.Last` | `Last.empty(T)` = `null` | `Last.append(a, b)` = `b orelse a` |

---

## 参考リンク

- [Haskell Data.Monoid](https://hackage.haskell.org/package/base/docs/Data-Monoid.html)
- [Haskell Data.Semigroup](https://hackage.haskell.org/package/base/docs/Data-Semigroup.html)
- [Monoids — Typeclassopedia](https://wiki.haskell.org/Typeclassopedia#Monoid)
- [Zig comptime](https://ziglang.org/documentation/master/#comptime)

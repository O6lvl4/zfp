# slice — スライスへの Foldable 操作

```zig
const slice = @import("zfp").slice;
```

## これは何？

`slice` は Haskell の `Foldable` 型クラスを Zig のスライス（`[]T` / `[]const T`）に持ち込むモジュールです。

すべての関数は同等の手書き `for` ループにコンパイルされます。アロケーションなし、ボクシングなし、抽象化のオーバーヘッドなし — よくあるスライス操作のためのゼロコストな語彙です。

---

## 問題

`slice` なしでは、すべての走査が手作りの `for` ループになります：

```zig
// Before — 操作ごとにボイラープレート
var total: i32 = 0;
for (scores) |s| total += s;

var passing: usize = 0;
for (scores) |s| if (s >= 50) { passing += 1; };

var best: ?i32 = null;
for (scores) |s| if (best == null or s > best.?) { best = s; };
```

`slice` を使えば意図がコードの表面に出ます：

```zig
const slice = @import("zfp").slice;

const total   = slice.sum(&scores);
const passing = slice.count(&scores, struct { fn call(x: i32) bool { return x >= 50; } }.call);
const best    = slice.max(&scores);
```

---

## `fold` — 基本操作

**Haskell**: `foldl :: (b -> a -> b) -> b -> [a] -> b`

左畳み込み。他のすべてのコンビネータは fold で表現できます。

```zig
const slice = @import("zfp").slice;

// 合計
slice.fold(&items, @as(i32, 0), struct {
    fn call(acc: i32, x: i32) i32 { return acc + x; }
}.call)
// → 10  (items = [1, 2, 3, 4] の場合)

// 積
slice.fold(&items, @as(i32, 1), struct {
    fn call(acc: i32, x: i32) i32 { return acc * x; }
}.call)
// → 24  (items = [1, 2, 3, 4] の場合)
```

空スライスに対しては `init` を返します。

---

## `all` / `any` — 述語

**Haskell**: `all`, `any`

```zig
const slice = @import("zfp").slice;

const isPositive = struct { fn call(x: i32) bool { return x > 0; } }.call;

slice.all(&.{ 1, 2, 3 }, isPositive)   // → true
slice.all(&.{ 1, -2, 3 }, isPositive)  // → false （短絡評価）
slice.all(&.{}, isPositive)             // → true  （空は真）

slice.any(&.{ -1, 2, -3 }, isPositive)  // → true  （短絡評価）
slice.any(&.{ -1, -2, -3 }, isPositive) // → false
slice.any(&.{}, isPositive)             // → false
```

どちらも短絡評価します。`all` は最初の `false` で返り、`any` は最初の `true` で返ります。

---

## `find` — 最初のマッチ

**Haskell**: `find :: Foldable t => (a -> Bool) -> t a -> Maybe a`

```zig
const slice = @import("zfp").slice;

slice.find(&.{ -1, -2, 3, 4 }, isPositive)  // → @as(?i32, 3)
slice.find(&.{ -1, -2, -3 }, isPositive)    // → null
```

`?T` を返します — マッチするものがなければ `null`。

---

## `findIndex` — 最初のマッチのインデックス

```zig
const slice = @import("zfp").slice;

slice.findIndex(&.{ -1, -2, 3, 4 }, isPositive)  // → @as(?usize, 2)
slice.findIndex(&.{ -1, -2, -3 }, isPositive)    // → null
```

`?usize` を返します — マッチするものがなければ `null`。

---

## `count` — マッチ数のカウント

**Haskell**: `length . filter p`

```zig
const slice = @import("zfp").slice;

slice.count(&.{ 1, -2, 3, -4, 5 }, isPositive)  // → 3
slice.count(&.{ -1, -2, -3 }, isPositive)        // → 0
slice.count(&.{}, isPositive)                    // → 0
```

---

## `forEach` — サイドエフェクト

**Haskell**: `traverse_`

各要素に `f` を呼び出し、サイドエフェクトを実行します。戻り値はありません。

```zig
const slice = @import("zfp").slice;

slice.forEach(&items, struct {
    fn call(x: i32) void {
        std.debug.print("{d}\n", .{x});
    }
}.call);
```

値を累積したい場合は `fold` を、サイドエフェクトだけが必要な場合は `forEach` を使います。

---

## `sum` — 全要素の合計

**Haskell**: `sum :: (Foldable t, Num a) => t a -> a`

`i32`、`u64`、`f32` など任意の数値型に対して動作します。

```zig
const slice = @import("zfp").slice;

slice.sum(&.{ 1, 2, 3, 4, 5 })    // → @as(i32, 15)
slice.sum(&.{ 1.0, 2.5, 0.5 })    // → @as(f32, 4.0)
slice.sum(&([_]i32{})[0..])        // → @as(i32, 0)  （空 → 0）
```

---

## `min` / `max` — 最小値・最大値

**Haskell**: `minimum`, `maximum`

```zig
const slice = @import("zfp").slice;

slice.min(&.{ 3, 1, 4, 1, 5, 9 })  // → @as(?i32, 1)
slice.max(&.{ 3, 1, 4, 1, 5, 9 })  // → @as(?i32, 9)

slice.min(&([_]i32{})[0..])         // → null  （空スライス）
slice.max(&([_]i32{})[0..])         // → null  （空スライス）
```

`?T` を返します — 空スライスは `null`（合理的なデフォルト値が存在しないため）。

---

## なぜゼロコストなのか？

10 個の関数はすべて `pub inline fn` で `anytype` パラメータを持ちます。

それぞれ、手書きすれば Zig のオプティマイザが生成するものと同じ最小のループにコンパイルされます：

```zig
// slice.count(items, predicate) は以下にコンパイルされます：
var n: usize = 0;
for (items) |item| {
    if (predicate(item)) n += 1;
}
```

仮想ディスパッチなし。アロケーションなし。中間コレクションなし。

要素型はコンパイル時に `std.meta.Elem` で取得します — これにより実行時型情報は不要で、`[]T`、`[]const T`、`*[N]T`（配列へのポインタ）のいずれにも対応します。

---

## 合成の例

```zig
const slice  = @import("zfp").slice;
const option = @import("zfp").option;

const scores = [_]i32{ 42, 7, 98, 13, 55, 76 };

// 合格スコア（50以上）は何個？
const isPassing = struct { fn call(x: i32) bool { return x >= 50; } }.call;
const passing = slice.count(&scores, isPassing);
// → 3

// 最高スコア
const best = slice.max(&scores);
// → @as(?i32, 98)

// 合格スコアの合計
const total = slice.fold(&scores, @as(i32, 0), struct {
    fn call(acc: i32, x: i32) i32 {
        return acc + if (x >= 50) x else 0;
    }
}.call);
// → 229

// option と組み合わせて: 90 点超の最初のスコアを 2 倍に
const result = option.map(
    slice.find(&scores, struct { fn call(x: i32) bool { return x > 90; } }.call),
    struct { fn call(x: i32) i32 { return x * 2; } }.call,
);
// → @as(?i32, 196)
```

---

## 対応表

| Haskell | zfp | 内容 |
|---------|-----|------|
| `foldl f z xs` | `slice.fold(xs, z, f)` | 左畳み込み |
| `all p xs` | `slice.all(xs, p)` | 全要素がマッチ |
| `any p xs` | `slice.any(xs, p)` | いずれかがマッチ |
| `find p xs` | `slice.find(xs, p)` | 最初のマッチ（`?T`） |
| `findIndex p xs` | `slice.findIndex(xs, p)` | 最初のマッチのインデックス（`?usize`） |
| `length (filter p xs)` | `slice.count(xs, p)` | マッチ数 |
| `mapM_ f xs` | `slice.forEach(xs, f)` | サイドエフェクトのみ |
| `sum xs` | `slice.sum(xs)` | 全要素の合計 |
| `minimum xs` | `slice.min(xs)` | 最小値（`?T`） |
| `maximum xs` | `slice.max(xs)` | 最大値（`?T`） |

---

## 参考リンク

- [Haskell Data.Foldable](https://hackage.haskell.org/package/base/docs/Data-Foldable.html)
- [Rust Iterator](https://doc.rust-lang.org/std/iter/trait.Iterator.html) — 同様のコンビネータ
- [Zig for ループ](https://ziglang.org/documentation/master/#for)
- [std.meta.Elem](https://ziglang.org/documentation/master/std/#std.meta.Elem)

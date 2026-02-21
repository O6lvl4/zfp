# arrow — Arrow コンビネータ

```zig
const arrow = @import("zfp").arrow;
```

## これは何？

`arrow` は、**ペア**（2要素タプル）を扱うコンビネータ群です。
Haskell の `Arrow` 型クラスにインスパイアされています。

`pipe` や `compose` が単一の値を関数の連鎖に通すのに対し、
`arrow` はペアの**両側を独立に変換**したり、単一の値を2本のパスに分岐させたりできます。

---

## 問題

`arrow` なしでペアの変換を行うと、展開と再梱包が必要になります：

```zig
// Before — 冗長なペア操作
const raw_pair: struct { i32, []const u8 } = .{ -3, "hello" };
const result: struct { i32, usize } = .{
    @abs(raw_pair[0]),   // 最初の要素を変換
    raw_pair[1].len,     // 2番目の要素を変換
};
```

`arrow` を使えば意図が明確になります：

```zig
const arrow = @import("zfp").arrow;

const result = arrow.split(absInt, strLen, .{ @as(i32, -3), "hello" });
// → .{ 3, 5 }
```

---

## `first` — 最初の要素を変換する

**Haskell**: `first f (a, b) = (f a, b)`

`f` を最初の要素に適用し、2番目はそのまま残します。

```zig
const arrow = @import("zfp").arrow;

arrow.first(double, .{ @as(i32, 3), @as(i32, 4) })
// → .{ 6, 4 }
```

最初の要素の型を変えることもできます：

```zig
arrow.first(isPositive, .{ @as(i32, 3), "hello" })
// → .{ true, "hello" }   (i32 → bool、[]const u8 はそのまま)
```

---

## `second` — 2番目の要素を変換する

**Haskell**: `second g (a, b) = (a, g b)`

`g` を2番目の要素に適用し、最初はそのまま残します。

```zig
const arrow = @import("zfp").arrow;

arrow.second(double, .{ @as(i32, 4), @as(i32, 3) })
// → .{ 4, 6 }
```

---

## `split` — それぞれの要素を独立に変換する (`***`)

**Haskell**: `(f *** g) (a, b) = (f a, g b)`

`f` を最初の要素に、`g` を2番目の要素に適用します。

```zig
const arrow = @import("zfp").arrow;

arrow.split(double, negate, .{ @as(i32, 3), @as(i32, 4) })
// → .{ 6, -4 }
```

両側で型が異なっていても構いません：

```zig
arrow.split(isPositive, double, .{ @as(i32, 5), @as(i32, 3) })
// → .{ true, 6 }   (左: i32→bool、右: i32→i32)
```

---

## `fanout` — 同じ値に2つの関数を適用する (`&&&`)

**Haskell**: `(f &&& g) a = (f a, g a)`

1つの値に `f` と `g` の両方を適用し、ペアを生成します。

```zig
const arrow = @import("zfp").arrow;

arrow.fanout(double, isPositive, @as(i32, 5))
// → .{ 10, true }
```

`fanout` は `split` の双対です。`split` がペアを受け取って両側を変換するのに対し、
`fanout` は単一の値を受け取って2つのパスに分岐させます。

---

## なぜゼロコストなのか？

4つの関数はすべて `pub inline fn` で `anytype` パラメータを持ちます。
それぞれ、最小限の関数呼び出しとタプル構築にコンパイルされます：

- `first(f, .{a, b})` → `f` を1回呼び出し、タプルリテラルを1つ
- `second(g, .{a, b})` → `g` を1回呼び出し、タプルリテラルを1つ
- `split(f, g, .{a, b})` → `f` と `g` を各1回、タプルリテラルを1つ
- `fanout(f, g, a)` → `f` と `g` を各1回、タプルリテラルを1つ

アロケーションなし、ボクシングなし、中間構造体なし。

---

## 合成の例

`first`、`second`、`split`、`fanout` は `pipe.run` と自然に組み合わせられます：

```zig
const arrow = @import("zfp").arrow;
const pipe  = @import("zfp").pipe;

// 生の入力を (値, ラベル) ペアに変換し、それぞれの側を変換する
const process = pipe.run("42:meters", .{
    splitOnColon,                                 // → .{ "42", "meters" }
    tap.typed(struct { []const u8, []const u8 }, logRaw),
    struct {
        fn call(p: struct { []const u8, []const u8 }) struct { i32, []const u8 } {
            return arrow.split(parseInt, toUpperCase, p);
        }
    }.call,                                       // → .{ 42, "METERS" }
});
```

`fanout` でサマリーペアを構築する例：

```zig
// スライスの合計と個数を1パスで計算する
const stats = arrow.fanout(sumSlice, countSlice, items);
// stats[0] = 合計、stats[1] = 個数
```

---

## 対応表

| Haskell | zfp | 内容 |
|---------|-----|------|
| `first f (a, b)` | `arrow.first(f, .{a, b})` | `.{f(a), b}` |
| `second g (a, b)` | `arrow.second(g, .{a, b})` | `.{a, g(b)}` |
| `(f *** g) (a, b)` | `arrow.split(f, g, .{a, b})` | `.{f(a), g(b)}` |
| `(f &&& g) a` | `arrow.fanout(f, g, a)` | `.{f(a), g(a)}` |

---

## 参考リンク

- [Haskell Control.Arrow](https://hackage.haskell.org/package/base/docs/Control-Arrow.html)
- [Understanding Arrows (Haskell wiki)](https://wiki.haskell.org/Arrow_tutorial)
- [Zig 無名構造体タプル](https://ziglang.org/documentation/master/#Anonymous-Struct-Literals)

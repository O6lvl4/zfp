# func — 関数コンビネータ

```zig
const func = @import("zfp").zf;
```

## これは何？

`zf` は、関数を値として扱うための基本的な部品を提供するモジュールです。
Haskell の Prelude にある `id`, `flip`, `const`, `on` の Zig 版です。

`pipe.run` や `compose.from` のチェーンの中で、小さな変換のたびに名前付き関数を定義しなくて済むようにする「のり」として機能します。

---

## `id` — 恒等関数

**Haskell**: `id :: a -> a`

引数をそのまま返します。一見無意味ですが、パイプラインの「何もしない」スロットやデフォルトの変換として不可欠です。

```zig
const func = @import("zfp").zf;

zf.id(42)      // → 42
zf.id("hello") // → "hello"
zf.id(true)    // → true
```

**パイプラインでの使用例:**

```zig
// 条件によって変換を適用するか、そのまま通す
const transform = if (should_double) double else zf.id;
const result = pipe.run(value, .{transform});
```

---

## `flip` — 引数の入れ替え

**Haskell**: `flip :: (a -> b -> c) -> b -> a -> c`

二項関数の最初の2引数を入れ替えて呼び出します。

```zig
const func = @import("zfp").zf;

const sub = fn(a: i32, b: i32) i32 { return a - b; };

sub(10, 3)            // → 7   (10 - 3)
zf.flip(sub, 10, 3) // → -7  (3 - 10)
```

**なぜ重要か:**

関数を合成するとき、引数の順序がパイプラインの要求と合わないことがあります。
`flip` を使えば、ラッパー関数を書かずに任意の二項関数を適合させられます。

```zig
// std.mem.startsWith(haystack, prefix) の順序だが
// (prefix, haystack) の形で渡したい場合
zf.flip(std.mem.startsWith, prefix, haystack)
```

---

## `const_` — 定数関数

**Haskell**: `const :: a -> b -> a`

第一引数を返し、第二引数を無視します。
`const` は Zig の予約語なので `const_` という名前にしています。

```zig
const func = @import("zfp").zf;

zf.const_(42, "ignored") // → 42
zf.const_(true, 9999)    // → true
```

**パイプラインでの使用例:**

```zig
// どんな値でも固定の番兵値に置き換える
const alwaysZero = struct {
    fn call(x: i32) i32 { return zf.const_(@as(i32, 0), x); }
}.call;

pipe.run(value, .{ parse, validate, alwaysZero }); // 常に 0 で終わる
```

---

## `on` — 共通の写像を経由して二項関数を適用

**Haskell**: `on :: (b -> b -> c) -> (a -> b) -> a -> a -> c`

単項関数 `g` を両方の引数に適用してから、その結果を二項関数 `f` に渡します。

```
on(f, g, a, b)  ≡  f(g(a), g(b))
```

```zig
const func = @import("zfp").zf;
const std   = @import("std");

const byLength = zf.on(std.math.order, sliceLen);

byLength("foo", "hello") // → .lt  (3 < 5)
byLength("hi",  "ok")    // → .eq  (2 == 2)
```

**なぜ重要か:**

`on` を使うと、毎回カスタムラッパーを書かずに、*派生したプロパティ*を使って比較や結合を行えます。

```zig
// 文字列を長さでソートする
std.sort.block([]const u8, items, {}, struct {
    fn lessThan(_: void, a: []const u8, b: []const u8) bool {
        return zf.on(std.math.order, strLen, a, b) == .lt;
    }
}.lessThan);
```

---

## なぜ `fn` ではなく `zf` なのか？

`fn` は Zig の予約語です。モジュール名に使うと、呼び出し側は毎回 `@"fn"` と書く必要があり、見苦しくなります。

```zig
// 名前を変えない場合 — 見苦しい
const f = @import("zfp").@"fn";

// func にした場合 — すっきり
const func = @import("zfp").zf;
```

---

## なぜゼロコストなのか？

4つの関数すべてが `pub inline fn` と `anytype` パラメータで定義されています。
コンパイラがコンパイル時にすべての呼び出しを展開します。

- `id(x)` → 値 `x` そのまま
- `flip(f, a, b)` → `f(b, a)` の1回の呼び出し
- `const_(x, _)` → 値 `x` そのまま
- `on(f, g, a, b)` → `f(g(a), g(b))` の2回の呼び出し

仮想ディスパッチなし、ボクシングなし、ラッパーのオーバーヘッドなし。

---

## 合成の例

```zig
const func    = @import("zfp").zf;
const pipe    = @import("zfp").pipe;
const compose = @import("zfp").compose;

// スコアフィールドで降順に比較する
const byScoreDesc = struct {
    fn call(a: Record, b: Record) bool {
        return zf.on(std.math.order, getScore, a, b) == .gt;
    }
}.call;

// パイプライン: 正規化してからスコアで順序を確認
const checkOrder = compose.from(.{ normalise, byScoreDesc });
```

---

## 対応表

| Haskell | zfp | 意味 |
|---------|-----|------|
| `id x` | `zf.id(x)` | そのまま通す |
| `flip f a b` | `zf.flip(f, a, b)` | `f(b, a)` を呼ぶ |
| `const x _` | `zf.const_(x, _)` | 常に `x` を返す |
| `f \`on\` g` | `zf.on(f, g, a, b)` | `f(g(a), g(b))` |

---

## 参考リンク

- [Haskell Prelude — id, const, flip](https://hackage.haskell.org/package/base/docs/Prelude.html)
- [Data.Function — on](https://hackage.haskell.org/package/base/docs/Data-Function.html)
- [Zig comptime と anytype](https://ziglang.org/documentation/master/#comptime)

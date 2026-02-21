# either — Left/Right 直和型

```zig
const either = @import("zfp").either;
```

## これは何？

`either` は `Either(L, R)` を提供します。これは 2 つの選択肢のいずれかを保持するタグ付きユニオンです：

- **`Left(L)`** — 「補助的な」または「エラー」側
- **`Right(R)`** — 「主要な」または「成功」側

Haskell の `Data.Either` にインスパイアされており、型の異なる 2 種類の結果を持つ計算を表現します。

`result`（`anyerror!T` に作用する）と異なり、`Either(L, R)` は左右どちらの型も**自由に選択できます** — リッチなエラー型、代替値、ドメイン固有のバリアントも使えます。

---

## 問題

関数が 2 種類の異なる型を返す場合、Zig にはいくつかの選択肢があります：

```zig
// 選択肢 1 — タグ付きユニオン（毎回定義が冗長）
const ParseResult = union(enum) {
    ok: i32,
    err: []const u8,
};

// 選択肢 2 — anyerror!T（Left 側はエラーセットに限定）
fn parse(s: []const u8) anyerror!i32 { ... }

// どちらも連鎖させるたびに手動の switch が必要
const raw = parse(input) catch |e| return e;
const doubled = raw * 2;
```

`either` を使えば意図が明確で合成可能になります：

```zig
const either = @import("zfp").either;
const E = either.Either([]const u8, i32);

const result = either.andThen(
    either.andThen(parse(input), validate),
    double,
);
```

---

## `Either(L, R)` — 型の構築

`Either(L, R)` を使って Either 型を構築します：

```zig
const either = @import("zfp").either;

const E = either.Either([]const u8, i32);

const ok  = E{ .right = 42 };
const err = E{ .left  = "何かがおかしい" };
```

---

## Functor — `map`

**Haskell**: `fmap :: (a -> b) -> Either l a -> Either l b`

`Right` の値に `f` を適用し、`Left` はそのまま通します。

```zig
const either = @import("zfp").either;

const E = either.Either([]const u8, i32);

either.map(E{ .right = 3 }, double)
// → Either([]const u8, i32){ .right = 6 }

either.map(E{ .left = "エラー" }, double)
// → Either([]const u8, i32){ .left = "エラー" }
```

Right 側の型を変えることもできます：

```zig
either.map(E{ .right = 5 }, isPositive)
// → Either([]const u8, bool){ .right = true }
```

---

## Monad — `andThen`

**Haskell**: `(>>=) :: Either l a -> (a -> Either l b) -> Either l b`

`Right` に `f` を適用し、`Left` はそのまま伝播させます。
`f` 自身も `Either` を返す必要があります。

```zig
const either = @import("zfp").either;

const E = either.Either([]const u8, i32);

const validate = struct {
    fn call(x: i32) E {
        return if (x > 0) .{ .right = x } else .{ .left = "非正数" };
    }
}.call;

either.andThen(E{ .right = 3 }, validate)        // → .{ .right = 3 }
either.andThen(E{ .right = -1 }, validate)       // → .{ .left = "非正数" }
either.andThen(E{ .left = "失敗" }, validate)    // → .{ .left = "失敗" }
```

ネストなしで複数のステップを連鎖させられます：

```zig
either.andThen(
    either.andThen(parse(input), validate),
    transform,
)
```

---

## `mapLeft` — Left 側を変換する

`Left` の値に `f` を適用し、`Right` はそのまま通します。

```zig
const either = @import("zfp").either;

either.mapLeft(E{ .left = "hi" }, strLen)
// → Either(usize, i32){ .left = 2 }

either.mapLeft(E{ .right = 42 }, strLen)
// → Either(usize, i32){ .right = 42 }
```

---

## `bimap` — 両側を変換する

アクティブな側に応じて `lf`（Left）または `rf`（Right）を適用します。

**Haskell**: `bimap :: (a -> c) -> (b -> d) -> Either a b -> Either c d`

```zig
const either = @import("zfp").either;

either.bimap(E{ .left  = "hi" }, strLen, double)
// → Either(usize, i32){ .left = 2 }

either.bimap(E{ .right = 5 }, strLen, double)
// → Either(usize, i32){ .right = 10 }
```

`bimap` は最も汎用的な変換で、両側を一度に正規化できます。

---

## `isLeft` / `isRight` — 判定関数

```zig
const either = @import("zfp").either;

either.isLeft(E{ .left = "エラー" })   // → true
either.isRight(E{ .right = 42 })       // → true
```

---

## `unwrapOr` — Right を取り出すかデフォルト値を返す

```zig
const either = @import("zfp").either;

either.unwrapOr(E{ .right = 42 }, 0)       // → 42
either.unwrapOr(E{ .left = "エラー" }, 0)  // → 0
```

---

## `unwrapOrElse` — Right を取り出すか Left から計算する

```zig
const either = @import("zfp").either;

either.unwrapOrElse(E{ .right = 42 }, strLen)        // → 42
either.unwrapOrElse(E{ .left = "hello" }, strLen)    // → 5
```

---

## `fromOption` — `?T` を Either に変換する

```zig
const either = @import("zfp").either;

either.fromOption(@as(?i32, 42), "欠損")    // → .{ .right = 42 }
either.fromOption(@as(?i32, null), "欠損")  // → .{ .left = "欠損" }
```

---

## `toOption` — Either を `?R` に変換する

`Left` の値は捨てられます。

```zig
const either = @import("zfp").either;

either.toOption(E{ .right = 42 })        // → @as(?i32, 42)
either.toOption(E{ .left = "エラー" })   // → null
```

---

## なぜ Zig のネイティブタグ付きユニオンが正しいのか

`Either(L, R)` はタグ付きユニオンにコンパイルされます。これは Zig が `?T` や `anyerror!T` に使うものと同じ構造です。ヒープアロケーションなし、ボクシングなし、間接参照なし。

```zig
// Either([]const u8, i32) は以下と同じ構造にコンパイルされます：
union(enum) {
    left: []const u8,
    right: i32,
}
```

オーバーヘッドはタグのバイトのみ — ユニオンを手書きしたときと同じコストです。

---

## なぜゼロコストなのか

すべての関数は `pub inline fn` で `anytype` パラメータを持ちます。
戻り型は `@TypeOf(f(@as(PayloadType, undefined)))` で算出されます — 実行せずに型を評価するコンパイル時式です。

どの呼び出しも、1 つのブランチが取られるプレーンな `switch` 文にコンパイルされます：

```zig
// map(e, f) は以下にコンパイルされます：
switch (e) {
    .left => |l| .{ .left = l },
    .right => |r| .{ .right = f(r) },
}
```

仮想ディスパッチなし。アロケーションなし。中間構造体なし。

---

## 合成の例

文字列をパースし、範囲を検証し、結果をフォーマットする — または各段階でわかりやすいエラーを収集する：

```zig
const either = @import("zfp").either;
const std    = @import("std");

const E = either.Either([]const u8, i32);

const parse = struct {
    fn call(s: []const u8) E {
        const n = std.fmt.parseInt(i32, s, 10) catch return .{ .left = "数値ではありません" };
        return .{ .right = n };
    }
}.call;

const validate = struct {
    fn call(n: i32) E {
        return if (n >= 0 and n <= 100)
            .{ .right = n }
        else
            .{ .left = "範囲外 [0, 100]" };
    }
}.call;

const result = either.andThen(parse("42"), validate);
// → .{ .right = 42 }

const bad = either.andThen(parse("999"), validate);
// → .{ .left = "範囲外 [0, 100]" }
```

---

## 対応表

| Haskell | zfp | 内容 |
|---------|-----|------|
| `Left l` | `E{ .left = l }` | Left として包む |
| `Right r` | `E{ .right = r }` | Right として包む |
| `fmap f (Right r)` | `either.map(e, f)` | `.{ .right = f(r) }` |
| `fmap f (Left l)` | `either.map(e, f)` | `.{ .left = l }` |
| `first f` | `either.mapLeft(e, f)` | Left に f を適用 |
| `bimap lf rf` | `either.bimap(e, lf, rf)` | アクティブな側に適用 |
| `e >>= f` | `either.andThen(e, f)` | Right の flatMap |
| `fromMaybe` | `either.fromOption(opt, l)` | `?T → Either(L, R)` |
| `toMaybe` | `either.toOption(e)` | `Either(L, R) → ?R` |
| `either l r` | `switch` 式 | Left/Right でパターンマッチ |

---

## 参考リンク

- [Haskell Data.Either](https://hackage.haskell.org/package/base/docs/Data-Either.html)
- [Rust Result](https://doc.rust-lang.org/std/result/enum.Result.html) — 同じコンセプト、エラー側が制限付き
- [Zig タグ付きユニオン](https://ziglang.org/documentation/master/#Tagged-union)

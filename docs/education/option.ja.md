# Option — 解説ガイド

> English version: [option.md](./option.md)

---

## Option とは何か

**Option**（Haskell では **Maybe**、Java/Swift では **Optional**）は「値があるかもしれないし、ないかもしれない」という状態を表す型です。

`null` を「魔法の値」としてコード中に黙って流すのではなく、「値が存在しないかもしれない」という事実を**型システムで明示**します。

```
Some(42)   — 値が存在する
None       — 値が存在しない
```

Zig では、これはすでに言語の第一級機能として提供されています: `?T`。

```zig
const x: ?i32 = 42;    // Some(42)
const y: ?i32 = null;  // None
```

Zig の `?T` はそのまま Option 型です。`zfp/option` は、その上に**ランタイムコスト ゼロ**で関数型コンビネータを追加します。

---

## 問題: ネストされた null チェック

複数の操作が失敗しうる場合、素朴に書くと深いネストが生まれます。

```zig
fn process(raw: ?[]const u8) ?i32 {
    if (raw) |s| {
        const parsed = std.fmt.parseInt(i32, s, 10) catch return null;
        if (parsed > 0) {
            const result = lookup(parsed);
            if (result) |r| {
                return r * 2;
            }
        }
    }
    return null;
}
```

ステップが増えるたびにインデントが深くなります。本来の処理ロジックが `if` の海に埋もれていく。これは **「ピラミッド・オブ・ドゥーム」** とも呼ばれます。

同じロジックをパイプラインで書くと:

```zig
const option = @import("zfp").option;

fn process(raw: ?[]const u8) ?i32 {
    return option.map(
        option.andThen(
            option.andThen(raw, parsePositiveInt),
            lookup,
        ),
        double,
    );
}
```

フラットで読みやすく、生成されるマシンコードは**ネスト版と完全に同一**です。

---

## 関数型プログラミングの概念

### ファンクタ — `map`

**ファンクタ**とは、コンテナを「開けずに」関数を適用できる構造です。

```
map : F(A) → (A → B) → F(B)
```

Option における意味:

```
map(Some(a), f)  = Some(f(a))
map(None,    f)  = None
```

`map` は `A → B` という関数を「optional の世界」に持ち上げます。null の伝播はコンテナが肩代わりするので、あなたが `if` を書く必要はありません。

```zig
const option = @import("zfp").option;

fn double(x: i32) i32 { return x * 2; }

// null でなければ 2 倍、null はそのまま通す
const result = option.map(@as(?i32, 21), double); // ?i32(42)
const empty  = option.map(@as(?i32, null), double); // null
```

**ポイント**: `map` は「値があるかどうか」を変えません。あくまで中身を変換するだけです。

---

### モナド — `andThen`

**モナド**は、ファンクタの考え方を「自分でも optional を返す関数」に拡張したものです。

```
andThen : F(A) → (A → F(B)) → F(B)
```

`flatMap`、`bind`、Haskell の `>>=` とも呼ばれます。

`map` との違い:

| 操作 | `f` の戻り値 | 結果 |
|------|------------|------|
| `map` | `B` | `?B` |
| `andThen` | `?B` | `?B` |

`map` で「失敗しうる関数」を適用すると `??B`（二重の optional）になります。`andThen` はそれを自動でフラットに展開します。

```zig
const std = @import("std");
const option = @import("zfp").option;

const safeSqrt = struct {
    fn call(x: f64) ?f64 {
        if (x < 0) return null;
        return std.math.sqrt(x);
    }
}.call;

// 失敗しうる操作を 2 回連鎖させる
const r = option.andThen(option.andThen(@as(?f64, 16.0), safeSqrt), safeSqrt);
// 16.0 → sqrt → 4.0 → sqrt → 2.0
```

**ポイント**: `andThen` は「失敗しうる操作の連鎖」を、ネストなしに書くための仕組みです。どのステップが `null` を返しても、チェーン全体がそこで短絡します。

---

### デフォルト値 — `unwrapOr`

optional の世界から「脱出」して、具体的な値を取り出したいとき:

```
unwrapOr : F(A) → A → A
```

```zig
const option = @import("zfp").option;

const port = option.unwrapOr(config.port, 8080);
```

Zig では `config.port orelse 8080` と書けます。`unwrapOr` はパイプラインとの一貫性のために提供しています。

---

### フィルタ — `filter`

条件を満たすときだけ値を保持する:

```
filter : F(A) → (A → Bool) → F(A)
```

```zig
const option = @import("zfp").option;

fn isPositive(x: i32) bool { return x > 0; }

const positive = option.filter(@as(?i32, -5), isPositive); // null
const kept     = option.filter(@as(?i32,  3), isPositive); // ?i32(3)
```

「値はあるが、条件を満たさない」という状態を「値がない」に変換します。値そのものは変えません。

---

## なぜ Zig の `?T` はすでに正しいのか

多くの言語では Option をジェネリック enum や struct で実装します（例: `enum Option<T> { Some(T), None }`）。これには通常:

- 判別子のためのタグバイト
- ボクシングによるヒープアロケーション
- 仮想ディスパッチや分岐予測のコスト

が伴います。

**Zig の `?T` にはこれらのコストが一切ありません。** コンパイラは `?T` を次のように表現します:

- ポインタ型: `null` は特殊なビットパターン（ゼロ）。オーバーヘッドなし。
- 値型: 小さな判別子を値の隣にパックし、値が非 null であることが自明な場合はコンパイラが完全に除去。

結果として、Zig の `?T` は手書きの「bool フラグ付き struct」と同等かそれ以上の効率を持ちます。

---

## `zfp/option` がゼロコストである理由

`zfp/option` の全関数は `inline` かつ `anytype` パラメータを使っています。

これが意味すること:

1. **関数呼び出しのオーバーヘッドなし。** 呼び出し元にインライン展開されます。
2. **型消去なし。** `anytype` はコンパイル時に解決されます。使った型に特化したコードが生成されます。
3. **間接参照なし。** 関数ポインタ、vtable、ヒープ上のクロージャは使いません。

コンパイラから見ると:

```zig
const option = @import("zfp").option;

option.map(@as(?i32, x), double)
```

は次と完全に同一です:

```zig
if (x) |v| v * 2 else null
```

`zig build -Doptimize=ReleaseFast` でビルドしてアセンブリを確認すると、呼び出しが消えていることを確かめられます。

---

## コンポジション（組み合わせ）

本当の力は、これらを組み合わせたときに発揮されます:

```zig
const option = @import("zfp").option;

// 生の文字列を、検証・変換された値に変換する
// 各ステップが独立して null を返せる
fn processInput(raw: ?[]const u8) ?f64 {
    return option.map(
        option.andThen(
            option.andThen(
                option.filter(raw, isNonEmpty),
                parseFloat,
            ),
            validateRange,
        ),
        normalize,
    );
}
```

内側から読むと:
1. `filter` — 空文字列をスキップ
2. `andThen(parseFloat)` — f64 にパース、失敗なら null
3. `andThen(validateRange)` — 範囲外の値を棄却
4. `map(normalize)` — 正常な値を変換

各ステップは独立してテスト・命名できます。データの流れが明示的になります。

---

## 他の概念との対応

| 概念 | Zig の記法 | zfp 関数 |
|------|-----------|---------|
| ファンクタ | `if (x) \|v\| f(v) else null` | `map` |
| モナド / flatMap | `if (x) \|v\| f(v) else null`（f が `?U` を返す） | `andThen` |
| デフォルト / getOrElse | `x orelse default` | `unwrapOr` |
| ガード / filter | `if (x) \|v\| if (p(v)) v else null` | `filter` |
| 存在確認 | `x != null` | `isSome` |
| 不在確認 | `x == null` | `isNone` |

これらの操作はすべて Zig にすでに構文として存在します。`zfp/option` はそれらに**名前をつけ**、意図を明確にし、ノイズなしのコンポジションを可能にします。

---

## 参考リソース

- [Zig 言語リファレンス: Optional](https://ziglang.org/documentation/master/#Optionals)
- [Haskell `Maybe` モナド](https://wiki.haskell.org/Maybe_monad) — 原典
- [Rust `Option<T>`](https://doc.rust-lang.org/std/option/) — よく整備されたモダンな実装例

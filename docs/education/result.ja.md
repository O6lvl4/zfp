# Result — 解説ガイド

> English version: [result.md](./result.md)

---

## Result とは何か

**Result**（Haskell では **Either**、Rust では `Result<T, E>`）は「成功して値を返すか、失敗してエラーを返すか」という計算を表す型です。

例外（型システムから逃げる）やマジックな戻り値コード（無視しやすい）ではなく、失敗の可能性を**型で明示**します。

```
Ok(42)        — 成功（値あり）
Err(NotFound) — 失敗（エラーあり）
```

Zig では、これはすでに言語の第一級機能として提供されています: `E!T`（エラーユニオン）。

```zig
const x: anyerror!i32 = 42;             // Ok(42)
const y: anyerror!i32 = error.NotFound; // Err(NotFound)
```

Zig の `E!T` はそのまま Result 型です。`zfp/result` は、その上に**ランタイムコスト ゼロ**で関数型コンビネータを追加します。

---

## 問題: 散らばったエラー処理

複数の操作が失敗しうる場合、素朴に書くとエラー処理がロジック全体に散らばります。

```zig
fn process(raw: anyerror![]const u8) anyerror!i32 {
    const s = try raw;
    const n = std.fmt.parseInt(i32, s, 10) catch |err| return err;
    if (n <= 0) return error.OutOfRange;
    const looked_up = lookup(n) catch |err| return err;
    return looked_up * 2;
}
```

各ステップで個別のエラー処理が必要です。本来のハッピーパスがノイズに埋もれています。

同じロジックをパイプラインで書くと:

```zig
const result = @import("zfp").result;

fn process(raw: anyerror![]const u8) anyerror!i32 {
    return result.andThen(
        result.andThen(
            result.andThen(raw, parsePositiveInt),
            lookup,
        ),
        double,
    );
}
```

フラットで読みやすく、生成されるマシンコードは**手書き版と完全に同一**です。

---

## 関数型プログラミングの概念

### ファンクタ — `map`

**ファンクタ**とは、コンテナを「開けずに」関数を適用できる構造です。

```
map : F(A) → (A → B) → F(B)
```

Result における意味:

```
map(Ok(a),  f)  = Ok(f(a))
map(Err(e), f)  = Err(e)
```

`map` は「失敗しない（純粋な）関数」を「失敗しうる値の世界」に持ち上げます。エラーの伝播はコンテナが肩代わりするので、あなたが `catch` を書く必要はありません。

```zig
const result = @import("zfp").result;

fn double(x: i32) i32 { return x * 2; }

const ok  = result.map(@as(anyerror!i32, 21), double);          // Ok(42)
const err = result.map(@as(anyerror!i32, error.Bad), double);   // Err(Bad)
```

**ポイント**: `map` は「成功しているかどうか」を変えません。成功値の中身を変換するだけです。

---

### モナド — `andThen`

**モナド**は、ファンクタの考え方を「自分でも result を返す関数」に拡張したものです。

```
andThen : F(A) → (A → F(B)) → F(B)
```

`flatMap`、`bind`、Haskell の `>>=` とも呼ばれます。

`map` との違い:

| 操作 | `f` の戻り値 | 結果 |
|------|------------|------|
| `map` | `B` | `E!B` |
| `andThen` | `E!B` | `E!B` |

`map` で「失敗しうる関数」を適用すると `E!(E!B)`（二重のエラーユニオン）になります。`andThen` はそれを自動でフラットに展開します。

```zig
const result = @import("zfp").result;

const safeDiv = struct {
    fn call(x: i32) anyerror!i32 {
        if (x == 0) return error.DivisionByZero;
        return @divTrunc(100, x);
    }
}.call;

// 失敗しうる操作を 2 回連鎖させる
const r = result.andThen(result.andThen(@as(anyerror!i32, 5), safeDiv), safeDiv);
// 5 → 100/5=20 → 100/20=5
```

**ポイント**: `andThen` は「失敗しうる操作の連鎖」を、ネストなしに書くための仕組みです。どのステップが失敗しても、チェーン全体がそこで短絡します。

---

### デフォルト値 — `unwrapOr`

エラーを無視してデフォルト値で代替したいとき:

```
unwrapOr : F(A) → A → A
```

```zig
const result = @import("zfp").result;

const port = result.unwrapOr(config.readPort(), 8080);
```

Zig では `config.readPort() catch 8080` と書けます。`unwrapOr` はパイプラインとの一貫性のために提供しています。

---

### エラーを使ったリカバリ — `unwrapOrElse`

エラー値そのものを使ってフォールバック値を決めたいとき:

```
unwrapOrElse : F(A) → (E → A) → A
```

```zig
const result = @import("zfp").result;

const value = result.unwrapOrElse(readConfig(), struct {
    fn call(err: anyerror) Config {
        std.log.warn("config error: {s}, using defaults", .{@errorName(err)});
        return Config.default();
    }
}.call);
```

`option` との大きな違いはここです。エラーは情報を持つため、リカバリ処理でそのエラー値を使いたいケースが多い。`unwrapOrElse` はそれを明示的にします。

---

### Option へのブリッジ — `toOption`

result ベースのコードと option ベースのコードをつなぐとき:

```
toOption : F(A) → ?A
```

```zig
const result = @import("zfp").result;

// エラーを捨て、「成功したかどうか」だけを保持する
const maybe_value: ?i32 = result.toOption(riskyOperation());
```

「具体的なエラー内容」より「あるかないか」だけが重要なシステム境界で有用です。

---

## Result vs Option

| 概念 | `option` | `result` |
|------|----------|---------|
| 表すもの | 存在 / 不在 | 成功 / 失敗 |
| Zig のネイティブ型 | `?T` | `E!T` |
| 不在時の情報 | なし | あり（エラー値） |
| リカバリ | `unwrapOr` | `unwrapOr`、`unwrapOrElse` |

**`option` を使う**: 不在の理由を報告する必要がない場合。
**`result` を使う**: 失敗の理由を呼び出し元が使う可能性がある場合。

---

## なぜ Zig の `E!T` はすでに正しいのか

多くの言語では Result をジェネリック enum で実装します（例: `enum Result<T, E> { Ok(T), Err(E) }`）。これには通常:

- 判別子のためのタグバイト
- 大きなエラー型のボクシングによるヒープアロケーション
- バリアントのマッチングオーバーヘッド

が伴います。

**Zig の `E!T` にはこれらのコストが一切ありません。** コンパイラは `E!T` を次のように表現します:

- エラー値は Zig でコンパイル時整数なので、タグは小さな整数
- ペイロード T はその隣に格納
- 結果が成功であることが自明な場合はタグをコンパイラが除去

結果として、Zig の `E!T` は手書きの discriminated union と同等かそれ以上の効率を持ちます。

---

## `zfp/result` がゼロコストである理由

`zfp/result` の全関数は `inline` かつ `anytype` パラメータを使っています。

これが意味すること:

1. **関数呼び出しのオーバーヘッドなし。** 呼び出し元にインライン展開されます。
2. **型消去なし。** `anytype` はコンパイル時に解決されます。使ったエラーセットに特化したコードが生成されます。
3. **間接参照なし。** 関数ポインタ、vtable、ヒープ上のクロージャは使いません。

コンパイラから見ると:

```zig
const result = @import("zfp").result;

result.map(@as(anyerror!i32, x), double)
```

は次と完全に同一です:

```zig
if (x) |v| double(v) else |err| err
```

---

## コンポジション（組み合わせ）

本当の力は、これらを組み合わせたときに発揮されます:

```zig
const result = @import("zfp").result;

// 生の設定文字列をパース・検証して Config を構築する
// 各ステップが独立してエラーを返せる
fn parseConfig(raw: anyerror![]const u8) anyerror!Config {
    return result.map(
        result.andThen(
            result.andThen(
                result.andThen(raw, trimWhitespace),
                parseJson,
            ),
            validateSchema,
        ),
        buildConfig,
    );
}
```

内側から読むと:
1. `andThen(trimWhitespace)` — 空白を除去、空なら失敗
2. `andThen(parseJson)` — JSON にパース、構文エラーなら失敗
3. `andThen(validateSchema)` — スキーマ検証、フィールド不足なら失敗
4. `map(buildConfig)` — 検証済みの値から Config を構築（失敗しない）

各ステップは独立してテスト・命名できます。すべてのエラーパスが型に現れます。

---

## 他の概念との対応

| 概念 | Zig の記法 | zfp 関数 |
|------|-----------|---------|
| ファンクタ | `if (x) \|v\| f(v) else \|e\| e` | `map` |
| モナド / flatMap | `f(x catch \|e\| return e)` | `andThen` |
| デフォルト / getOrElse | `x catch default` | `unwrapOr` |
| エラーでリカバリ | `x catch \|e\| f(e)` | `unwrapOrElse` |
| optional へのブリッジ | `x catch null` | `toOption` |
| 成功チェック | `if (x) \|_\| true else \|_\| false` | `isOk` |
| エラーチェック | `if (x) \|_\| false else \|_\| true` | `isErr` |

---

## 参考リソース

- [Zig 言語リファレンス: Error Union](https://ziglang.org/documentation/master/#Error-Union-Type)
- [Haskell `Either` モナド](https://hackage.haskell.org/package/base/docs/Data-Either.html) — 原典
- [Rust `Result<T, E>`](https://doc.rust-lang.org/std/result/) — よく整備されたモダンな実装例

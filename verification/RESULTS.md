# 検証結果マトリクス

`verification/run-all.sh` が生成する。手で編集しない。

「手順書の主張」と「実際に止めた層」を並べるのがこの表の眼目である。
一致すれば手順書が正しく、ズレれば手順書への修正提案になる。

## この表が保証していること・していないこと

生成前に対照実行（パッチ無しで全ゲートが pass すること）を確認している。
したがって ✅ の行は「パッチを当てたら、主張どおりの層のゲートが赤くなった」を意味する。
❌ と ⚠️ の行はそうならなかったことを意味し、原因の分析は
`docs/superpowers/phase0-findings.md` の「手順書への修正提案候補」に書く。

一方、次は保証していない。読むときに補って解釈すること。

- **どのルールが落としたかは見ていない。** 「実際に止めた層」の列はゲート単位であり、
  意図したルールが発火したのか、パッチが誘発した別の違反で落ちたのかを区別しない。
  同じ層で止まる複数のケース（例: L1-01 と L1-02）は観測上まったく同一になる。
- **因果は保証していない。** ゲートが赤くなったことと、それがパッチのせいであることは
  別である。対照実行はこの隙間を狭めるが、閉じはしない。
- **ゲート単位までは見るが、ルール単位は見ていない。** 手順書がツール名を名指ししている
  ケースは `claimed_gate` で照合するので「層は一致したが名指しされたツールは無反応」を
  区別できる。ただし同じゲート内でどのルールが落としたかは区別しない。
- **「止めた」と「検出した」を区別している。** 非ブロックゲート（`l2-new-deps`）は
  exit code で欠陥を主張しないので、検出した場合は「（検出のみ）」と注記する。

| ケース | 落とし穴 | 手順書の主張 | 実際に止めた層 | 判定 |
|---|---|---|---|---|
| L1-01-eslint-disable-abuse | eslint-disable でファイル全体を黙らせる | L1 | l1-lint | ✅ 一致 |
| L1-02-explicit-any | any で型チェックを回避する | L1 | l1-lint | ✅ 一致 |
| L1-03-floating-promise | await 忘れで Promise を放置する | L1 | l1-lint, l3-test | ✅ 一致 |
| L1-04-unused-disable | 効いていない eslint-disable を残す | L1 | l1-lint | ✅ 一致 |
| L1-05-unchecked-index | 配列添字アクセスの undefined を考慮しない | L1 | l1-typecheck | ✅ 一致 |
| L1-06-web-imports-api | Web から API の内部実装を直接 import する | L1 | （なし） | ❌ どの層も止めなかった |
| L2-01-phantom-package | 存在しないパッケージを import する | L2 (l2-osv) | l2-install, l2-new-deps（検出のみ） | ❌ 層は一致・主張したツールは無反応 |
| L2-02-guard-missing | Controller から認可ガードを外す | L2 (l2-semgrep) | l2-semgrep, l3-test | ✅ 一致 |
| L2-03-hardcoded-secret | API キーらしき文字列をハードコードする | L2 | l2-semgrep, l2-gitleaks | ✅ 一致 |
| L2-04-new-dependency | 実在する新規依存を追加する | L2 (l2-new-deps) | l2-new-deps（検出のみ） | ✅ 一致 |
| L2-05-sql-injection | $queryRawUnsafe で文字列連結して SQL を組み立てる | L2 (l2-semgrep) | l3-test | ❌ 別の層が止めた |
| L3-01-broken-logic | 割引計算のロジックを壊す | L3 (l3-test) | l3-test | ✅ 一致 |
| L3-02-openapi-drift | DTO を変更して OpenAPI 生成物を更新しない | L3 (l3-openapi-drift) | l3-openapi-drift | ✅ 一致 |
| L3-03-authz-bypass | 認可チェック（所有者確認）が欠落する | L2 (l2-semgrep) | l3-test | ❌ 別の層が止めた |

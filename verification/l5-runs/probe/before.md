レビュー完了。`main...HEAD` は実質ドキュメント 2 本（Phase 5 設計・実装計画）と、`discount.spec.ts` から境界値テストを 1 件消す `tmp:` コミットです。計画書に埋め込まれたシェルスクリプトと実測手順を実行可能なコードとして精査しました。

指摘 10 件（重大度順）:

- `docs/superpowers/plans/2026-08-06-phase5-l5-ai-review.md:836` — Task 5 が `gates.test.sh` に足す `git checkout -b` / `git commit -am` / `git branch -D` は、クリーンツリーの前提チェックが無い場所に置かれる。未コミットの作業が tmp コミットに取り込まれたうえで `-D` で消える。tmp ブランチが残存していた場合は `checkout -b` 失敗後も `check` が中断しないため、probe コミットが実ブランチに落ちる（`run-case.sh` が明示的に防いでいる事故）。detached HEAD で `_l4_base` が文字列 `HEAD` になる穴もある。
- `...plan.md:924` — Task 6 Step 3 の Playwright 赤確認（`合計:` → `総額:`）は原理的に赤くならない。E2E は `getByText('1080 円')` しか見ておらず、それは行内の `<span>{order.discountedTotal} 円</span>` に一致する。exit 0 を「E2E がその表示を検証していない」と読む表があるため、§1.44 と同型の誤った結論を出す。
- `...plan.md:943` — Task 6 Step 4/5 の `stryker run ... | tail -30` の直後の `echo "exit=$?"` は `tail` の終了コードを拾う。#34 の仮説（関連テスト 0 件で error になるか）を測る唯一の値が常に 0 になる。`${PIPESTATUS[0]}` にすべき。
- `...plan.md:157` — Task 1 の名前衝突実測は、2 回目の実行前に SKILL.md をコミットするため、レビュー対象の差分自体にチェックリスト 8 語が含まれる。Step 5 の grep は「スキルが読まれた」と「追加ファイルを読んだ」を区別できず、組み込みが優先されていても「手順書どおり」と誤判定する。
- `...plan.md:277` — `l5-ai-review.sh` は claude の実行時失敗（認証切れ・レート制限）を exit 0 に潰すが、`run-l5.sh` は exit 2 で実行不能を判別する設計。実行不能列が常に 0 になり、失敗回が「AI が指摘しなかった」に化ける。
- `...plan.md:334` — 新規 2 件の `gates.test.sh` チェックは、claude 未インストール環境では両方 `gate_require_cmd claude` で exit 2 になる。ref ガードを消しても緑のまま。Docker ゲートと同様にメッセージ照合が要る。
- `...plan.md:702` — `run-l5.sh` の構造に `verify/<ID>` 残存チェックが無い。中断で残ったブランチがあると `checkout -b` 失敗後にパッチが実ブランチへ当たる。
- `apps/api/src/discount/discount.spec.ts:11` — `tmp:` の probe コミットがレビュー範囲に入っている。マージすると L5-03 の `case.patch`（同じ `it` を含む 3 ブロックを削除する前提）が `git apply` に失敗する。Task 1 Step 7 で `branch -D` により消えるはずのコミット。
- `...plan.md:268` — `mkdir -p "${OUT%/*}"` は `L5_REVIEW_OUT` にスラッシュが無いとファイル名のディレクトリを作り、リダイレクトが失敗したまま exit 0 になる。
- `...plan.md:62` — ゲート側は「追跡ファイルにすると次のケースの `l2-gitleaks` が拾う（§1.55）」を理由に `reports/` へ出すのに、`run-l5.sh` は同じ生出力 15 本を追跡ディレクトリ `verification/l5-runs/` にコピーしてコミットする。同じ漏洩経路を再び開けている。

なお L5-01 のパッチが既存 web テスト（`orderTotal.test.ts` / `OrderList.test.tsx`）を通すという計画の見立ては、実データで確認して正しいことを確かめました。

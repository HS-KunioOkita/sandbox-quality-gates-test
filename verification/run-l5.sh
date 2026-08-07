#!/usr/bin/env bash
# L5（AI レビュー）の反復実測。
#
#   verification/run-l5.sh [回数]
#
# L5 系 3 ケースそれぞれについて、同じ差分に対して l5-ai-review を N 回
# （既定 5 回）実行し、生出力を verification/l5-runs/ に保存して
# verification/L5-REVIEW.md に集計する。
#
# なぜ RESULTS.md と別なのか: l5-ai-review は GATE_ORDER にも
# GATE_DETECTION にも入っていない（決定 D1）。claude -p は非決定的で、
# 1 回の結果を RESULTS.md に恒久的な事実として固定すると誤読を生む。
# 手順書 §6.1 自身が「LLM の判定は非頑健」と書いているので、
# 揺れの実測こそが検証結果である。
set -uo pipefail

toplevel=$(git rev-parse --show-toplevel) || exit 2
[ -n "$toplevel" ] || exit 2
cd "$toplevel" || exit 2

RUNS="${1:-5}"
CASES="L5-01-duplicate-logic L5-02-n-plus-one L5-03-missing-boundary-test"
OUT_DIR=verification/l5-runs
REVIEW=verification/L5-REVIEW.md

if [ -n "$(git status --porcelain)" ]; then
  printf 'エラー: 作業ツリーが汚れています。コミットまたは stash してください\n' >&2
  git status --short >&2
  exit 2
fi

BASE_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BASE_BRANCH" = "HEAD" ]; then
  printf 'エラー: detached HEAD では実行できません\n' >&2
  exit 2
fi

# 検証ブランチが前回の異常終了で残っていないかを先に確認する（run-case.sh と同じ理由。
# 残っていると checkout -b が失敗し、以降のパッチ適用が実ブランチに向かう事故になる）。
for case_id in $CASES; do
  branch="verify/l5-$case_id"
  if git show-ref --quiet "refs/heads/$branch"; then
    printf 'エラー: ブランチ %s が残っています。前回が異常終了しています\n' "$branch" >&2
    printf '  復旧: git branch -D %s\n' "$branch" >&2
    exit 2
  fi
done

WORK=$(mktemp -d)
STATUS="$WORK/status.tsv"
: >"$STATUS"

# ケースごとの静的メタデータ。bash 3.2 に連想配列が無いため case 文で引く。
#
#   checklist_kw    : SKILL.md のチェックリスト項目の文字列に含まれる部分文字列。
#                      空文字なら「対応する項目が無い」（L5-01。手順書の穴）。
#   checklist_label : L5-REVIEW.md の「対応するチェックリスト項目」列に出す文字列。
#   pitfall_kw_re    : checklist_kw が空のケース（L5-01）専用。チェックリストに
#                      判定行が無いので、自由記述の指摘本文が pitfall（Web 側での
#                      割引ロジックの二重実装）に触れているかを見る grep -E パターン。
#                      Task 1 の probe は境界値ケースの派生であり L5-01 の実出力は
#                      観察していなかったため、Step 5（RUNS=1 の実測）で実出力を
#                      読んで確定させた（詳細は case_pitfall_kw_re のコメント）。
#   pitfall_target_file: pitfall_kw_re の一致をさらに絞るためのファイル名（部分一致）。
#                      キーワード一致だけだと「診断対象ファイルには触れていない、
#                      別の指摘の中で偶然キーワードが出た」回を誤って数える
#                      （fix round 1 でレビュアが実測で発見。詳細は pitfall_mentioned
#                      のコメント）。
case_checklist_kw() {
  case "$1" in
    L5-01-duplicate-logic) printf '%s' '' ;;
    L5-02-n-plus-one) printf '%s' 'N+1' ;;
    L5-03-missing-boundary-test) printf '%s' '境界値' ;;
  esac
}
case_checklist_label() {
  case "$1" in
    L5-01-duplicate-logic) printf '%s' '（存在しない）' ;;
    L5-02-n-plus-one) printf '%s' 'N+1：ORM のクエリが件数に比例して増えないか' ;;
    L5-03-missing-boundary-test) printf '%s' '境界値：閾値のちょうど上・ちょうど・すぐ下のテストがあるか' ;;
  esac
}
case_pitfall_kw_re() {
  case "$1" in
    # Step 5（RUNS=1）は「重複」「二重実装」を使わず「割引ルールが API と web の
    # 2 箇所に分散した」「ドリフト問題」と表現していた。fix round 1 のレビューで、
    # Step 7（RUNS=5）の run-2 は「二重化」を使っており、このパターンにも入っていな
    # かったことが判明した（run-2 が 5/5 に数えられたのは、たまたま別の指摘文中に
    # 「再判定」という語が出ていたための偶然の一致だった）。表現の揺れは今後も
    # 増える前提で、"2 箇所"/"2 か所" という定型的な数え方の表現も候補に加えて
    # 頑健性を上げているが、これでも新しい言い回しを取りこぼす可能性は残る
    # （L5-REVIEW.md に残る限界として明記）。
    L5-01-duplicate-logic) printf '%s' '重複|二重化|二重実装|再実装|再判定|分裂|分散|ドリフト|2 ?箇所|2 ?か所' ;;
    *) printf '%s' '' ;;
  esac
}
case_pitfall_target_file() {
  case "$1" in
    L5-01-duplicate-logic) printf '%s' 'orderTotal.ts' ;;
    *) printf '%s' '' ;;
  esac
}

# チェックリスト表だけを抜き出す（見出し「## チェックリスト」から次の「## 」見出しまで）。
# 指摘（findings）テーブルも同じ「| ... |」形式なので、セクションで区切らずに
# キーワード一致だけで判定すると findings 側の行を誤って拾いうる。Step 1 で観察した
# 実出力（probe2-with-skill.md）は必ず「## チェックリスト」→ 表 → 「## 指摘」の順。
extract_checklist() {
  awk '
    /^## / {
      insec = ($0 ~ /チェックリスト/) ? 1 : 0
      next
    }
    insec && /^\|/ { print }
  ' "$1"
}

# 「指摘」表（重大度|ファイル:行|指摘|根拠）だけを抜き出す。L5-01 の pitfall_mentioned
# 専用（extract_checklist と対になる）。差分の要約文（ファイル先頭、表より前）は
# 「〜を web 側で再判定する実装に変わっている」のように、レビュー結果ではなく
# 単に diff の内容を機械的に説明する行なので、そこにキーワードが出ても「自発的に
# 問題として指摘した」ことにはならない。fix round 1 のレビューはこの区別が
# 無かったことも間接的な原因として指摘している（要約文での偶然の一致は無かったが、
# 指摘表の別の行での偶然の一致と同じ根本原因: キーワードがどの文脈で出たかを
# 見ていなかった）。
extract_findings() {
  awk '
    /^## / {
      insec = ($0 ~ /指摘/) ? 1 : 0
      next
    }
    insec && /^\|/ { print }
  ' "$1"
}

# 表の行から項目セルと判定セルを取り出す。**列位置には依存しない**。
#
# Step 5（RUNS=1）は 3 列（項目|判定|理由）だったが、Step 7（RUNS=5）の実出力の
# 1 本（L5-03 run-4）は先頭に "#" の番号列が付いた 4 列（#|項目|判定|理由）だった。
# 列位置 f[2]/f[3] に依存する実装は、この回だけ項目セルとして "4"（番号）を読み、
# キーワードに一致せず判定を取りこぼす（実測で発覚。5/5 該当のはずが 4/5 と出た）。
#
# 代わりに、行内のどのセルが「項目」でどのセルが「判定」かを内容で判定する。
# 判定セルは "該当" または "非該当" で始まるセル（前方一致）と定義する。この
# 前方一致（^該当 / ^非該当）は、「非該当」が文字列として「該当」を含むために
# 単純な部分一致だと毎回ヒットしてしまう問題（Step 1 で観察。probe2-no-skill.md
# にも散文として「境界値」が出た偽陽性と同型）を、位置指定なしで解決する。
# "非該当" は "非" から始まるので ^該当 には一致しない。
checklist_judgment() {
  local file="$1" kw="$2"
  extract_checklist "$file" | awk -v kw="$kw" '
    BEGIN { FS="|" }
    {
      line = $0
      gsub(/\*\*/, "", line)
      n = split(line, f, "|")
      has_kw = 0
      judgment = ""
      for (i = 1; i <= n; i++) {
        cell = f[i]
        gsub(/^[ \t]+|[ \t]+$/, "", cell)
        if (kw != "" && index(cell, kw) > 0) has_kw = 1
        if (cell ~ /^該当/ || cell ~ /^非該当/) judgment = cell
      }
      if (has_kw && judgment != "") {
        print judgment
        exit
      }
    }
  '
}

# checklist_judgment が返した判定文字列が「該当」（「非該当」ではない）かを 0/1 で返す。
# 前方一致なので "非該当" は該当しない（上のコメント参照）。
is_hit() {
  case "$1" in
    該当*) printf '1' ;;
    *) printf '0' ;;
  esac
}

# 対象キーワード以外の 7 項目に「該当」の行があるか（L5-02 / L5-03 の
# 「チェックリスト外の指摘」列に使う）。判定セルの特定方法は checklist_judgment と同じ
# （列位置に依存しない）。
other_checklist_hit() {
  local file="$1" kw="$2"
  extract_checklist "$file" | awk -v kw="$kw" '
    BEGIN { FS="|"; found = 0 }
    {
      line = $0
      gsub(/\*\*/, "", line)
      n = split(line, f, "|")
      has_kw = 0
      judgment = ""
      for (i = 1; i <= n; i++) {
        cell = f[i]
        gsub(/^[ \t]+|[ \t]+$/, "", cell)
        if (kw != "" && index(cell, kw) > 0) has_kw = 1
        if (cell ~ /^該当/ || cell ~ /^非該当/) judgment = cell
      }
      if (!has_kw && judgment ~ /^該当/) found = 1
    }
    END { print found }
  '
}

# L5-01 専用: チェックリストに対応項目が無いケースで、「指摘」表の行が pitfall
# 自体に触れているか。
#
# fix round 1 のレビューで発覚した問題: 当初は `grep -Eq "$pattern" "$file"` で
# ファイル全体を見ていたため、(1) 差分の要約文（レビュー結果ではなく diff の
# 説明）や (2) pitfall と無関係な別の指摘の文中で、たまたまキーワードが出た回まで
# 「自発的に指摘した」と数えていた（実測: run-2 は「二重化」を使わず、`isMember`
# 欠落についての別の指摘文中の「再判定」で偶然ヒットしていた）。
#
# 対策は 2 段: (1) 検索範囲を「指摘」表の行だけに絞る（extract_findings）。
# (2) キーワードに一致した行が、対象ファイル名（filehint）にも触れていることを
# 追加で要求する。`grep pattern | grep -F filehint` は「同じ行が両方を満たす」ことを
# 保証する（1 段目の grep で行が絞られた後段に 2 段目を適用するため）。
#
# 残る限界: これでもキーワードの列挙に依存している以上、将来 filehint には触れて
# いるがどのキーワードにも一致しない言い回しが出れば取りこぼす。L5-REVIEW.md に
# 明記する。
pitfall_mentioned() {
  local file="$1" pattern="$2" filehint="$3"
  if [ -z "$pattern" ]; then
    printf '0'
    return
  fi
  local rows
  rows=$(extract_findings "$file")
  if [ -z "$rows" ]; then
    printf '0'
    return
  fi
  if [ -n "$filehint" ]; then
    if printf '%s\n' "$rows" | grep -E "$pattern" | grep -Fq "$filehint"; then
      printf '1'
    else
      printf '0'
    fi
  elif printf '%s\n' "$rows" | grep -Eq "$pattern"; then
    printf '1'
  else
    printf '0'
  fi
}

# 1 回分の l5-ai-review 実行。出力先は必ず mktemp -d の下に置く。検証ブランチ上で
# 追跡ファイルを作ると git checkout での復帰が失敗する（§1.32 (2) と同型）。
#
# l5-ai-review.sh は exit 2（error）のときだけ「実行不能」だが、既知の穴として
# claude がゼロ終了で空出力を返した場合もゲートは pass を返す。ここで出力サイズも
# 記録し、「指摘しなかった」（内容はあるが該当なし）と「実行できなかった」
# （空出力 / exit 2）を混同しないようにする。
run_one() {
  local case_id="$1" idx="$2"
  local outfile="$WORK/$case_id-run-$idx.md"
  local gatelog="$WORK/$case_id-run-$idx.gate.log"
  GATE_BASE_REF="$BASE_BRANCH" L5_REVIEW_OUT="$outfile" ./scripts/gates/l5-ai-review.sh >"$gatelog" 2>&1
  local gate_exit=$?
  local size=0
  [ -f "$outfile" ] && size=$(wc -c <"$outfile" | tr -d ' ')
  local claude_nonzero=0
  grep -q 'L5_REVIEW_CLAUDE_EXIT=' "$gatelog" && claude_nonzero=1
  printf '%s\t%s\t%s\t%s\t%s\n' "$case_id" "$idx" "$gate_exit" "$size" "$claude_nonzero" >>"$STATUS"
  printf '    run %s: gate_exit=%s size=%sB claude_nonzero=%s\n' "$idx" "$gate_exit" "$size" "$claude_nonzero" >&2
}

for case_id in $CASES; do
  CASE_DIR="verification/cases/$case_id"
  if [ ! -f "$CASE_DIR/case.patch" ]; then
    printf 'エラー: %s に case.patch がありません\n' "$CASE_DIR" >&2
    exit 2
  fi
  BRANCH="verify/l5-$case_id"

  # run-case.sh の cleanup / restore_verify_worktree と同じ役割・同じ理由づけ。
  # ケースごとに BRANCH の値が変わるので、trap は毎ケースの先頭で張り直す。
  cleanup() {
    git checkout --quiet "$BASE_BRANCH" 2>/dev/null || true
    git branch -D "$BRANCH" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  # git apply --index の後、git commit の前に失敗したときの後始末。reset --hard で
  # 戻して良い理由は run-case.sh の同名関数と同じ（このケースの検証ブランチ上に
  # まだ新規コミットが無く、作業ツリーはパッチ適用前クリーンだったことを確認済み）。
  restore_verify_worktree() {
    git reset --hard --quiet HEAD 2>/dev/null || true
  }

  printf '=== %s ===\n' "$case_id" >&2
  if ! git checkout --quiet -b "$BRANCH"; then
    printf 'エラー: 検証ブランチ %s を作成できませんでした\n' "$BRANCH" >&2
    exit 2
  fi

  if ! git apply --index "$CASE_DIR/case.patch" 2>"$WORK/$case_id.apply.log"; then
    printf 'エラー: パッチが適用できません。case.patch の更新が必要です\n' >&2
    cat "$WORK/$case_id.apply.log" >&2
    restore_verify_worktree
    exit 2
  fi
  if ! git commit --quiet -m "verify: $case_id (l5 iterative x$RUNS)"; then
    printf 'エラー: 検証コミットに失敗しました\n' >&2
    restore_verify_worktree
    exit 2
  fi

  # N 回のループは 1 つの検証ブランチの中で回す。ブランチを切り直さない——
  # 差分が同一であることが反復実測の前提だからである。
  i=1
  while [ "$i" -le "$RUNS" ]; do
    run_one "$case_id" "$i"
    i=$((i + 1))
  done

  cleanup

  # cleanup が本当に成功したかを検査する（run-case.sh 212 行目と同じガード）。
  # ゲートが追跡ファイルを汚すと checkout が失敗し、続く branch -D も失敗する。
  # 見逃すと欠陥パッチ適用済みの検証ブランチに次のケースの処理が乗ってしまう。
  if [ "$(git rev-parse --abbrev-ref HEAD)" != "$BASE_BRANCH" ] \
    || git show-ref --quiet "refs/heads/$BRANCH"; then
    printf 'エラー: %s への復帰に失敗しました。手動で復旧してください\n' "$BASE_BRANCH" >&2
    printf '  復旧: git checkout -f %s && git branch -D %s\n' "$BASE_BRANCH" "$BRANCH" >&2
    git status --short >&2
    exit 2
  fi

  # 作業ツリーの汚れも検査する。claude -p はツール制限なし（--allowedTools も
  # --permission-mode も無し）で呼ばれており、実際に書き込みを試みている
  # （verification/l5-runs/L5-03-missing-boundary-test/run-4.md:1 と run-2.md:1 が
  # 「リポジトリ内ファイルの書き換え/検証用スクリプトの実行が承認されず未実行」と
  # 明記している——つまり書き込みは試みられ、今回は権限プロンプトで止まっただけである）。
  # 両ブランチで内容が同一のファイルを書き換えた場合、上の HEAD / ブランチ消滅の検査は
  # パスしたまま、git checkout はその変更を作業ツリーに持ち越して成功する
  # （run-case.sh:85-103 が別経路で詳述する構造と同型）。見逃すと、AI が加えた編集が
  # ユーザーの実ブランチに黙って残る。
  if [ -n "$(git status --porcelain)" ]; then
    printf 'エラー: %s への復帰後に作業ツリーが汚れています。claude -p の書き込みが持ち越された可能性があります\n' "$BASE_BRANCH" >&2
    printf '  復旧: git status で内容を確認し、意図しない変更を戻してください（git checkout -- <file> / git clean -fd）\n' >&2
    git status --short >&2
    exit 2
  fi
  trap - EXIT
done

# 全ケースが終わってから、$WORK の生出力を verification/l5-runs/<CASE-ID>/run-N.md へ
# コピーする。出力ファイルが無い回（claude コマンド自体が起動できなかった等）は
# 空ファイルを置き、status.tsv 側の記録で「実行不能」と判定できるようにする。
#
# 生出力を追跡ファイルとして残す（.gitignore しない）のは、判定基準を後から検証
# 可能にするため（設計の決定 D6）。この判断が成立するのは L5 系 3 ケースの差分に
# 秘密が含まれないからである。**秘密を含むケース（L2-03-hardcoded-secret 型）を
# 上の CASES に追加してはならない。** 追加すると、その秘密を埋め込んだ AI の
# 生出力が git 履歴に永久にコミットされる（l5-ai-review.sh のヘッダが reports/
# 配下を追跡しない理由として述べる §1.55 と同型のリスクが、ここでは追跡ディレクトリ
# 側で顕在化する）。
mkdir -p "$OUT_DIR"
for case_id in $CASES; do
  mkdir -p "$OUT_DIR/$case_id"
  i=1
  while [ "$i" -le "$RUNS" ]; do
    src="$WORK/$case_id-run-$i.md"
    dst="$OUT_DIR/$case_id/run-$i.md"
    if [ -f "$src" ]; then
      cp "$src" "$dst"
    else
      : >"$dst"
    fi
    i=$((i + 1))
  done
done

# 機械判定して L5-REVIEW.md を書く。
{
  printf '# L5（AI レビュー）反復実測\n\n'
  # shellcheck disable=SC2016
  printf '`verification/run-l5.sh` が生成する。手で編集しない（偽陽性列を除く。後述）。\n\n'
  printf '手順書 §6.1 は「LLM の判定は非頑健」と自ら書いている。同一差分・同一プロンプトを\n'
  printf 'N 回反復し、揺れそのものを実測するのがこの表の眼目である。\n\n'
  printf '## この表が保証していること・していないこと\n\n'
  printf -- '- **機械判定はキーワードの一致であり、指摘の妥当性を見ていない。** 「該当と判定」\n'
  printf '  列はチェックリスト表の判定列を文字列で読んでいるだけで、その判定が正しいかは\n'
  printf '  見ていない。\n'
  # シングルクォート内のバッククォートは Markdown のコードスパン表記であり、
  # シェル展開させない意図なので SC2016 は偽陽性
  # shellcheck disable=SC2016
  printf -- '- **`L5-01` に「対応するチェックリスト項目」が存在しないのは手順書の穴である。**\n'
  printf '  手順書 §10 は L5 にこの落とし穴を割り当てているが、§6.2 のチェックリスト 8 項目に\n'
  printf '  重複・設計一貫性の項目が無い。「n/a」はハーネスの欠落ではなく手順書の欠落を示す。\n'
  printf -- '- **n=%s の比率であり、統計的な信頼区間ではない。** 分母は実行回数 %s で固定する。\n' "$RUNS" "$RUNS"
  printf '  実行不能だった回も分母に残し、実行不能列で別に数える（「指摘しなかった」と\n'
  printf '  「実行できなかった」を混ぜない）。実行不能には (1) ゲート自体が失敗した回、\n'
  printf '  (2) claude が非ゼロで終わった回、(3) 出力が空だった回、(4) 出力はあるが\n'
  printf '  期待した表（チェックリスト表 / 指摘表）が 1 行も見つからず解析できなかった回、\n'
  printf '  の 4 種を含める。(4) を「非該当」や「自発的指摘なし」に混ぜないのは (2)(3) と\n'
  printf '  同じ理由——判定不能を判定結果として数えると、揺れの実測が誤って希釈される。\n'
  # 同上（Markdown のコードスパン表記。展開させない意図）
  # shellcheck disable=SC2016
  printf -- '- **偽陽性列は人が数える。** 基準は「そのケースの `case.patch` が触っていない箇所への\n'
  printf '  指摘」。パッチが触った箇所への指摘は、的外れでも差分に反応したことになるため\n'
  printf '  区別する。\n'
  # 同上（Markdown のコードスパン表記。展開させない意図）
  # shellcheck disable=SC2016
  printf -- '- **`L5-01` の「チェックリスト外の指摘」列（自発的な pitfall 検出）はキーワード\n'
  printf '  一致に依存しており、表現の揺れに対して原理的に頑健ではない。** fix round 1 で、\n'
  printf '  当初のキーワード集合が実際には表現の揺れ（「二重化」）を取りこぼしており、\n'
  printf '  別の指摘文中の偶然の一致で 5/5 という結果に「たまたま」到達していたことが\n'
  printf '  判明した。検索範囲を「指摘」表の行に絞り、対象ファイル名への言及も要求する\n'
  printf '  ことで誤検出の経路は塞いだが、キーワード集合自体は列挙である以上、今後\n'
  printf '  新しい言い回し（キーワードに一致せず対象ファイルには触れている回）が\n'
  printf '  出れば取りこぼす可能性が残る。\n\n'
  printf '| ケース | 対応するチェックリスト項目 | 該当と判定 | チェックリスト外の指摘 | 偽陽性 | 実行不能 |\n'
  printf '|---|---|---|---|---|---|\n'
} >"$REVIEW"

for case_id in $CASES; do
  kw=$(case_checklist_kw "$case_id")
  label=$(case_checklist_label "$case_id")
  pitfall_re=$(case_pitfall_kw_re "$case_id")
  pitfall_file=$(case_pitfall_target_file "$case_id")
  hit_count=0
  other_count=0
  unusable_count=0
  i=1
  while [ "$i" -le "$RUNS" ]; do
    f="$OUT_DIR/$case_id/run-$i.md"
    status_line=$(awk -F'\t' -v c="$case_id" -v idx="$i" '$1==c && $2==idx {print; exit}' "$STATUS")
    usable=1
    if [ -z "$status_line" ]; then
      usable=0
    else
      gate_exit=$(printf '%s' "$status_line" | cut -f3)
      size=$(printf '%s' "$status_line" | cut -f4)
      claude_nonzero=$(printf '%s' "$status_line" | cut -f5)
      # claude_nonzero は run_one が既に記録しているが、fix round 1 まで
      # ここで読まれていなかった。claude が非ゼロで終わりつつ $OUT に空でない
      # エラーメッセージ/部分出力を書いた回（l5-ai-review.sh:47 は stdout と
      # stderr の両方を $OUT にリダイレクトするため起こりうる）を size>0 だけで
      # usable と判定すると、その回のチェックリスト表が見つからず「該当しなかった」
      # に化ける。Global Constraints が名指しで禁じている取り違えなので、
      # claude_nonzero も usable の必要条件にする。
      if [ "$gate_exit" != "0" ] || [ "$size" -eq 0 ] || [ "$claude_nonzero" != "0" ]; then
        usable=0
      fi
    fi
    # status.tsv 上は usable でも、期待した表（チェックリスト表 or 指摘表）が
    # 実出力から 1 行も抜き出せない回は「解析できなかった」であり、「非該当」や
    # 「自発的指摘なし」とは区別する必要がある（extract_checklist / extract_findings
    # は見出しが無いと黙って空を返すため、この区別を呼び出し側で明示的に行う）。
    if [ "$usable" -eq 1 ]; then
      if [ -n "$kw" ]; then
        [ -z "$(extract_checklist "$f")" ] && usable=0
      else
        [ -z "$(extract_findings "$f")" ] && usable=0
      fi
    fi
    if [ "$usable" -eq 0 ]; then
      unusable_count=$((unusable_count + 1))
    elif [ -n "$kw" ]; then
      [ "$(is_hit "$(checklist_judgment "$f" "$kw")")" = "1" ] && hit_count=$((hit_count + 1))
      [ "$(other_checklist_hit "$f" "$kw")" = "1" ] && other_count=$((other_count + 1))
    else
      [ "$(pitfall_mentioned "$f" "$pitfall_re" "$pitfall_file")" = "1" ] && other_count=$((other_count + 1))
    fi
    i=$((i + 1))
  done
  if [ -n "$kw" ]; then
    hit_disp="$hit_count/$RUNS"
  else
    hit_disp="n/a"
  fi
  printf '| %s | %s | %s | %s/%s | (要目視) | %s |\n' \
    "$case_id" "$label" "$hit_disp" "$other_count" "$RUNS" "$unusable_count" >>"$REVIEW"
done

printf '\n生成しました: %s\n' "$REVIEW" >&2
printf '生出力: %s/\n' "$OUT_DIR" >&2
cat "$REVIEW"

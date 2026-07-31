import { readFileSync } from 'node:fs';

const CODE_PASS = 0;
const CODE_FAIL = 1;

/** ゲート名から層を導く（'l1-lint' → 'L1'） */
function layerOfGate(gate) {
  return gate.slice(0, 2).toUpperCase();
}

/**
 * 限定形式の expect.yml を読む。
 *
 * 完全な YAML パーサではない。トップレベルは id / pitfall / claimed_layer /
 * claimed_gate / expect / expect_detection のみ、expect 系の子はインデント
 * 2 スペースの `<ゲート名>: <値>` のみを受け付ける。
 */
export function parseExpect(path) {
  const parsed = {
    id: '',
    pitfall: '',
    claimedLayer: '',
    claimedGate: '',
    expect: {},
    expectDetection: {},
  };
  let section = null;

  for (const rawLine of readFileSync(path, 'utf8').split('\n')) {
    if (rawLine.trim() === '' || rawLine.trim().startsWith('#')) {
      continue;
    }

    const nested = /^ {2}([\w-]+):\s*(\S+)\s*$/.exec(rawLine);
    if (nested !== null && section !== null) {
      const [, key, value] = nested;
      if (section === 'expect') {
        parsed.expect[key] = value;
      } else {
        parsed.expectDetection[key] = value === 'true';
      }
      continue;
    }

    const top = /^([\w_]+):\s*(.*)$/.exec(rawLine);
    if (top === null) {
      throw new Error(`expect.yml の解釈できない行です: ${rawLine}`);
    }
    const [, key, value] = top;
    if (key === 'expect' || key === 'expect_detection') {
      section = key === 'expect' ? 'expect' : 'expect_detection';
      continue;
    }
    section = null;
    if (key === 'id') parsed.id = value.trim();
    else if (key === 'pitfall') parsed.pitfall = value.trim();
    else if (key === 'claimed_layer') parsed.claimedLayer = value.trim();
    else if (key === 'claimed_gate') parsed.claimedGate = value.trim();
    else throw new Error(`expect.yml の未知のキーです: ${key}`);
  }

  // 値の妥当性を検査する。構造が正しくても中身が不正だと判定が静かに壊れる:
  // claimed_layer が空や小文字だと blockingLayers に一致しえず claimVerdict が恒に
  // mismatch になり、expect が空だと mismatches が空になって configVerdict が恒に
  // match になる。どちらも「ハーネスが何も検証していないのに結果が出る」状態なので、
  // 黙って通さず throw する。throw すれば run-all.sh が「⚠️ 実行不能」行を出す。
  if (!/^L[1-5]$/.test(parsed.claimedLayer)) {
    throw new Error(`expect.yml の claimed_layer が不正です: ${parsed.claimedLayer}`);
  }
  // claimed_gate は任意。指定するなら形式を検査し、claimed_layer と矛盾しないことを確かめる。
  // 食い違ったまま通すと「L2 を主張しているのに L1 のゲートを名指ししている」ケースが
  // 静かに mismatch 固定になる。
  if (parsed.claimedGate !== '') {
    if (!/^l[1-5]-[a-z0-9-]+$/.test(parsed.claimedGate)) {
      throw new Error(`expect.yml の claimed_gate が不正です: ${parsed.claimedGate}`);
    }
    if (layerOfGate(parsed.claimedGate) !== parsed.claimedLayer) {
      throw new Error(
        `expect.yml の claimed_gate(${parsed.claimedGate}) の層が claimed_layer(${parsed.claimedLayer}) と一致しません`,
      );
    }
  }
  if (Object.keys(parsed.expect).length === 0) {
    throw new Error('expect.yml の expect が空です');
  }
  for (const [gate, value] of Object.entries(parsed.expect)) {
    if (value !== 'pass' && value !== 'fail') {
      throw new Error(`expect.yml の expect.${gate} は pass か fail のみです: ${value}`);
    }
  }

  return parsed;
}

/** ゲート実行結果の TSV を読む。列は <ゲート名> <exit code> <detected> <summary> */
export function parseActual(path) {
  const actual = {};
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    if (line.trim() === '') continue;
    const [gate, code, detected, ...rest] = line.split('\t');
    actual[gate] = { code: Number(code), detected, summary: rest.join('\t') };
  }
  return actual;
}

/**
 * 期待と実測を突き合わせ、独立した 2 つの判定を返す。
 *
 *   claimVerdict  手順書の主張（claimed_layer）どおりの層が止めたか。検証の本題。
 *   configVerdict expect の各ゲートの pass/fail が実測と一致するか。設定の回帰検出。
 *
 * error(2) が 1 つでもあれば両方 inconclusive とし、緑赤の推論をしない。
 * ツールが実行できなかっただけの状態を「欠陥を検出した」と読み違えないため。
 */
export function judge(expected, actual) {
  const entries = Object.entries(actual);
  const isDetectionGate = ([, r]) => r.detected === 'true' || r.detected === 'false';

  const errored = entries
    .filter(([, r]) => r.code !== CODE_PASS && r.code !== CODE_FAIL)
    .map(([gate]) => gate);

  // 非ブロックゲートは exit code で欠陥を主張しない。層の判定から外す。
  const blockedBy = entries
    .filter((e) => !isDetectionGate(e))
    .filter(([, r]) => r.code === CODE_FAIL)
    .map(([gate]) => gate);

  const blockingLayers = [...new Set(blockedBy.map(layerOfGate))];

  if (errored.length > 0) {
    return {
      claimVerdict: 'inconclusive',
      claimGateVerdict: 'inconclusive',
      configVerdict: 'inconclusive',
      errored,
      blockedBy,
      blockingLayers,
      mismatches: [],
      detectionMismatches: [],
    };
  }

  const mismatches = [];
  for (const [gate, want] of Object.entries(expected.expect)) {
    const result = actual[gate];
    if (result === undefined) {
      mismatches.push({ gate, expected: want, actual: 'not-run' });
      continue;
    }
    const got = result.code === CODE_FAIL ? 'fail' : 'pass';
    if (got !== want) {
      mismatches.push({ gate, expected: want, actual: got });
    }
  }

  // 非ブロックゲートは exit code ではなく出力内容で判定する（設計書 §8.1）。
  const detectionMismatches = [];
  for (const [gate, want] of Object.entries(expected.expectDetection)) {
    const result = actual[gate];
    if (result === undefined) {
      detectionMismatches.push({ gate, expected: want, actual: 'not-run' });
      continue;
    }
    const got = result.detected === 'true';
    if (got !== want) {
      detectionMismatches.push({ gate, expected: want, actual: got });
    }
  }

  let claimVerdict;
  if (blockedBy.length === 0) {
    claimVerdict = 'not-caught';
  } else if (blockingLayers.includes(expected.claimedLayer)) {
    claimVerdict = 'match';
  } else {
    claimVerdict = 'mismatch';
  }

  // 手順書がツール名を名指ししているケースだけ、ゲート粒度でも照合する。
  // 層は一致するが名指しされたツールは無反応、という形を表に出すため。
  let claimGateVerdict;
  if (expected.claimedGate === '') {
    claimGateVerdict = 'n/a';
  } else if (blockedBy.includes(expected.claimedGate)) {
    claimGateVerdict = 'match';
  } else {
    claimGateVerdict = 'mismatch';
  }

  return {
    claimVerdict,
    claimGateVerdict,
    configVerdict:
      mismatches.length === 0 && detectionMismatches.length === 0 ? 'match' : 'mismatch',
    errored,
    blockedBy,
    blockingLayers,
    mismatches,
    detectionMismatches,
  };
}

// CLI: node judge.mjs <expect.yml> <actual.tsv>
/* global process -- ベース設定は .mjs に Node のグローバルを与えないため、CLI 部分専用に宣言する */
if (process.argv[1]?.endsWith('judge.mjs') === true) {
  const [, , expectPath, actualPath] = process.argv;
  if (expectPath === undefined || actualPath === undefined) {
    process.stderr.write('usage: node judge.mjs <expect.yml> <actual.tsv>\n');
    process.exit(2);
  }
  const expected = parseExpect(expectPath);
  const actual = parseActual(actualPath);
  process.stdout.write(`${JSON.stringify({ ...judge(expected, actual), expected })}\n`);
}

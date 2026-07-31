import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { judge, parseActual, parseExpect } from './judge.mjs';

function writeTemp(name, content) {
  const dir = mkdtempSync(join(tmpdir(), 'judge-'));
  const path = join(dir, name);
  writeFileSync(path, content, 'utf8');
  return path;
}

const EXPECT_YML = `id: L1-02-explicit-any
pitfall: any で型チェックを回避する
claimed_layer: L1
expect:
  l2-install: pass
  l1-typecheck: pass
  l1-lint: fail
`;

test('parseExpect は限定形式の YAML を読める', () => {
  const parsed = parseExpect(writeTemp('expect.yml', EXPECT_YML));
  assert.equal(parsed.id, 'L1-02-explicit-any');
  assert.equal(parsed.pitfall, 'any で型チェックを回避する');
  assert.equal(parsed.claimedLayer, 'L1');
  assert.deepEqual(parsed.expect, {
    'l2-install': 'pass',
    'l1-typecheck': 'pass',
    'l1-lint': 'fail',
  });
});

test('parseExpect はコメント行と空行を無視する', () => {
  const withNoise = `# これはコメント\nid: X\n\npitfall: p\nclaimed_layer: L1\nexpect:\n  # 途中のコメント\n  l1-lint: fail\n`;
  const parsed = parseExpect(writeTemp('expect.yml', withNoise));
  assert.deepEqual(parsed.expect, { 'l1-lint': 'fail' });
});

// 以下 3 件は「構造は正しいが中身が不正」なケース。黙って通ると判定が
// 恒真／恒偽になり、ハーネスが何も検証しなくなる。
test('parseExpect は claimed_layer が L1〜L5 でなければ throw する', () => {
  const lower = `id: X\npitfall: p\nclaimed_layer: l1\nexpect:\n  l1-lint: fail\n`;
  assert.throws(() => parseExpect(writeTemp('expect.yml', lower)), /claimed_layer が不正/);
  const missing = `id: X\npitfall: p\nexpect:\n  l1-lint: fail\n`;
  assert.throws(() => parseExpect(writeTemp('expect.yml', missing)), /claimed_layer が不正/);
});

test('parseExpect は expect が空なら throw する', () => {
  const empty = `id: X\npitfall: p\nclaimed_layer: L1\nexpect:\n`;
  assert.throws(() => parseExpect(writeTemp('expect.yml', empty)), /expect が空/);
});

test('parseExpect は expect の値が pass/fail 以外なら throw する', () => {
  const quoted = `id: X\npitfall: p\nclaimed_layer: L1\nexpect:\n  l1-lint: "fail"\n`;
  assert.throws(() => parseExpect(writeTemp('expect.yml', quoted)), /pass か fail のみ/);
  const typo = `id: X\npitfall: p\nclaimed_layer: L1\nexpect:\n  l1-lint: faill\n`;
  assert.throws(() => parseExpect(writeTemp('expect.yml', typo)), /pass か fail のみ/);
});

test('parseActual は TSV を読める', () => {
  const tsv = 'l2-install\t0\t-\tok\nl1-typecheck\t0\t-\tok\nl1-lint\t1\t-\t3 problems\n';
  assert.deepEqual(parseActual(writeTemp('actual.tsv', tsv)), {
    'l2-install': { code: 0, detected: '-', summary: 'ok' },
    'l1-typecheck': { code: 0, detected: '-', summary: 'ok' },
    'l1-lint': { code: 1, detected: '-', summary: '3 problems' },
  });
});

test('judge は主張どおりの層が止めたとき claimVerdict を match とする', () => {
  const result = judge(
    {
      id: 'X',
      pitfall: 'p',
      claimedLayer: 'L1',
      claimedGate: '',
      expect: { 'l1-lint': 'fail', 'l1-typecheck': 'pass' },
      expectDetection: {},
    },
    {
      'l1-lint': { code: 1, detected: '-', summary: '' },
      'l1-typecheck': { code: 0, detected: '-', summary: '' },
    },
  );
  assert.equal(result.claimVerdict, 'match');
  assert.equal(result.configVerdict, 'match');
  assert.deepEqual(result.blockedBy, ['l1-lint']);
  assert.deepEqual(result.blockingLayers, ['L1']);
});

test('judge は主張と別の層が止めたとき claimVerdict を mismatch とする', () => {
  // 手順書は L2（OSV-Scanner）が止めると主張しているが、実際に止めたのは install だけ
  const result = judge(
    {
      id: 'X',
      pitfall: 'p',
      claimedLayer: 'L4',
      claimedGate: '',
      expect: { 'l2-install': 'fail' },
      expectDetection: {},
    },
    { 'l2-install': { code: 1, detected: '-', summary: '' } },
  );
  assert.equal(result.claimVerdict, 'mismatch');
  assert.deepEqual(result.blockingLayers, ['L2']);
});

test('judge はどのゲートも止めなかったとき claimVerdict を not-caught とする', () => {
  const result = judge(
    {
      id: 'X',
      pitfall: 'p',
      claimedLayer: 'L1',
      claimedGate: '',
      expect: { 'l1-lint': 'pass' },
      expectDetection: {},
    },
    { 'l1-lint': { code: 0, detected: '-', summary: '' } },
  );
  assert.equal(result.claimVerdict, 'not-caught');
  assert.deepEqual(result.blockedBy, []);
});

test('judge は expect と実測がずれたとき configVerdict を mismatch とする', () => {
  const result = judge(
    {
      id: 'X',
      pitfall: 'p',
      claimedLayer: 'L1',
      claimedGate: '',
      expect: { 'l1-lint': 'fail' },
      expectDetection: {},
    },
    { 'l1-lint': { code: 0, detected: '-', summary: '' } },
  );
  assert.equal(result.configVerdict, 'mismatch');
  assert.deepEqual(result.mismatches, [{ gate: 'l1-lint', expected: 'fail', actual: 'pass' }]);
});

test('judge は error(2) を含むケースを両方 inconclusive とする', () => {
  const result = judge(
    {
      id: 'X',
      pitfall: 'p',
      claimedLayer: 'L1',
      claimedGate: '',
      expect: { 'l1-lint': 'fail' },
      expectDetection: {},
    },
    { 'l1-lint': { code: 2, detected: '-', summary: 'docker が起動していない' } },
  );
  assert.equal(result.claimVerdict, 'inconclusive');
  assert.equal(result.configVerdict, 'inconclusive');
  assert.deepEqual(result.errored, ['l1-lint']);
});

test('judge は複数の層が止めた場合、主張の層が含まれていれば match とする', () => {
  const result = judge(
    {
      id: 'X',
      pitfall: 'p',
      claimedLayer: 'L1',
      claimedGate: '',
      expect: { 'l1-typecheck': 'fail', 'l1-lint': 'fail' },
      expectDetection: {},
    },
    {
      'l1-typecheck': { code: 1, detected: '-', summary: '' },
      'l1-lint': { code: 1, detected: '-', summary: '' },
    },
  );
  assert.equal(result.claimVerdict, 'match');
  assert.deepEqual(result.blockingLayers, ['L1']);
});

test('claimed_gate が指定され、そのゲートが止めたら claimGateVerdict は match', () => {
  const expected = {
    id: 'X', pitfall: 'p', claimedLayer: 'L2', claimedGate: 'l2-osv',
    expect: { 'l2-osv': 'fail' }, expectDetection: {},
  };
  const actual = { 'l2-osv': { code: 1, detected: '-', summary: '' } };
  const r = judge(expected, actual);
  assert.equal(r.claimVerdict, 'match');
  assert.equal(r.claimGateVerdict, 'match');
});

test('claimed_gate が指定され、同じ層の別ゲートが止めたら claimGateVerdict は mismatch', () => {
  const expected = {
    id: 'X', pitfall: 'p', claimedLayer: 'L2', claimedGate: 'l2-osv',
    expect: { 'l2-install': 'fail' }, expectDetection: {},
  };
  const actual = { 'l2-install': { code: 1, detected: '-', summary: '' } };
  const r = judge(expected, actual);
  assert.equal(r.claimVerdict, 'match', '層としては L2 が止めているので match');
  assert.equal(r.claimGateVerdict, 'mismatch', '名指しされた l2-osv は止めていない');
});

test('claimed_gate が無ければ claimGateVerdict は n/a', () => {
  const expected = {
    id: 'X', pitfall: 'p', claimedLayer: 'L1', claimedGate: '',
    expect: { 'l1-lint': 'fail' }, expectDetection: {},
  };
  const actual = { 'l1-lint': { code: 1, detected: '-', summary: '' } };
  assert.equal(judge(expected, actual).claimGateVerdict, 'n/a');
});

test('expect_detection と実測がずれたら configVerdict は mismatch', () => {
  const expected = {
    id: 'X', pitfall: 'p', claimedLayer: 'L2', claimedGate: '',
    expect: { 'l1-lint': 'pass' }, expectDetection: { 'l2-new-deps': true },
  };
  const actual = {
    'l1-lint': { code: 0, detected: '-', summary: '' },
    'l2-new-deps': { code: 0, detected: 'false', summary: '' },
  };
  const r = judge(expected, actual);
  assert.equal(r.configVerdict, 'mismatch');
  assert.deepEqual(r.detectionMismatches, [
    { gate: 'l2-new-deps', expected: true, actual: false },
  ]);
});

test('非ブロックゲートは fail しないので blockedBy に入らない', () => {
  const expected = {
    id: 'X', pitfall: 'p', claimedLayer: 'L2', claimedGate: '',
    expect: {}, expectDetection: { 'l2-new-deps': true },
  };
  const actual = { 'l2-new-deps': { code: 0, detected: 'true', summary: '' } };
  const r = judge(expected, actual);
  assert.deepEqual(r.blockedBy, []);
  assert.equal(r.claimVerdict, 'not-caught');
});

test('非ブロックゲートが error(2) なら inconclusive', () => {
  const expected = {
    id: 'X', pitfall: 'p', claimedLayer: 'L2', claimedGate: '',
    expect: { 'l1-lint': 'pass' }, expectDetection: { 'l2-new-deps': true },
  };
  const actual = {
    'l1-lint': { code: 0, detected: '-', summary: '' },
    'l2-new-deps': { code: 2, detected: 'false', summary: '' },
  };
  assert.equal(judge(expected, actual).claimVerdict, 'inconclusive');
});

test('parseActual は 4 列 TSV を読む', () => {
  const p = writeTemp('actual.tsv', 'a\t1\t-\tsummary with\ttab\nb\t0\ttrue\tok\n');
  const r = parseActual(p);
  assert.deepEqual(r.a, { code: 1, detected: '-', summary: 'summary with\ttab' });
  assert.deepEqual(r.b, { code: 0, detected: 'true', summary: 'ok' });
});

test('claimed_gate の層が claimed_layer と食い違ったら throw', () => {
  const p = writeTemp(
    'expect.yml',
    'id: X\npitfall: p\nclaimed_layer: L2\nclaimed_gate: l1-lint\nexpect:\n  l1-lint: fail\n',
  );
  assert.throws(() => parseExpect(p), /claimed_gate/);
});

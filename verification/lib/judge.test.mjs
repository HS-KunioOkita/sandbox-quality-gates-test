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

test('parseActual は TSV を読める', () => {
  const tsv = 'l2-install\t0\tok\nl1-typecheck\t0\tok\nl1-lint\t1\t3 problems\n';
  assert.deepEqual(parseActual(writeTemp('actual.tsv', tsv)), {
    'l2-install': { code: 0, summary: 'ok' },
    'l1-typecheck': { code: 0, summary: 'ok' },
    'l1-lint': { code: 1, summary: '3 problems' },
  });
});

test('judge は主張どおりの層が止めたとき claimVerdict を match とする', () => {
  const result = judge(
    { id: 'X', pitfall: 'p', claimedLayer: 'L1', expect: { 'l1-lint': 'fail', 'l1-typecheck': 'pass' } },
    { 'l1-lint': { code: 1, summary: '' }, 'l1-typecheck': { code: 0, summary: '' } },
  );
  assert.equal(result.claimVerdict, 'match');
  assert.equal(result.configVerdict, 'match');
  assert.deepEqual(result.blockedBy, ['l1-lint']);
  assert.deepEqual(result.blockingLayers, ['L1']);
});

test('judge は主張と別の層が止めたとき claimVerdict を mismatch とする', () => {
  // 手順書は L2（OSV-Scanner）が止めると主張しているが、実際に止めたのは install だけ
  const result = judge(
    { id: 'X', pitfall: 'p', claimedLayer: 'L4', expect: { 'l2-install': 'fail' } },
    { 'l2-install': { code: 1, summary: '' } },
  );
  assert.equal(result.claimVerdict, 'mismatch');
  assert.deepEqual(result.blockingLayers, ['L2']);
});

test('judge はどのゲートも止めなかったとき claimVerdict を not-caught とする', () => {
  const result = judge(
    { id: 'X', pitfall: 'p', claimedLayer: 'L1', expect: { 'l1-lint': 'pass' } },
    { 'l1-lint': { code: 0, summary: '' } },
  );
  assert.equal(result.claimVerdict, 'not-caught');
  assert.deepEqual(result.blockedBy, []);
});

test('judge は expect と実測がずれたとき configVerdict を mismatch とする', () => {
  const result = judge(
    { id: 'X', pitfall: 'p', claimedLayer: 'L1', expect: { 'l1-lint': 'fail' } },
    { 'l1-lint': { code: 0, summary: '' } },
  );
  assert.equal(result.configVerdict, 'mismatch');
  assert.deepEqual(result.mismatches, [{ gate: 'l1-lint', expected: 'fail', actual: 'pass' }]);
});

test('judge は error(2) を含むケースを両方 inconclusive とする', () => {
  const result = judge(
    { id: 'X', pitfall: 'p', claimedLayer: 'L1', expect: { 'l1-lint': 'fail' } },
    { 'l1-lint': { code: 2, summary: 'docker が起動していない' } },
  );
  assert.equal(result.claimVerdict, 'inconclusive');
  assert.equal(result.configVerdict, 'inconclusive');
  assert.deepEqual(result.errored, ['l1-lint']);
});

test('judge は複数の層が止めた場合、主張の層が含まれていれば match とする', () => {
  const result = judge(
    { id: 'X', pitfall: 'p', claimedLayer: 'L1', expect: { 'l1-typecheck': 'fail', 'l1-lint': 'fail' } },
    { 'l1-typecheck': { code: 1, summary: '' }, 'l1-lint': { code: 1, summary: '' } },
  );
  assert.equal(result.claimVerdict, 'match');
  assert.deepEqual(result.blockingLayers, ['L1']);
});

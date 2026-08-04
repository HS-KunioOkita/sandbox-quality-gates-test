import type { Config } from 'jest';

// 3 プロジェクトで共通の変換設定。ts-jest は tsconfig.spec.json を使う。
const common = {
  testEnvironment: 'node',
  transform: {
    '^.+\\.ts$': ['ts-jest', { tsconfig: '<rootDir>/tsconfig.spec.json' }],
  },
  moduleFileExtensions: ['ts', 'js', 'json'],
} satisfies Partial<Config>;

// Stryker からも参照する（jest.stryker.config.ts）。Stryker は mutant 1 つごとに
// テストを回すので、Testcontainers を使う integration / e2e を含めてはいけない
// （申し送り #28）。定義を 2 箇所に書くと片方だけ直す事故になるのでここを唯一の
// 情報源にする。
export const unitProject = {
  ...common,
  displayName: 'unit',
  rootDir: '.',
  testMatch: ['<rootDir>/src/**/*.spec.ts'],
};

const config: Config = {
  rootDir: '.',
  // 手順書 §4.1 は種別ごとにファイル名を分ける（*.int-spec.ts / *.e2e-spec.ts）。
  // ここを 1 つの testMatch で束ねると、`*.spec.ts` は `-spec.ts` 終わりの
  // ファイルにマッチしないため、統合テストと e2e が黙って実行されない。
  // 「テストを置いたのに Jest が拾わず緑のまま」は、このリポジトリが
  // 繰り返し踏んでいる「緑と守っているは別物」の型そのものである。
  projects: [
    unitProject,
    {
      ...common,
      displayName: 'integration',
      rootDir: '.',
      testMatch: ['<rootDir>/test/**/*.int-spec.ts'],
      // DB を立てるのはこのプロジェクトと e2e だけ。単体テストに持たせると
      // Docker が無い環境で単体テストまで巻き添えで落ちる。
      setupFilesAfterEnv: ['<rootDir>/test/setup-db.ts'],
      testTimeout: 120_000,
    },
    {
      ...common,
      displayName: 'e2e',
      rootDir: '.',
      testMatch: ['<rootDir>/test/**/*.e2e-spec.ts'],
      setupFilesAfterEnv: ['<rootDir>/test/setup-db.ts'],
      testTimeout: 120_000,
    },
  ],
  collectCoverageFrom: ['src/**/*.ts', '!src/**/*.spec.ts', '!src/main.ts', '!src/**/*.module.ts'],
  coverageDirectory: 'coverage',
};

export default config;

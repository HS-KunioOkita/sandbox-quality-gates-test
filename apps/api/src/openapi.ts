import 'reflect-metadata';
import { writeFileSync } from 'node:fs';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';

const OUTPUT = `${__dirname}/../../../openapi.json`;

async function main(): Promise<void> {
  // listen しない。スキーマを組み立てるだけなので DB 接続も不要である。
  const app = await NestFactory.create(AppModule, { logger: false });
  const config = new DocumentBuilder().setTitle('Orders API').setVersion('1.0').build();
  const document = SwaggerModule.createDocument(app, config);

  // 生成物の差分で drift を検出するので、キーの順序が実行ごとに揺れてはいけない。
  // JSON.stringify は挿入順を保つため、NestJS が同じ順序でメタデータを集める限り安定する。
  writeFileSync(OUTPUT, `${JSON.stringify(document, null, 2)}\n`);
  await app.close();
}

main().catch((cause: unknown) => {
  // eslint-disable-next-line no-console -- CLI なのでログ以外に伝える手段が無い
  console.error('OpenAPI の生成に失敗しました', cause);
  process.exit(1);
});

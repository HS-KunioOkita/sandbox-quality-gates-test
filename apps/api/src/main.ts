import 'reflect-metadata';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

const PORT = 3000;

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);

  app.enableCors({ origin: 'http://localhost:5173', allowedHeaders: ['content-type', 'x-user-id'] });
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
  );

  await app.listen(PORT);
}

bootstrap().catch((cause: unknown) => {
  // eslint-disable-next-line no-console -- 起動失敗はログ以外に伝える手段が無い
  console.error('API の起動に失敗しました', cause);
  process.exit(1);
});

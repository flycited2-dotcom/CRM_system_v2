const { createHash } = require('node:crypto');
const { readFile } = require('node:fs/promises');
const { NestFactory } = require('@nestjs/core');
const { AppModule } = require('./dist/src/app.module.js');
const { ClientsService } = require('./dist/src/clients/clients.service.js');

(async () => {
  const app = await NestFactory.createApplicationContext(AppModule, { logger: false });
  try {
    const service = app.get(ClientsService);
    const result = await service.storeFile({
      originalname: 'production-persistence-check.txt',
      mimetype: 'text/plain',
      size: 28,
      buffer: Buffer.from('production-persistence-check')
    });
    const contents = await readFile(result.storagePath);
    const hash = createHash('sha256').update(contents).digest('hex');

    console.log(`storage_path=${result.storagePath}`);
    console.log(`sha256=${hash}`);
  } finally {
    await app.close();
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});

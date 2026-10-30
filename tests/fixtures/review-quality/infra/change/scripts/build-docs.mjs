import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const SRC = 'docs';
const OUT = path.join('docs', 'dist');

const escapeHtml = (text) =>
  text.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

await mkdir(OUT, { recursive: true });
for (const name of await readdir(SRC)) {
  if (!name.endsWith('.md')) continue;
  const text = await readFile(path.join(SRC, name), 'utf8');
  const title = escapeHtml(name.replace(/\.md$/, ''));
  const html = `<!doctype html><meta charset="utf-8"><title>${title}</title><pre>${escapeHtml(text)}</pre>\n`;
  await writeFile(path.join(OUT, name.replace(/\.md$/, '.html')), html);
}

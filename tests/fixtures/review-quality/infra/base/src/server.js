import http from 'node:http';

const port = Number(process.env.PORT ?? 8080);

export const server = http.createServer((req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'content-type': 'text/plain' });
    res.end('ok');
    return;
  }
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ status: 'operational', checkedAt: new Date().toISOString() }));
});

if (process.env.NODE_ENV !== 'test') {
  server.listen(port, () => {
    console.log(`status-api listening on :${port}`);
  });
  process.on('SIGTERM', () => server.close(() => process.exit(0)));
}

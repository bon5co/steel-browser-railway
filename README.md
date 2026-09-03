# steel-browser-railway

Thin wrapper around [`ghcr.io/steel-dev/steel-browser`](https://github.com/steel-dev/steel-browser)
for a one-click Railway template.

Steel Browser is an open-source Browser API for AI agents (sessions, CDP,
scraping, screenshots, PDF, a proxy). Upstream ships **no authentication of any
kind**, and the vendor's own Railway template publishes it on a public domain —
so anyone who finds the URL can create browser sessions, drive Chromium over
CDP, scrape and proxy through the instance on the deployer's bill and IP, and
reach the deployer's own `*.railway.internal` services.

This wrapper keeps the upstream image pinned by digest and inserts an nginx
gateway that:

- listens on Railway's injected `$PORT` and forces the app onto `127.0.0.1:3000`;
- requires `STEEL_API_KEY` on every route except `/v1/health` (the healthcheck),
  accepted as `Authorization: Bearer <key>`, `x-api-key: <key>`, or
  `?apiKey=<key>` (the query form is needed because a CDP WebSocket client
  cannot set request headers);
- refuses to boot on an empty `STEEL_API_KEY`.

The image adds no packages — nginx is already present in the upstream image.

## Build

Pushed to `ghcr.io/bon5co/steel-browser-railway:latest` by GitHub Actions on
every push to `main`.

# Steel Browser for Railway.
#
# Upstream (ghcr.io/steel-dev/steel-browser) ships a Browser API for AI agents
# that has NO authentication of any kind — no API key, no bearer token, no
# basic auth anywhere in api/src. The vendor's own Railway template publishes
# it on a public domain, so any stranger who finds the URL can create browser
# sessions, drive Chromium over CDP, scrape and proxy through the deployer's
# instance on the deployer's bill and IP, and reach the deployer's own
# *.railway.internal services from inside the project.
#
# This wrapper keeps the same pinned image and inserts an nginx gateway that:
#   * listens on Railway's injected $PORT and forces the app onto 3000,
#   * requires STEEL_API_KEY on every route except /v1/health (the
#     healthcheck), accepting it as `Authorization: Bearer <key>`,
#     `x-api-key: <key>`, or `?apiKey=<key>` (the query form is required
#     because a CDP WebSocket client cannot set request headers),
#   * refuses to boot on an empty STEEL_API_KEY.
#
# nginx is already installed in the upstream image and its entrypoint already
# runs it (for the internal 9223->9222 CDP redirect), so this adds no packages.
FROM ghcr.io/steel-dev/steel-browser@sha256:6dd29f73c33bb0f5bc9d950e8e4492c3f8458a06313346fa1767f68936a36fc8

# Railway terminates TLS at its edge, so the app must advertise wss:// URLs.
ENV USE_SSL=true

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]

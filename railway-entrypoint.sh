#!/bin/sh
# Boot wrapper for Steel Browser on Railway.
#
# Upstream has no authentication anywhere in its API, so the vendor's own
# public template lets any stranger create sessions, drive CDP, scrape and
# proxy on the deployer's bill and IP. This wrapper puts an nginx gateway in
# front of the app that requires STEEL_API_KEY on every route except the
# healthcheck, and forces the app onto an internal port so the gateway owns
# the public one.
set -eu

log() { echo "[railway-entrypoint] $*"; }

# --- credentials ------------------------------------------------------------
if [ -z "${STEEL_API_KEY:-}" ]; then
  log "FATAL: STEEL_API_KEY is empty. Refusing to expose an unauthenticated browser API."
  exit 1
fi

# Railway's secret(n) is alphanumeric, so the key is regex- and nginx-safe. Be
# defensive anyway: reject anything that is not a plain alphanumeric token, so
# nothing in it can break the nginx match below.
if ! printf '%s' "$STEEL_API_KEY" | grep -Eq '^[A-Za-z0-9]+$'; then
  log "FATAL: STEEL_API_KEY must be alphanumeric only."
  exit 1
fi

# --- ports ------------------------------------------------------------------
# Railway injects PORT and its HTTP healthcheck dials that injected value, so
# the gateway must own it. The app reads env.PORT (default 3000); force it onto
# 3000 internally and give the gateway the injected port.
GATEWAY_PORT="${PORT:-8080}"
export PORT=3000
export HOST=0.0.0.0

# The app builds session websocketUrl from DOMAIN; point it at the public
# Railway domain so returned wss:// URLs are reachable. Kept out of the
# published template variables (derived from RAILWAY_PUBLIC_DOMAIN at boot).
if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  export DOMAIN="${RAILWAY_PUBLIC_DOMAIN}"
  log "DOMAIN=${DOMAIN}"
fi
log "gateway on ${GATEWAY_PORT}, app on 127.0.0.1:${PORT}"

# --- gateway config ---------------------------------------------------------
# Auth is granted when the key appears as `Authorization: Bearer <key>`,
# `x-api-key: <key>`, or `?apiKey=<key>`. The query form is required because a
# CDP WebSocket client (puppeteer connect) cannot set request headers.
# The three candidate values are joined with '|' (absent from an alphanumeric
# key) and one regex tests whether any field equals the key.
CONF=/app/api/railway-nginx.conf
cat > "$CONF" <<NGINX
events {
    worker_connections 1024;
}

http {
    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        ''      close;
    }

    # Strip the "Bearer " prefix from Authorization, if present.
    map \$http_authorization \$auth_bearer {
        default "";
        "~*^Bearer\\s+(.+)\$" \$1;
    }

    # Grant access if any of the three key sources equals STEEL_API_KEY.
    map "\$auth_bearer|\$http_x_api_key|\$arg_apiKey" \$auth_ok {
        default 0;
        "~(^|\\|)${STEEL_API_KEY}(\\||\$)" 1;
    }

    server {
        listen ${GATEWAY_PORT};
        server_name _;
        client_max_body_size 512m;

        # Open for Railway's healthcheck only.
        location = /v1/health {
            proxy_pass http://127.0.0.1:3000;
            proxy_set_header Host \$host;
        }

        location / {
            if (\$auth_ok = 0) {
                add_header Content-Type application/json always;
                return 401 '{"error":"unauthorized","message":"provide STEEL_API_KEY via Authorization: Bearer, x-api-key header, or ?apiKey= query"}';
            }
            proxy_pass http://127.0.0.1:3000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
            proxy_buffering off;
            proxy_request_buffering off;
            chunked_transfer_encoding on;
        }
    }

    # Internal CDP redirect (upstream's own 9223 -> 9222), kept for tooling
    # inside the project network. Not exposed publicly by Railway.
    server {
        listen 9223;
        location / {
            proxy_pass http://127.0.0.1:9222;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            gzip off;
            proxy_set_header Accept-Encoding "";
            proxy_read_timeout 86400;
            proxy_send_timeout 86400;
            proxy_buffering off;
            proxy_request_buffering off;
            chunked_transfer_encoding on;
        }
    }
}
NGINX

nginx -t -c "$CONF"
nginx -c "$CONF"
log "gateway up; handing off to upstream entrypoint (--no-nginx)"

cd /app
exec /app/api/entrypoint.sh --no-nginx

###############
# BUILD STAGE #
###############
# Use Playwright image with browsers and deps preinstalled for running E2E tests
FROM mcr.microsoft.com/playwright:v1.54.2-jammy AS builder

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential \
    python3 \
    pkg-config \
    libsqlite3-dev \
    sqlite3 \
    bash \
    curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./

# Install all dependencies
RUN npm install --no-audit --no-fund

# Copy source code
COPY . ./

# Build frontend
RUN NODE_ENV=production npm run frontend:build

# Cleanup
RUN npm cache clean --force && \
    rm -rf ~/.npm /tmp/*


####################
# Production stage #
####################
FROM node:22-slim AS production

ENV APP_UID=1001
ENV APP_GID=1001

# Create a non-root user and group (Debian-compatible commands)
RUN groupadd --gid ${APP_GID} app && \
    useradd --uid ${APP_UID} --gid ${APP_GID} --shell /bin/bash --create-home app

# Install production dependencies (Debian-compatible commands)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    sqlite3 \
    openssl \
    curl \
    procps \
    dumb-init \
    bash \
    su-exec && \
    # Clean up to reduce image size
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy necessary files and set permissions
COPY --chown=app:app ./backend/ /app/backend/
RUN chmod +x /app/backend/cmd/start.sh

COPY --chown=app:app ./scripts/docker-entrypoint.sh /app/scripts/docker-entrypoint.sh
RUN chmod +x /app/scripts/docker-entrypoint.sh

COPY --from=builder --chown=app:app /app/dist ./backend/dist
COPY --from=builder --chown=app:app /app/public/locales ./backend/dist/locales
COPY --from=builder --chown=app:app /app/node_modules ./node_modules
COPY --from=builder --chown=app:app /app/package.json /app/

RUN mkdir -p /app/backend/db /app/backend/certs /app/backend/uploads && \
    chown -R app:app /app

VOLUME ["/app/backend/db", "/app/backend/uploads"]

EXPOSE 3002

ENV NODE_ENV=production \
    DB_FILE="db/production.sqlite3" \
    PORT=3002 \
    TUDUDI_ALLOWED_ORIGINS="http://localhost:8080,http://localhost:3002,http://127.0.0.1:8080,http://127.0.0.1:3002" \
    TUDUDI_SESSION_SECRET="" \
    TUDUDI_USER_EMAIL="" \
    TUDUDI_USER_PASSWORD="" \
    DISABLE_TELEGRAM=false \
    DISABLE_SCHEDULER=false \
    TUDUDI_UPLOAD_PATH="/app/backend/uploads"

HEALTHCHECK --interval=60s --timeout=3s --start-period=10s --retries=2 \
    CMD curl -sf http://localhost:3002/api/health || exit 1

WORKDIR /app/backend
ENTRYPOINT ["/app/scripts/docker-entrypoint.sh"]

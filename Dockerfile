FROM node:18-alpine AS base

FROM base AS deps

RUN apk add --no-cache libc6-compat

WORKDIR /app

COPY package.json yarn.lock ./

RUN yarn config set registry 'https://registry.npmmirror.com/'
RUN yarn install

FROM base AS builder

RUN apk update && apk add --no-cache git

ENV OPENAI_API_KEY=""
ENV GOOGLE_API_KEY=""
ENV CODE=""

WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN yarn build

FROM base AS runner
WORKDIR /app

# Install necessary packages.
# Add curl temporarily for downloads in the RUN step below
RUN apk add --no-cache proxychains-ng tar bash curl

# TARGETPLATFORM is set automatically by buildx
ARG TARGETPLATFORM

ENV PROXY_URL=""
ENV OPENAI_API_KEY=""
ENV GOOGLE_API_KEY=""
ENV CODE=""
ENV ENABLE_MCP=""
ENV HUMANITEC_TOKEN=""
ENV MINIO_ENDPOINT=""
ENV MINIO_ACCESS_KEY_ID=""
ENV MINIO_SECRET_ACCESS_KEY=""
ENV MINIO_BUCKET=""
ENV MINIO_USE_SSL=""



COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.next/server ./.next/server


RUN mkdir -p /app/app/mcp && chmod 777 /app/app/mcp
COPY --from=builder /app/app/mcp/mcp_config.default.json /app/app/mcp/mcp_config.json

# Install humctl and canyon-cli based on TARGETPLATFORM during build
RUN set -eux; \
    echo "Installing tools for TARGETPLATFORM=${TARGETPLATFORM:-linux/amd64}..."; \
    \
    # Determine architecture for humctl
    HUMCTL_ARCH=""; \
    case "${TARGETPLATFORM}" in \
      linux/amd64) HUMCTL_ARCH="amd64"; ;; \
      linux/arm64) HUMCTL_ARCH="arm64"; ;; \
      *) echo "Unsupported architecture for humctl: ${TARGETPLATFORM}"; exit 1; ;; \
    esac; \
    HUMCTL_VERSION="v0.39.2"; \
    HUMCTL_FILENAME="cli_${HUMCTL_VERSION#v}_linux_${HUMCTL_ARCH}.tar.gz"; \
    HUMCTL_URL="https://github.com/humanitec/cli/releases/download/${HUMCTL_VERSION}/${HUMCTL_FILENAME}"; \
    echo "Downloading humctl version ${HUMCTL_VERSION} for architecture ${HUMCTL_ARCH} from ${HUMCTL_URL}"; \
    curl -fSL "${HUMCTL_URL}" -o /tmp/humctl.tar.gz; \
    echo "Extracting humctl..."; \
    tar xzf /tmp/humctl.tar.gz -C /usr/local/bin; \
    rm /tmp/humctl.tar.gz; \
    chmod +x /usr/local/bin/humctl; \
    echo "humctl installed successfully."; \
    \
    # Determine architecture for canyon-cli
    CANYON_ARCH=""; \
    case "${TARGETPLATFORM}" in \
      linux/amd64) CANYON_ARCH="amd64"; ;; \
      linux/arm64) CANYON_ARCH="arm64"; ;; \
      *) echo "Unsupported architecture for canyon-cli: ${TARGETPLATFORM}"; exit 1; ;; \
    esac; \
    CANYON_VERSION="v0.3.0"; \
    CANYON_FILENAME="canyon-cli-cloud_${CANYON_VERSION#v}_linux_${CANYON_ARCH}.tar.gz"; \
    CANYON_URL="https://github.com/DominicJamesWhite/canyon-cli-cloud/releases/download/${CANYON_VERSION}/${CANYON_FILENAME}"; \
    echo "Downloading canyon-cli-cloud version ${CANYON_VERSION} for architecture ${CANYON_ARCH} from ${CANYON_URL}"; \
    mkdir -p /app/bin; \
    curl -fSL "${CANYON_URL}" -o /tmp/canyon.tar.gz; \
    echo "Extracting canyon-cli..."; \
    tar xzf /tmp/canyon.tar.gz -C /app/bin canyon; \
    rm /tmp/canyon.tar.gz; \
    chmod +x /app/bin/canyon; \
    echo "canyon-cli installed successfully to /app/bin/canyon."; \
    \
    # Clean up temporary packages and cache
    apk del curl; \
    rm -rf /var/cache/apk/*

EXPOSE 3000

# Simplified CMD: Run the server
CMD ["sh", "-c", "\
    # Run the application \n\
    echo \"Starting server...\" && \n\
    if [ -n \"$PROXY_URL\" ]; then \n\
      export HOSTNAME=\"::\"; \n\
      protocol=$(echo $PROXY_URL | cut -d: -f1); \n\
      host=$(echo $PROXY_URL | cut -d/ -f3 | cut -d: -f1); \n\
      port=$(echo $PROXY_URL | cut -d: -f3); \n\
      conf=/etc/proxychains.conf; \n\
      echo \"strict_chain\" > $conf; \n\
      echo \"proxy_dns\" >> $conf; \n\
      echo \"remote_dns_subnet 224\" >> $conf; \n\
      echo \"tcp_read_time_out 15000\" >> $conf; \n\
      echo \"tcp_connect_time_out 8000\" >> $conf; \n\
      echo \"localnet 127.0.0.0/255.0.0.0\" >> $conf; \n\
      echo \"localnet ::1/128\" >> $conf; \n\
      echo \"[ProxyList]\" >> $conf; \n\
      echo \"$protocol $host $port\" >> $conf; \n\
      echo \"Using proxychains with config:\" && cat /etc/proxychains.conf; \n\
      proxychains -f $conf node server.js; \n\
    else \n\
      export HOSTNAME=\"::\"; \n\
      node server.js; \n\
    fi \
"]

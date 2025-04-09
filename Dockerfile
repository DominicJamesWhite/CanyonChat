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

RUN apk add --no-cache proxychains-ng curl tar

ENV PROXY_URL=""
ENV OPENAI_API_KEY=""
ENV GOOGLE_API_KEY=""
ENV CODE=""
ENV ENABLE_MCP=""
ENV HUMANITEC_TOKEN=""

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.next/server ./.next/server
COPY --from=builder /app/app/mcp ./app/mcp

EXPOSE 3000

CMD echo "Listing contents of /app/app/mcp before starting server:" && \
    ls -la /app/app/mcp && \
    echo "-----------------------------------------------------" && \
    echo "Installing humctl..." && \
    HUMCTL_ARCH=$(uname -m) && \
    HUMCTL_VERSION="v0.39.2" && \
    if [ "$HUMCTL_ARCH" = "x86_64" ]; then HUMCTL_ARCH="amd64"; \
    elif [ "$HUMCTL_ARCH" = "aarch64" ]; then HUMCTL_ARCH="arm64"; fi && \
    HUMCTL_FILENAME="cli_${HUMCTL_VERSION#v}_linux_${HUMCTL_ARCH}.tar.gz" && \
    HUMCTL_URL="https://github.com/humanitec/cli/releases/download/${HUMCTL_VERSION}/${HUMCTL_FILENAME}" && \
    echo "Downloading humctl version ${HUMCTL_VERSION} for architecture ${HUMCTL_ARCH} from ${HUMCTL_URL}" && \
    curl -fSL "$HUMCTL_URL" -o /tmp/humctl.tar.gz && \
    echo "Extracting humctl..." && \
    tar xzf /tmp/humctl.tar.gz -C /usr/local/bin && \
    rm /tmp/humctl.tar.gz && \
    chmod +x /usr/local/bin/humctl && \
    echo "humctl installed successfully." && \
    \
    echo "Installing canyon-cli..." && \
    CANYON_ARCH=$(uname -m) && \
    CANYON_VERSION="v0.0.7" && \
    if [ "$CANYON_ARCH" = "x86_64" ]; then CANYON_ARCH="amd64"; \
    elif [ "$CANYON_ARCH" = "aarch64" ]; then CANYON_ARCH="arm64"; fi && \
    CANYON_FILENAME="canyon-cli_${CANYON_VERSION#v}_linux_${CANYON_ARCH}.tar.gz" && \
    CANYON_URL="https://github.com/humanitec/canyon-cli/releases/download/${CANYON_VERSION}/${CANYON_FILENAME}" && \
    echo "Downloading canyon-cli version ${CANYON_VERSION} for architecture ${CANYON_ARCH} from ${CANYON_URL}" && \
    mkdir -p /app/bin && \
    curl -fSL "$CANYON_URL" -o /tmp/canyon.tar.gz && \
    echo "Extracting canyon-cli..." && \
    tar xzf /tmp/canyon.tar.gz -C /app/bin canyon && \
    rm /tmp/canyon.tar.gz && \
    chmod +x /app/bin/canyon && \
    echo "canyon-cli installed successfully to /app/bin/canyon." && \
    \
    if [ -n "$PROXY_URL" ]; then \
    export HOSTNAME="0.0.0.0"; \
    protocol=$(echo $PROXY_URL | cut -d: -f1); \
    host=$(echo $PROXY_URL | cut -d/ -f3 | cut -d: -f1); \
    port=$(echo $PROXY_URL | cut -d: -f3); \
    conf=/etc/proxychains.conf; \
    echo "strict_chain" > $conf; \
    echo "proxy_dns" >> $conf; \
    echo "remote_dns_subnet 224" >> $conf; \
    echo "tcp_read_time_out 15000" >> $conf; \
    echo "tcp_connect_time_out 8000" >> $conf; \
    echo "localnet 127.0.0.0/255.0.0.0" >> $conf; \
    echo "localnet ::1/128" >> $conf; \
    echo "[ProxyList]" >> $conf; \
    echo "$protocol $host $port" >> $conf; \
    cat /etc/proxychains.conf; \
    proxychains -f $conf node server.js; \
    else \
    node server.js; \
    fi

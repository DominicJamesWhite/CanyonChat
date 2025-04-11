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

# Install necessary packages including Python3 and bash for gcloud
RUN apk add --no-cache proxychains-ng curl tar python3 py3-crcmod bash

# Install Google Cloud SDK
ENV CLOUD_SDK_VERSION=460.0.0
RUN curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${CLOUD_SDK_VERSION}-linux-$(uname -m).tar.gz && \
    tar xzf google-cloud-cli-${CLOUD_SDK_VERSION}-linux-$(uname -m).tar.gz && \
    rm google-cloud-cli-${CLOUD_SDK_VERSION}-linux-$(uname -m).tar.gz && \
    ./google-cloud-sdk/install.sh --quiet --usage-reporting false --path-update true && \
    # Add gcloud to PATH for subsequent RUN/CMD instructions
    export PATH="/google-cloud-sdk/bin:$PATH" && \
    # Clean up installation directory to reduce image size (optional)
    rm -rf /google-cloud-sdk/.install

# Set PATH for future commands in the container
ENV PATH /google-cloud-sdk/bin:$PATH

ENV PROXY_URL=""
ENV OPENAI_API_KEY=""
ENV GOOGLE_API_KEY=""
ENV CODE=""
ENV ENABLE_MCP=""
ENV HUMANITEC_TOKEN=""
# GCP_SERVICE_ACCOUNT_KEY_JSON will hold the key content if provided
ENV GCP_SERVICE_ACCOUNT_KEY_JSON=""

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.next/server ./.next/server


RUN mkdir -p /app/app/mcp && chmod 777 /app/app/mcp
COPY --from=builder /app/app/mcp/mcp_config.default.json /app/app/mcp/mcp_config.json

EXPOSE 3000

CMD # Define the path for the dynamic credentials file within the script
    GCP_KEY_PATH="/app/gcp-key.json" && \
    # Setup GCP credentials dynamically if provided
    if [ -n "$GCP_SERVICE_ACCOUNT_KEY_JSON" ]; then \
      echo "Creating GCP key file from environment variable..." && \
      echo "$GCP_SERVICE_ACCOUNT_KEY_JSON" > "$GCP_KEY_PATH" && \
      export GOOGLE_APPLICATION_CREDENTIALS="$GCP_KEY_PATH" && \
      echo "GOOGLE_APPLICATION_CREDENTIALS set to $GCP_KEY_PATH" ; \
    else \
      echo "GCP_SERVICE_ACCOUNT_KEY_JSON not set. Unsetting GOOGLE_APPLICATION_CREDENTIALS." ; \
      unset GOOGLE_APPLICATION_CREDENTIALS ; \
    fi && \
    # Original CMD starts here
    echo "Listing contents of /app/app/mcp before starting server:" && \
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
    CANYON_VERSION="v0.1.0" && \
    if [ "$CANYON_ARCH" = "x86_64" ]; then CANYON_ARCH="amd64"; \
    elif [ "$CANYON_ARCH" = "aarch64" ]; then CANYON_ARCH="arm64"; fi && \
    CANYON_FILENAME="canyon-cli-cloud_${CANYON_VERSION#v}_linux_${CANYON_ARCH}.tar.gz" && \
    CANYON_URL="https://github.com/DominicJamesWhite/canyon-cli-cloud/releases/download/${CANYON_VERSION}/${CANYON_FILENAME}" && \
    echo "Downloading canyon-cli-cloud version ${CANYON_VERSION} for architecture ${CANYON_ARCH} from ${CANYON_URL}" && \
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
    export HOSTNAME="0.0.0.0"; \
    node server.js; \
    fi

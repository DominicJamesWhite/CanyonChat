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
# Using the official install script is more robust than downloading a specific version URL
# Pass --disable-prompts and --install-dir to the outer script.
# The inner install.sh will be called with appropriate flags by the outer script.
RUN curl -sSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir=/usr/local

# Set PATH for future commands in the container
# Update PATH to reflect the chosen installation directory.
ENV PATH /usr/local/google-cloud-sdk/bin:$PATH

ENV PROXY_URL=""
ENV OPENAI_API_KEY=""
ENV GOOGLE_API_KEY=""
ENV CODE=""
ENV ENABLE_MCP=""
ENV HUMANITEC_TOKEN=""
ENV GCP_SERVICE_ACCOUNT_KEY_JSON=""

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/.next/server ./.next/server


RUN mkdir -p /app/app/mcp && chmod 777 /app/app/mcp
COPY --from=builder /app/app/mcp/mcp_config.default.json /app/app/mcp/mcp_config.json

EXPOSE 3000

CMD ["sh", "-c", "\
    # Define the path for the dynamic credentials file within the script \n\
    GCP_KEY_PATH=\"/app/gcp-key.json\" && \n\
    # Setup GCP credentials dynamically if provided \n\
    if [ -n \"$GCP_SERVICE_ACCOUNT_KEY_JSON\" ]; then \n\
      echo \"Creating GCP key file from environment variable...\" && \n\
      echo \"$GCP_SERVICE_ACCOUNT_KEY_JSON\" > \"$GCP_KEY_PATH\" && \n\
      export GOOGLE_APPLICATION_CREDENTIALS=\"$GCP_KEY_PATH\" && \n\
      echo \"GOOGLE_APPLICATION_CREDENTIALS set to $GCP_KEY_PATH\" ; \n\
    else \n\
      echo \"GCP_SERVICE_ACCOUNT_KEY_JSON not set. Unsetting GOOGLE_APPLICATION_CREDENTIALS.\" ; \n\
      unset GOOGLE_APPLICATION_CREDENTIALS ; \n\
    fi && \n\
    # Original CMD starts here \n\
    echo \"Listing contents of /app/app/mcp before starting server:\" && \n\
    ls -la /app/app/mcp && \n\
    echo \"-----------------------------------------------------\" && \n\
    echo \"Installing humctl...\" && \n\
    HUMCTL_ARCH=$(uname -m) && \n\
    HUMCTL_VERSION=\"v0.39.2\" && \n\
    if [ \"$HUMCTL_ARCH\" = \"x86_64\" ]; then HUMCTL_ARCH=\"amd64\"; \n\
    elif [ \"$HUMCTL_ARCH\" = \"aarch64\" ]; then HUMCTL_ARCH=\"arm64\"; fi && \n\
    HUMCTL_FILENAME=\"cli_${HUMCTL_VERSION#v}_linux_${HUMCTL_ARCH}.tar.gz\" && \n\
    HUMCTL_URL=\"https://github.com/humanitec/cli/releases/download/${HUMCTL_VERSION}/${HUMCTL_FILENAME}\" && \n\
    echo \"Downloading humctl version ${HUMCTL_VERSION} for architecture ${HUMCTL_ARCH} from ${HUMCTL_URL}\" && \n\
    curl -fSL \"$HUMCTL_URL\" -o /tmp/humctl.tar.gz && \n\
    echo \"Extracting humctl...\" && \n\
    tar xzf /tmp/humctl.tar.gz -C /usr/local/bin && \n\
    rm /tmp/humctl.tar.gz && \n\
    chmod +x /usr/local/bin/humctl && \n\
    echo \"humctl installed successfully.\" && \n\
    \n\
    echo \"Installing canyon-cli...\" && \n\
    CANYON_ARCH=$(uname -m) && \n\
    CANYON_VERSION=\"v0.2.1\" && \n\
    if [ \"$CANYON_ARCH\" = \"x86_64\" ]; then CANYON_ARCH=\"amd64\"; \n\
    elif [ \"$CANYON_ARCH\" = \"aarch64\" ]; then CANYON_ARCH=\"arm64\"; fi && \n\
    CANYON_FILENAME=\"canyon-cli-cloud_${CANYON_VERSION#v}_linux_${CANYON_ARCH}.tar.gz\" && \n\
    CANYON_URL=\"https://github.com/DominicJamesWhite/canyon-cli-cloud/releases/download/${CANYON_VERSION}/${CANYON_FILENAME}\" && \n\
    echo \"Downloading canyon-cli-cloud version ${CANYON_VERSION} for architecture ${CANYON_ARCH} from ${CANYON_URL}\" && \n\
    mkdir -p /app/bin && \n\
    curl -fSL \"$CANYON_URL\" -o /tmp/canyon.tar.gz && \n\
    echo \"Extracting canyon-cli...\" && \n\
    tar xzf /tmp/canyon.tar.gz -C /app/bin canyon && \n\
    rm /tmp/canyon.tar.gz && \n\
    chmod +x /app/bin/canyon && \n\
    echo \"canyon-cli installed successfully to /app/bin/canyon.\" && \n\
    \n\
    if [ -n \"$PROXY_URL\" ]; then \n\
    export HOSTNAME=\"0.0.0.0\"; \n\
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
    cat /etc/proxychains.conf; \n\
    proxychains -f $conf node server.js; \n\
    else \n\
    export HOSTNAME=\"0.0.0.0\"; \n\
    node server.js; \n\
    fi \
"]

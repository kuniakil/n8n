FROM node:20-bullseye-slim

# Install build tools (required for native modules like isolated-vm in n8n)
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        python3 \
    && rm -rf /var/lib/apt/lists/*

# Install n8n 2.22.6 (via npm)
RUN npm install -g n8n@2.22.6 --unsafe-perm && npm cache clean --force

# Install kubectl
RUN apt-get update && apt-get install -y wget ca-certificates \
    && wget -q "https://dl.k8s.io/release/stable.txt" -O /tmp/k8s-version.txt \
    && K8S_VERSION=$(cat /tmp/k8s-version.txt) \
    && wget -q "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl" -O /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && rm /tmp/k8s-version.txt \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install local embedding package
RUN npm install -g @xenova/transformers --unsafe-perm && npm cache clean --force

# Create n8n expected directory structure
RUN mkdir -p /home/node/.n8n && chown -R node:node /home/node/.n8n

USER node
WORKDIR /home/node

# Environment variables
ENV NODE_FUNCTION_ALLOW_BUILTIN=crypto,child_process
ENV NODE_FUNCTION_ALLOW_EXTERNAL=*
ENV N8N_BLOCK_EXTERNAL_EXECUTION=false
ENV HF_HOME=/home/node/.n8n/.cache/huggingface
ENV N8N_USER_FOLDER=/home/node/.n8n

# Use n8n's own entrypoint
ENTRYPOINT ["n8n"]
CMD ["start"]

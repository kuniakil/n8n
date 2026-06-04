FROM ghcr.io/n8n-io/n8n:2.22.6-debian

USER root

# Download kubectl directly using wget or curl
RUN wget -q "https://dl.k8s.io/release/stable.txt" -O /tmp/k8s-version.txt \
    && K8S_VERSION=$(cat /tmp/k8s-version.txt) \
    && wget -q "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl" -O /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && rm /tmp/k8s-version.txt

# Install @xenova/transformers for local embedding (replaces external embedding API, no quota)
RUN npm install -g @xenova/transformers && npm cache clean --force

USER node

# HuggingFace model cache location (persistent via hostPath, no re-download on pod restart)
ENV HF_HOME=/home/node/.n8n/.cache/huggingface

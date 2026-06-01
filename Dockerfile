FROM docker.n8n.io/n8nio/n8n:latest

USER root

# 安裝 kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# 換回 n8n 預設使用者，保持安全
USER node

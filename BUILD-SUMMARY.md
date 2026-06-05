# n8n 客製化 Image Build 摘要

**Date:** 2026-06-04
**Image:** `ghcr.io/kuniakil/n8n:2.22.6-custom`
**Repository:** https://github.com/kuniakil/n8n
**Base Image:** `node:22.16-bullseye-slim`

---

## 目的

建立一個客製化 n8n image 包含：
1. n8n 2.22.6（鎖定版本，DB schema 相容）
2. `@xenova/transformers` 套件（本地 embedding，避免外部 API quota 限制）
3. `kubectl`（K8s 整合用）

---

## 問題排查歷程

### 1. 官方 `n8n:X.Y.Z-debian` tag 不存在

官方 `ghcr.io/n8n-io/n8n` registry 只有 `latest-debian`，沒有任何具體版本 + `-debian` 後綴的 tag。

```bash
$ docker manifest inspect ghcr.io/n8n-io/n8n:2.25.3-debian
# → not found
```

### 2. Alpine base 的 ONNX runtime 會 segfault

`ghcr.io/n8n-io/n8n:X.Y.Z` (Alpine) 是 musl libc 環境，ONNX runtime binary 是 glibc 動態連結，會 segfault：

```bash
$ docker run --rm ghcr.io/n8n-io/n8n:2.22.6 \
    node -e "require('@xenova/transformers')"
# → Segmentation fault (exit code 139)
```

`latest-debian` 雖然是 Debian，但對應 n8n 2.22.0，跟 DB schema (2.22.6) 不相容。

### 3. Node 20 編譯 `isolated-vm` 失敗

`isolated-vm` 用了 V8 API `v8::SourceLocation`，這個 API 在 Node 20 沒有。`isolated-vm` 4.x 不行，5+ 才有。

```
error: 'SourceLocation' in namespace 'v8' does not name a type
make: *** Error 1
```

查 n8n 2.22.6 `engines` 發現：
```json
"engines": { "node": ">=22.16" }
```

→ 必須用 Node 22.16+。

### 4. USER node 找不到 global npm package

`npm install -g` 裝到 `/usr/local/lib/node_modules`（root 擁有），但 n8n 跑在 `USER node`。Node module 解析路徑預設不含 `/usr/local/lib/node_modules`，需要 `ENV NODE_PATH`。

---

## 最終 Dockerfile

`/Users/mlee/n8n/Dockerfile`:

```dockerfile
FROM node:22.16-bullseye-slim

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
ENV NODE_PATH=/usr/local/lib/node_modules

# Use n8n's own entrypoint
ENTRYPOINT ["n8n"]
CMD ["start"]
```

---

## CI/CD

**Workflow:** `.github/workflows/docker-release.yml`
- 手動觸發 (`workflow_dispatch`)
- 支援 amd64 + arm64 multi-platform
- Push 到 `ghcr.io/kuniakil/n8n`
- 使用 GHA cache 加速

**觸發指令：**
```bash
gh workflow run docker-release.yml --field docker_tags=2.22.6-custom
```

---

## 驗證結果

```bash
# 1. n8n 版本
$ docker run --rm --entrypoint n8n ghcr.io/kuniakil/n8n:2.22.6-custom --version
2.22.6  ✅

# 2. Debian 版本
$ docker run --rm --entrypoint cat ghcr.io/kuniakil/n8n:2.22.6-custom /etc/debian_version
11.11  ✅

# 3. @xenova/transformers
$ docker run --rm --entrypoint node ghcr.io/kuniakil/n8n:2.22.6-custom \
    -e "console.log(require('@xenova/transformers').pipeline ? 'OK' : 'MISSING')"
OK  ✅

# 4. kubectl
$ docker run --rm --entrypoint kubectl ghcr.io/kuniakil/n8n:2.22.6-custom version --client
Client Version: v1.36.1
Kustomize Version: v5.8.1  ✅

# 5. Entrypoint
$ docker run --rm --entrypoint which ghcr.io/kuniakil/n8n:2.22.6-custom n8n
/usr/local/bin/n8n  ✅
```

---

## 環境變數說明

| ENV | 用途 |
|---|---|
| `NODE_FUNCTION_ALLOW_BUILTIN` | 允許 `crypto`、`child_process` 內建模組（n8n Code node 需要） |
| `NODE_FUNCTION_ALLOW_EXTERNAL=*` | 允許所有外部 npm 模組 |
| `N8N_BLOCK_EXTERNAL_EXECUTION=false` | 允許 Exec node 執行外部命令（kubectl 用） |
| `HF_HOME` | HuggingFace model cache 路徑（K8s hostPath 掛載） |
| `N8N_USER_FOLDER` | n8n 資料目錄（DB、credentials、workflows） |
| `NODE_PATH` | 讓 USER node 找得到 npm global 安裝的 `@xenova/transformers` |

---

## 部署注意事項

- **Volumes 需要 hostPath：**
  - `/home/node/.n8n` — DB、credentials、workflows
  - `/home/node/.n8n/.cache/huggingface` — embedding model cache（避免重啟重抓）
- **K8s API Server RBAC** 需要給 n8n pod 對應 ServiceAccount + ClusterRole
- **DB migration 風險：** 升級 n8n 時要 n8n 內部自動跑 migration，不要直接換 image 不先驗證 schema

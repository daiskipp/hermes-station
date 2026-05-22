# Agent OS — Architecture Design Document

最終更新: 2026-05-21
ステータス: 要件書 v3.5 + 各リポジトリ実機調査に基づく設計

---

## 1. 概要

Mac (M4 Max 36GB) 上の Docker 隔離環境で動く AI エージェント基盤。
全コンポーネントを Docker Compose で起動し、`just up` 一発で動作する。

**自作コードは監視ページ (`monitoring/`) のみ**。他は全て既製 OSS を Docker で組み合わせる。

---

## 2. コンポーネント一覧と実機調査結果

### 2.1 Hermes Agent

| 項目 | 内容 |
|---|---|
| リポジトリ | https://github.com/NousResearch/hermes-agent |
| 言語 | Python 3.13 (uv) |
| ベースイメージ | `debian:13.4` + Python 3.13 (uv) — **Docker Hub に公式イメージなし** |
| エントリポイント | tini → hermes |
| データディレクトリ | `/opt/data` (HERMES_HOME) |
| UID/GID | `HERMES_UID` / `HERMES_GID` (default: 10000) |

**ポート:**
- Dashboard: `HERMES_DASHBOARD_HOST` + `HERMES_DASHBOARD_PORT` (env で制御)
- API Server: `API_SERVER_HOST` + `API_SERVER_KEY` で有効化

**初回起動:**
- `/opt/data` が空の場合、config.yaml / .env / SOUL.md をテンプレートから自動生成
- `HERMES_AUTH_JSON_BOOTSTRAP` で OAuth 資格情報を非対話的にシード可能

**Memory Provider (Honcho):**
- `hermes memory setup` で設定、または config.yaml 直書き
- `HONCHO_API_KEY` + `~/.honcho/config.json` が必要

**MCP Server (GBRAIN):**
- config.yaml の MCP セクションで stdio or HTTP endpoint を指定

**要件書との差分:**
- ~~Docker Hub の公式イメージを pin~~ → **リポジトリを clone してローカルビルド**が必要
- `API_SERVER_ENABLED` フラグは明示的に無い → `API_SERVER_KEY` の存在で有効化
- Dashboard ポートは 9119 固定ではなく env で指定

### 2.2 Honcho

| 項目 | 内容 |
|---|---|
| リポジトリ | https://github.com/plastic-labs/honcho |
| 言語 | Python 3.10+ (uv) |
| Docker | Dockerfile + docker-compose.yml.example あり |
| API ポート | `:8000` (FastAPI) |

**環境変数:**
- `DB_CONNECTION_URI` — PostgreSQL 接続文字列 (`postgresql+psycopg://...`)
- `AUTH_USE_AUTH` / `AUTH_JWT_SECRET` — 認証 (任意)
- `LLM_GEMINI_API_KEY` / `LLM_ANTHROPIC_API_KEY` / `LLM_OPENAI_API_KEY` — reasoning 用 LLM

**主要 API エンドポイント:**
- `/peers/{peer_id}/chat` — ピアとの自然言語対話
- `/sessions/{session_id}/context` — トークン制限付きプロンプトバンドル
- 検索 API (workspace / session / peer レベル)

**Reasoning (LLM 依存):**
- background reasoning は LLM を使う
- config.toml or env で custom endpoint を設定可能
- **Ollama (OpenAI 互換) に向けられるか要検証 (M4 のリスク項目)**

**要件書との差分:**
- ポートは要件書で「honcho:\<port\>」未定 → 実際は `:8000`
- Redis はオプション (MVP では不要)

### 2.3 GBRAIN

| 項目 | 内容 |
|---|---|
| リポジトリ | https://github.com/garrytan/gbrain |
| 言語 | TypeScript |
| ランタイム | Bun ≥1.3.10 |
| Docker | **Dockerfile なし** — CLI ツールとして配布 |

**MCP モード:**
- **stdio (default):** `gbrain serve` — subprocess として起動
- **HTTP:** `gbrain serve --http --port 3131` — OAuth 2.1, admin dashboard (`/admin`), SSE, rate limiting

**データベース:**
- **PGLite (default):** `~/.gbrain/brain.db` — 組込み PostgreSQL (WASM)
- **PostgreSQL:** 外部 Postgres + pgvector も対応 (Supabase/self-host)

**設定:**
- `~/.gbrain/config.json` or env vars
- `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` — embedding/LLM 用

**スキル:** 52 個 (要件書の 29 個より増加)

**要件書との差分:**
- **Dockerfile なし** → 自前で Dockerfile を書く必要あり
- PGLite がデフォルト → Postgres 外部接続はオプション扱い。compose の Postgres を使うか、PGLite のままにするか**設計判断が必要**
- ポートは要件書で未定 → HTTP モードは `:3131`
- embedding に外部 API キーが必要 → **Ollama embedding (nomic-embed-text) に向けられるか要検証**

### 2.4 hermes-webui

| 項目 | 内容 |
|---|---|
| リポジトリ | https://github.com/nesquena/hermes-webui |
| 言語 | Python + vanilla JS |
| イメージ | `ghcr.io/nesquena/hermes-webui:<tag>` |
| ポート | `:8787` |

**接続モード:**
- gateway: 別コンテナの Hermes API (`hermes:8642`) に接続
- in-process: Hermes を同一プロセスで取り込み

### 2.5 PostgreSQL

| 項目 | 内容 |
|---|---|
| イメージ | `pgvector/pgvector:pg16` |
| ポート | `:5432` (Docker network 内のみ) |
| 初期化 | `config/postgres/init.sql` |

---

## 3. ネットワーク設計

```
Docker network: agentos (bridge)

┌─────────────────────────────────────────────────────┐
│                                                     │
│  hermes ──→ honcho:8000     (memory provider)       │
│         ──→ gbrain:3131     (HTTP MCP)              │
│         ──→ host.docker.internal:11434 (Ollama)     │
│                                                     │
│  honcho ──→ postgres:5432                           │
│  gbrain ──→ postgres:5432   (or PGLite, 要判断)     │
│                                                     │
│  hermes-webui ──→ hermes    (gateway or in-process) │
│  dashboard    ──→ gbrain:3131 / honcho:8000 /       │
│                   hermes (dashboard API)             │
│                                                     │
└─────────────────────────────────────────────────────┘

localhost 公開:
  - hermes-webui  → 127.0.0.1:8787
  - dashboard     → 127.0.0.1:8080
```

---

## 4. データフロー

### 4.1 チャット (ユーザ → Hermes → 応答)

```
User → hermes-webui (:8787)
         → Hermes API
            → Ollama (host:11434) で推論
            → [必要に応じて] GBRAIN MCP で知識検索
            → [自動] Honcho に会話を記録 / representation 更新
         ← 応答を SSE ストリーミング
```

### 4.2 実行委譲 (Hermes → Claude Code)

```
Hermes (orchestrator)
  → 判断: このタスクは frontier CLI に委譲
  → コンテナ内の claude コマンドを実行 (backend=local)
  → 結果を受け取り、ユーザに返す
```

### 4.3 知識の蓄積

```
会話中の重要情報
  → Hermes が判断
  → GBRAIN MCP の write skill でページ作成
  → Postgres (or PGLite) に永続化 + ベクトルインデックス
```

---

## 5. docker-compose 設計

### 5.1 サービス定義

```yaml
services:
  postgres:
    image: pgvector/pgvector:pg16
    volumes:
      - ~/agent-data/postgres:/var/lib/postgresql/data
      - ./config/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: agentos
    networks: [agentos]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  honcho:
    build: ./vendor/honcho
    depends_on:
      postgres: { condition: service_healthy }
    environment:
      DB_CONNECTION_URI: postgresql+psycopg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/agentos
    networks: [agentos]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 10s
      retries: 5

  gbrain:
    build: ./config/gbrain
    depends_on:
      postgres: { condition: service_healthy }
    environment:
      # Ollama embedding (要検証)
      OPENAI_API_BASE: http://host.docker.internal:11434/v1
    command: ["gbrain", "serve", "--http", "--port", "3131"]
    networks: [agentos]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3131/health"]
      interval: 10s
      retries: 5

  hermes:
    build: ./config/hermes
    depends_on:
      honcho: { condition: service_healthy }
      gbrain: { condition: service_healthy }
    volumes:
      - ~/agent-data/hermes:/opt/data
    environment:
      HERMES_UID: ${HERMES_UID:-10000}
      HERMES_GID: ${HERMES_GID:-10000}
      HERMES_DASHBOARD: "true"
      HERMES_DASHBOARD_HOST: "0.0.0.0"
      HERMES_DASHBOARD_PORT: "9119"
      API_SERVER_HOST: "0.0.0.0"
      API_SERVER_KEY: ${API_SERVER_KEY}
    networks: [agentos]

  hermes-webui:
    image: ghcr.io/nesquena/hermes-webui:${WEBUI_TAG}
    depends_on: [hermes]
    ports:
      - "127.0.0.1:8787:8787"
    environment:
      HERMES_WEBUI_PASSWORD: ${WEBUI_PASSWORD}
      # gateway mode: Hermes API endpoint
    networks: [agentos]

  dashboard:
    build: ./monitoring
    depends_on: [hermes, honcho, gbrain]
    ports:
      - "127.0.0.1:8080:8080"
    environment:
      API_SERVER_KEY: ${API_SERVER_KEY}
    networks: [agentos]

networks:
  agentos:
    driver: bridge
```

### 5.2 ビルドが必要なイメージ

| サービス | ビルド元 | 理由 |
|---|---|---|
| hermes | `./config/hermes/Dockerfile` | 公式 Docker Hub イメージなし + CLI executors 同梱 |
| honcho | `./vendor/honcho/` | リポジトリの Dockerfile を使用 |
| gbrain | `./config/gbrain/Dockerfile` | Dockerfile なし、自前で作成 |
| dashboard | `./monitoring/Dockerfile` | 自作の監視ページ |

### 5.3 そのまま使うイメージ

| サービス | イメージ |
|---|---|
| postgres | `pgvector/pgvector:pg16` |
| hermes-webui | `ghcr.io/nesquena/hermes-webui:<固定タグ>` |

---

## 6. データ配置

```
~/agent-data/                    # Mac local, Syncthing 除外
├── hermes/                      # Hermes /opt/data マウント
│   ├── config.yaml
│   ├── SOUL.md
│   ├── memories/
│   ├── skills/
│   ├── sessions/
│   ├── cron/
│   ├── logs/
│   └── state.db (SQLite FTS)
├── postgres/                    # PostgreSQL data
├── gbrain/                      # GBRAIN data (PGLite or config)
└── honcho/                      # Honcho cache
```

---

## 7. 設計判断 (要検証・未決定)

### 7.1 GBRAIN: PGLite vs 共有 Postgres

| 選択肢 | メリット | デメリット |
|---|---|---|
| **PGLite (GBRAIN 内蔵)** | 設定不要、GBRAIN デフォルト動作 | Postgres と分離、監視ページからの直接クエリが面倒 |
| **共有 Postgres** | 1 DB で統合、監視が容易 | GBRAIN の Postgres 外部接続設定が要検証 |

**推奨**: MVP は **PGLite** で始める。GBRAIN のデフォルト動作を尊重し、設定リスクを減らす。監視ページは GBRAIN の HTTP API (`/admin`, stats) 経由でデータ取得。

### 7.2 GBRAIN embedding: 外部 API vs Ollama

GBRAIN は embedding に API キー (`OPENAI_API_KEY` 等) を期待する。
Ollama の OpenAI 互換 API (`host.docker.internal:11434/v1`) で代替可能か **M3 で検証**。

**fallback**: 不可なら `OPENAI_API_KEY` を設定して embedding だけ外部 API。
(推論は Ollama、embedding だけ外部という分離は許容範囲)

### 7.3 Honcho reasoning: Ollama 向け設定

Honcho の background reasoning は LLM を使う。
config.toml or env で custom endpoint (Ollama) を指定できるか **M4 で検証**。

**fallback (段階的)**:
1. 軽量モデルを別途 Ollama にロード
2. reasoning を無効化、Tier3 を「保存のみ」で MVP を通す

### 7.4 hermes-webui: gateway vs in-process

**推奨**: gateway 接続 (Hermes API 経由) を第一候補。
compose で分離したまま `hermes:8642` / `:9119` に Bearer 認証で接続。

**fallback**: 機能不足なら in-process (Hermes コンテナに同居)。

### 7.5 Hermes イメージ: clone + build 戦略

Docker Hub に公式イメージがないため:

```
vendor/hermes-agent/            # git submodule or clone
config/hermes/Dockerfile        # FROM vendor build + CLI executors
```

**タグ固定**: `git clone` 時にリリースタグを checkout してビルド。

---

## 8. init.sql 設計

```sql
-- PostgreSQL initialization for Agent OS
CREATE EXTENSION IF NOT EXISTS vector;

-- Honcho schema (Alembic migration が自動作成するため、ここでは DB/extension のみ)
-- GBRAIN schema (PGLite 使用の場合は不要。共有 Postgres の場合は別途)

-- 監視用テーブル (dashboard snapshots)
CREATE TABLE IF NOT EXISTS dashboard_metrics (
    id SERIAL PRIMARY KEY,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    service TEXT NOT NULL,          -- 'gbrain', 'honcho', 'hermes'
    metric_name TEXT NOT NULL,      -- 'page_count', 'entity_count', 'session_count', etc.
    metric_value NUMERIC NOT NULL
);

CREATE INDEX idx_dashboard_metrics_time ON dashboard_metrics (recorded_at DESC);
CREATE INDEX idx_dashboard_metrics_service ON dashboard_metrics (service, metric_name);
```

---

## 9. justfile 設計

```just
# Agent OS task runner

set dotenv-load

# Start all services
up:
    docker compose up -d --build

# Health check all services
health:
    @echo "=== Postgres ===" && docker compose exec postgres pg_isready -U ${POSTGRES_USER}
    @echo "=== Honcho ===" && curl -sf http://localhost:8000/health || echo "FAIL"
    @echo "=== GBRAIN ===" && curl -sf http://localhost:3131/health || echo "FAIL"
    @echo "=== Hermes ===" && docker compose exec hermes hermes status || echo "FAIL"
    @echo "=== hermes-webui ===" && curl -sf http://localhost:8787 || echo "FAIL"
    @echo "=== Dashboard ===" && curl -sf http://localhost:8080 || echo "FAIL"

# Stop all services
down:
    docker compose down

# Full cleanup: remove all containers, volumes, and agent data
clean:
    docker compose down -v --rmi local
    rm -rf ~/agent-data/postgres ~/agent-data/hermes ~/agent-data/gbrain ~/agent-data/honcho
    @echo "Cleaned. ~/agent-data/ contents removed."

# View logs
logs *args:
    docker compose logs {{args}}

# Rebuild a specific service
rebuild service:
    docker compose up -d --build {{service}}
```

---

## 10. .env 設計

```bash
# === Postgres ===
POSTGRES_USER=agentos
POSTGRES_PASSWORD=          # generate with: openssl rand -hex 16

# === Hermes ===
HERMES_UID=10000
HERMES_GID=10000
API_SERVER_KEY=             # generate with: openssl rand -hex 32

# === hermes-webui ===
WEBUI_TAG=v0.51.74          # pin to stable release
WEBUI_PASSWORD=             # set your password

# === Honcho ===
# AUTH_USE_AUTH=false        # MVP: no auth between services
# LLM endpoint for reasoning (M4 で検証)

# === GBRAIN ===
# OPENAI_API_KEY=           # embedding 用 (Ollama で代替できるか M3 で検証)

# === Ollama (host) ===
# Not in compose — runs natively on Mac
# Endpoint: host.docker.internal:11434
```

---

## 11. ディレクトリ構造 (実装後)

```
agent_os/
├── docker-compose.yml
├── justfile
├── .env.example
├── .env                         # .gitignore 対象
├── .gitignore
├── .stignore                    # Syncthing 除外
├── CLAUDE.md
│
├── vendor/                      # 外部リポジトリ (git submodule or clone)
│   ├── hermes-agent/            # NousResearch/hermes-agent (tag pin)
│   └── honcho/                  # plastic-labs/honcho (tag pin)
│
├── config/
│   ├── postgres/
│   │   └── init.sql             # CREATE EXTENSION vector + dashboard_metrics
│   ├── hermes/
│   │   ├── Dockerfile           # vendor/hermes-agent ベース + CLI executors
│   │   └── config.yaml.template # Ollama / Honcho / GBRAIN MCP 設定
│   └── gbrain/
│       └── Dockerfile           # Bun + gbrain CLI install
│
├── monitoring/                  # 自作: 監視ページ (Bun+TS)
│   ├── server.ts
│   ├── public/
│   │   └── index.html           # Chart.js (CDN)
│   ├── tsconfig.json
│   └── Dockerfile
│
├── docs/
│   ├── requirements.md          # v3.5
│   ├── tech-stack.md
│   ├── design/
│   │   └── architecture.md      # このファイル
│   └── tasks/
│
└── scripts/
    ├── backup.sh
    └── health-check.sh
```

---

## 12. MVP フェーズと設計のマッピング

| Phase | 作るもの | 設計セクション |
|---|---|---|
| **M1** | docker-compose + Postgres + justfile + .env | §5, §8, §9, §10 |
| **M2** | Hermes Dockerfile + config.yaml + Ollama 接続 | §2.1, §5.2 |
| **M3** | GBRAIN Dockerfile + MCP 登録 + 検索確認 | §2.3, §7.1, §7.2 |
| **M4** | Honcho 起動 + provider 設定 + reasoning 検証 | §2.2, §7.3 |
| **M5** | hermes-webui 追加 + 監視ページ実装 | §2.4, §5.1 |
| **M6** | just up/health/clean 整備 + 動作確認 | §9 |

---

## 13. リスクまとめ (設計時点)

| # | リスク | 影響 | 対策 | 検証タイミング |
|---|---|---|---|---|
| 1 | Hermes の Docker Hub イメージなし | ローカルビルド必須、ビルド時間増 | vendor/ に clone + tag pin | M2 |
| 2 | GBRAIN の Dockerfile なし | 自前 Dockerfile 作成 | Bun base image + gbrain install | M3 |
| 3 | GBRAIN embedding の Ollama 互換性 | embedding だけ外部 API 必要の可能性 | Ollama 試行 → fallback: OPENAI_API_KEY | M3 |
| 4 | Honcho reasoning の Ollama 互換性 | reasoning 無効化の可能性 | Ollama 試行 → fallback: 保存のみモード | M4 |
| 5 | hermes-webui gateway 接続の安定性 | in-process に切替の可能性 | gateway 試行 → fallback: 同居 | M5 |

---

**Next**: この設計書のレビュー後、M1 (scaffold) から着手。

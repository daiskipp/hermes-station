# hermes-station

Docker 隔離環境で動く AI エージェント基盤。Mac / Linux 対応。

中核は [Hermes Agent](https://hermes-agent.nousresearch.com/docs/) (Nous Research)、記憶は [Honcho](https://honcho.dev/docs/v3/documentation/introduction/overview) (会話/ユーザモデル) + [GBRAIN](https://github.com/garrytan/gbrain) (知識グラフ)。UI は [hermes-webui](https://github.com/nesquena/hermes-webui)。

```
Host:    Ollama (native, GPU) + Docker + just (task runner)
Docker:  Hermes → Honcho (memory) + GBRAIN (MCP) + Postgres (pgvector)
UI:      hermes-webui (:8787) + 監視ダッシュボード (:8080)
```

---

## 前提条件

| ツール | 用途 | Mac | Linux |
|--------|------|-----|-------|
| **Ollama** | LLM 推論 (GPU) | `brew install ollama` | `curl -fsSL https://ollama.com/install.sh \| sh` |
| **Docker** | コンテナランタイム | OrbStack (`brew install orbstack`) or Docker Desktop | `sudo apt install docker.io docker-compose-v2` (Ubuntu) |
| **just** | タスクランナー | `brew install just` | `cargo install just` or [prebuilt](https://github.com/casey/just/releases) |
| **git** | ソース管理 | Xcode CLT に同梱 | `sudo apt install git` |

---

## セットアップ

### 1. リポジトリの取得

```bash
git clone <repo-url> hermes-station
cd hermes-station
```

### 2. Ollama モデルの準備

```bash
# メインモデル (推論用)
ollama pull qwen3.6:27b-coding-nvfp4

# Embedding モデル (GBRAIN/Honcho のベクトル検索用)
ollama pull nomic-embed-text

# Ollama が起動していることを確認
ollama list
```

モデルは `.env` の `OLLAMA_MODEL` で変更可能。Ollama は常駐サービスとして動かしておく。

### 3. 環境変数の設定

```bash
cp .env.example .env
```

`.env` を編集して以下を設定:

```bash
# --- 必須 ---
AGENT_DATA=${HOME}/agent-data          # データ保存先 (絶対パスで指定)
POSTGRES_PASSWORD=<任意の安全なパスワード>
API_SERVER_KEY=<任意の長いランダム文字列>

# --- 任意 (デフォルトあり) ---
# OLLAMA_MODEL=qwen3.6:27b-coding-nvfp4   # 使用モデル
# OLLAMA_BASE_URL=http://host.docker.internal:11434  # Ollama の URL (後述)
# POSTGRES_USER=agentos                     # DB ユーザ
# POSTGRES_DB=agentos                       # DB 名
# WEBUI_PORT=8787                           # hermes-webui ポート
# DASHBOARD_PORT=8080                       # 監視ダッシュボード ポート
# HERMES_DASHBOARD_PORT=9119                # Hermes dashboard API ポート
# WEBUI_PASSWORD=                           # hermes-webui パスワード (空=認証なし)
```

パスワード/キーの生成例:

```bash
openssl rand -hex 16   # POSTGRES_PASSWORD 用
openssl rand -hex 32   # API_SERVER_KEY 用
```

### 4. 起動

```bash
just up       # コアのみ (Hermes + webui + Postgres)
just all-up   # 全サービス (+ GBRAIN + Honcho + Dashboard)
```

初回は Docker イメージのビルドに数分かかる。`just all-up` で完了すると以下が表示される:

```
=========================================
  hermes-station is running (full)
=========================================
  Chat UI:   http://localhost:8787
  Hermes:    http://localhost:9119
  Monitor:   http://localhost:8080
  Model:     qwen3.6:27b-coding-nvfp4
=========================================
```

`just up` (コアのみ) の場合は Hermes 単体で動作し、GBRAIN/Honcho 連携は無効になる。

---

## Mac / Linux の違い

### Ollama への接続

Docker コンテナからホスト上の Ollama に接続するための設定。

| 環境 | `host.docker.internal` | 追加設定 |
|------|----------------------|----------|
| **Mac** (OrbStack / Docker Desktop) | 自動で解決される | 不要 (デフォルトのまま) |
| **Linux** (Docker Engine) | `extra_hosts` で解決 (compose に設定済み) | 不要 (デフォルトのまま) |

docker-compose.yml には `extra_hosts: ["host.docker.internal:host-gateway"]` を設定済みなので、**通常はどちらの OS でもそのまま動く**。

Ollama をリモートマシンや別ポートで動かしている場合は `.env` で上書き:

```bash
OLLAMA_BASE_URL=http://192.168.1.100:11434   # リモート Ollama の例
OLLAMA_HOST=192.168.1.100:11434               # 監視ダッシュボード用
```



## 使い方

### just コマンド一覧

**起動・停止:**

| コマンド | 説明 |
|----------|------|
| `just up` | コアサービス起動 (Postgres + Hermes + hermes-webui) |
| `just all-up` | 全サービス起動 (コア + GBRAIN + Honcho + Dashboard) |
| `just down` | 全サービス停止 |
| `just clean` | 全データ・コンテナ消去 (確認プロンプトあり) |

**運用:**

| コマンド | 説明 |
|----------|------|
| `just health` | 全サービスの health check (停止中は SKIP 表示) |
| `just status` | コンテナの状態確認 |
| `just logs hermes` | Hermes のログを表示 |
| `just logs -f` | 全ログをフォロー |
| `just psql` | Postgres CLI に接続 |

**ビルド・更新:**

| コマンド | 説明 |
|----------|------|
| `just rebuild <service>` | 特定サービスだけ再ビルド |
| `just update` | 全 vendor を最新に更新して再ビルド |
| `just update-service <name>` | 個別サービスの更新 (hermes/honcho/gbrain/webui) |
| `just versions` | サブモジュール・イメージのバージョン確認 |

`just up` はコアだけ起動するので軽い。GBRAIN/Honcho/Dashboard が要るときは `just all-up`。

### Web UI

| URL | 用途 |
|-----|------|
| `http://localhost:8787` | **hermes-webui** — チャット、profile 管理、session、cron、memory 編集 |
| `http://localhost:8080` | **監視ダッシュボード** — 全サービスヘルス、GBRAIN/Honcho メトリクス |
| `http://localhost:9119` | **Hermes dashboard** — 内部 API (通常は直接見ない) |

### チャットする

hermes-webui (`localhost:8787`) を開いてチャットするのが基本。
Hermes が Honcho (会話記憶) と GBRAIN (知識) の両方を自動的に参照・蓄積する。

---

## メモリとナレッジの追加

### GBRAIN (知識グラフ)

人物・会社・概念などの構造化された知識を管理する。

**CLI (コンテナ内):**

```bash
# ハイブリッド検索 (ベクトル + キーワード + グラフ)
docker compose exec gbrain gbrain search "投資先の企業"

# 自然言語で質問
docker compose exec gbrain gbrain query "bob は今四半期何に投資した？"

# グラフ多段トラバーサル
docker compose exec gbrain gbrain graph-query "acme の投資先" --depth 2

# git リポジトリからページを同期
docker compose exec gbrain gbrain sync

# ブレインの健康状態チェック・自動修復
docker compose exec gbrain gbrain doctor --remediate
```

**MCP 経由 (Hermes が使う):**

Hermes は MCP ツールとして `put_page` / `search` / `query` / `list_pages` 等を呼ぶ。会話中に重要な知識と判断すれば `put_page` で自発的に記録する。

**ページ形式:** Markdown + wikilink + typed-link:

```markdown
# 田中太郎
[[wiki/companies/acme]] の CTO。機械学習が専門。
Relationship: founded [[wiki/companies/acme]], advises [[wiki/companies/widget-co]]

## Facts
team_size=12
focus=machine_learning

## Timeline
- 2024-03-10: カンファレンスで初対面
- 2024-08-01: プロジェクト共同開始
```

書込み時にエンティティ抽出・自動リンク・バックリンク生成・ベクトル索引が自動で走る。矛盾検出や重複マージはバックグラウンドサイクルで処理される。

### Honcho (会話記憶)

会話を通じて自動的にユーザモデルが育つ。明示的な操作は基本不要。

- **Deriver**: メッセージからユーザの特性・嗜好を自動抽出
- **Summarizer**: 20 メッセージごとに短縮要約、60 メッセージで長期要約

明示的に結論を書き込みたい場合:

```bash
# 直接 conclusion を登録
curl -X POST http://localhost:8000/v3/workspaces/{ws}/peers/{pid}/conclusions \
  -H "Content-Type: application/json" \
  -d '{"content": "Written memos preferred over synchronous meetings"}'
```

### 記憶の流れ

```
ユーザが hermes-webui でチャット
  → Hermes が Honcho にメッセージ保存 (自動)
  → Deriver がユーザ特性を抽出 (自動、バックグラウンド)
  → Hermes が重要な知識を GBRAIN に put_page (判断による)
  → 次回の会話で両方を参照して応答
```

---

## アーキテクチャ

### サービス構成

| サービス | ポート | 役割 | ヘルスチェック |
|----------|--------|------|---------------|
| **postgres** | 5432 (内部) | DB (pgvector) | `pg_isready` |
| **hermes** | 9119 | エージェントランタイム + dashboard API | `hermes status` |
| **gbrain** | 3131 (内部) | 知識グラフ MCP サーバー | `GET /health` |
| **honcho** | 8000 (内部) | 会話記憶 API | HTTP check |
| **honcho-deriver** | — | バックグラウンドワーカー (推論抽出) | — |
| **hermes-webui** | 8787 | 操作 UI (OSS) | HTTP 200 |
| **dashboard** | 8080 | 監視ダッシュボード (自作) | — |

全サービスは `agentos` bridge ネットワーク上で動作。外部公開ポートは全て `127.0.0.1` bind。

### 記憶の三層構造

| 層 | 担当 | 保存場所 |
|----|------|----------|
| **Tier 1** | MEMORY.md / USER.md (Hermes 内蔵) | `$AGENT_DATA/hermes/` |
| **Tier 2** | SQLite FTS (セッション検索) | `$AGENT_DATA/hermes/` |
| **Tier 3** | Honcho (ユーザモデル・推論) | Postgres |

GBRAIN は memory provider ではなく MCP ツールとして接続 (Honcho と競合しない)。

### データ配置

| パス | 内容 |
|------|------|
| `$AGENT_DATA/hermes/` | Hermes data (config, memories, sessions) |
| `$AGENT_DATA/postgres/` | Postgres volume |
| `$AGENT_DATA/gbrain/` | GBRAIN brain repo (Markdown ページ) |

`$AGENT_DATA` は Syncthing 等の同期対象から**必ず外す** (DB ファイル破損防止)。

---

## 設定ファイル

| ファイル | 説明 |
|----------|------|
| `.env` | 環境変数 (パスワード、モデル、ポート、データパス) |
| `docker-compose.yml` | サービス定義 |
| `config/hermes/config.yaml` | Hermes 設定テンプレート (初回起動時にコピーされる) |
| `config/hermes/setup-mcp.sh` | GBRAIN MCP トークン注入スクリプト |
| `config/gbrain/Dockerfile` | GBRAIN コンテナビルド |
| `config/gbrain/entrypoint.sh` | GBRAIN 初期化 + OAuth トークン発行 |
| `config/honcho/entrypoint.sh` | Honcho マイグレーション + embedding 次元修正 |
| `config/postgres/init.sql` | DB 初期化 (pgvector extension + dashboard_metrics テーブル) |

### Hermes 設定の変更

初回起動後の設定は `$AGENT_DATA/hermes/config.yaml` を直接編集する (テンプレートは再適用されない):

```bash
# コンテナ内で編集
docker compose exec hermes vi /opt/data/config.yaml

# 設定反映
just rebuild hermes
```

主な設定項目:

```yaml
model:
  default: "qwen3.6:27b-coding-nvfp4"  # OLLAMA_MODEL env で上書き可
  provider: "custom"
  base_url: "http://host.docker.internal:11434/v1"  # OLLAMA_BASE_URL env で上書き可

memory:
  memory_enabled: true        # Tier1 メモリ
  user_profile_enabled: true  # USER.md プロファイル

agent:
  max_turns: 60               # 暴走防止
  reasoning_effort: "none"    # "none"=高速, "medium"=高品質
```

### モデルの切替

```bash
# .env を編集
OLLAMA_MODEL=qwen3-30b-a3b   # 例: MoE モデルに変更

# Ollama にモデルを取得
ollama pull qwen3-30b-a3b

# 再起動
just down && just up
```

---

## アップデート

```bash
# 全 vendor サブモジュールを最新に更新して再ビルド
just update

# 特定サービスだけ更新
just update-service hermes
just update-service honcho
just update-service gbrain
just update-service webui

# バージョン確認
just versions
```

---

## トラブルシューティング

### Ollama に接続できない

```bash
# Ollama が起動しているか確認
ollama list

# Docker からホストに到達できるか確認
docker compose exec hermes curl -s http://host.docker.internal:11434/api/tags
```

Mac (OrbStack / Docker Desktop) と Linux (Docker Engine + extra_hosts) の両方で `host.docker.internal` は解決される。それでも失敗する場合は `.env` で `OLLAMA_BASE_URL` をホストの実 IP に設定する。

### GBRAIN MCP トークンが取得できない

GBRAIN の OAuth 登録は `config/gbrain/entrypoint.sh` が自動で行う。失敗する場合:

```bash
# GBRAIN ログを確認
just logs gbrain

# トークンファイルの確認
docker compose exec gbrain cat /opt/data/mcp-token.txt
```

### Honcho の embedding 次元エラー

Honcho は OpenAI 用の 1536 次元をデフォルトで作成するが、Ollama (nomic-embed-text) は 768 次元。
`config/honcho/entrypoint.sh` が自動で修正するが、失敗した場合:

```bash
just psql
-- 手動で修正
ALTER TABLE documents DROP COLUMN IF EXISTS embedding;
ALTER TABLE documents ADD COLUMN embedding vector(768);
```

### 全部やり直す

```bash
just clean   # 確認プロンプトあり。$AGENT_DATA 内のデータも消去される
just up      # ゼロから再構築
```

---

## 痕跡消去

ホストから hermes-station の全痕跡を消す:

**Mac:**
```bash
just clean
brew uninstall ollama orbstack just
rm -rf ~/agent-data
```

**Linux:**
```bash
just clean
sudo apt remove ollama docker.io    # or your package manager
rm -rf ~/agent-data
```

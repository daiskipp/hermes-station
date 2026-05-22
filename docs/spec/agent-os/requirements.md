# Agent OS 要件定義書 (逆生成)

## 分析概要

**分析日時**: 2026-05-22
**対象コードベース**: /Users/dicekey/WORKSPACES/tools/atama/
**抽出要件数**: 28 機能要件、16 非機能要件
**信頼度**: 90% (実装 + 設計書 `docs/requirements.md` v3.5 で裏付け)

---

## システム概要

### 推定されたシステム目的

Docker 隔離環境で動作する AI エージェント基盤。ホスト OS に Ollama / Docker / just 以外の痕跡を残さず、Hermes Agent を中核としたオーケストレーション・記憶・知識グラフの統合プラットフォームを提供する。

### 対象ユーザー

- **個人開発者** (Daisuke): AI エージェントを日常の開発補助・情報整理に使う
- **将来**: 複数プロファイル (programmer / researcher / designer) による専門エージェント群

---

## 機能要件 (EARS 記法)

### 通常要件

#### REQ-001: 全サービス一括起動

システムは `just up` コマンドで Hermes / hermes-webui / Honcho / GBRAIN / Postgres / 監視ダッシュボード を一括起動しなければならない。

**実装根拠**:
- `justfile:6-19` — `up` レシピ: `git submodule update` → `docker compose up -d --build` → `health` → バナー表示
- `docker-compose.yml` — 7 サービス定義 + depends_on による起動順序制御

#### REQ-002: 全サービスヘルスチェック

システムは `just health` コマンドで全サービスの生死を個別に確認できなければならない。

**実装根拠**:
- `justfile:22-34` — Postgres (`pg_isready`), Hermes (`hermes status`), GBRAIN (`curl /health`), Honcho (Python urllib), hermes-webui (`curl`), Dashboard (`curl`)
- `monitoring/src/health.ts` — API 経由での並列ヘルスチェック (3s timeout)

#### REQ-003: 完全リセット

システムは `just clean` コマンドでコンテナ・ボリューム・ローカルイメージ・`$AGENT_DATA` 配下のデータを全消去し、`just up` で再構築可能でなければならない。

**実装根拠**:
- `justfile:40-45` — 確認プロンプト付き `docker compose down -v --rmi local --remove-orphans` + `rm -rf $AGENT_DATA/*`

#### REQ-004: Hermes Agent のコンテナ内実行

Hermes Agent は Docker コンテナ内で実行し、実行バックエンドは `local` (コンテナ内完結) でなければならない。

**実装根拠**:
- `config/hermes/config.yaml:18-25` — `terminal.backend: "local"`, リソース制限 (1 CPU, 5120 MB mem)
- `docker-compose.yml:20-47` — Hermes コンテナ定義

#### REQ-005: Ollama 経由の LLM 推論

システムはホスト上の Ollama (OpenAI 互換 API) を経由して LLM 推論を行わなければならない。

**実装根拠**:
- `config/hermes/config.yaml:8-13` — `model.provider: "custom"`, `base_url: "http://host.docker.internal:11434/v1"`
- `docker-compose.yml` — 全 Ollama 参照サービスに `OLLAMA_BASE_URL` 環境変数 + `extra_hosts`

#### REQ-006: GBRAIN 知識グラフ MCP 接続

Hermes は GBRAIN に HTTP MCP サーバーとして接続し、知識の読み書き・検索ができなければならない。

**実装根拠**:
- `config/gbrain/entrypoint.sh:22-23` — `gbrain serve --http --port 3131 --bind 0.0.0.0 --enable-dcr`
- `config/hermes/setup-mcp.sh:39-56` — MCP サーバー設定注入 (9 tools: get_page, put_page, list_pages, search, query, add_tag, get_tags, get_stats, get_health)

#### REQ-007: Honcho 記憶プロバイダー

Honcho はセルフホストで動作し、Hermes の Tier3 memory provider として会話記憶・ユーザモデルを提供しなければならない。

**実装根拠**:
- `docker-compose.yml:69-105` — Honcho API サービス + Deriver ワーカー
- `config/honcho/entrypoint.sh` — DB マイグレーション + FastAPI サーバー起動

#### REQ-008: Honcho Deriver バックグラウンド推論

Honcho Deriver はバックグラウンドワーカーとしてメッセージからユーザ特性を自動抽出しなければならない。

**実装根拠**:
- `docker-compose.yml:107-128` — `honcho-deriver` サービス (entrypoint: `python -m src.deriver`)

#### REQ-009: hermes-webui 操作 UI

hermes-webui (OSS) は `:8787` でチャット・プロファイル管理・セッション・cron・メモリ編集を提供しなければならない。

**実装根拠**:
- `docker-compose.yml:130-152` — `ghcr.io/nesquena/hermes-webui` イメージ、127.0.0.1 bind

#### REQ-010: 監視ダッシュボード

自作の監視ページ (`:8080`) は全サービスヘルス・GBRAIN/Honcho メトリクス・トークン使用量を 1 画面で表示しなければならない。

**実装根拠**:
- `monitoring/src/server.ts` — `/api/health`, `/api/metrics`, `/api/tokens` エンドポイント
- `monitoring/public/index.html` — Health Grid + Memory Growth + Token Usage パネル

#### REQ-011: メトリクスの定期スナップショット

監視サービスは 5 分ごとにヘルス状態・GBRAIN/Honcho メトリクスを `dashboard_metrics` テーブルに記録しなければならない。

**実装根拠**:
- `monitoring/src/snapshots.ts:5` — `SNAPSHOT_INTERVAL_MS = 5 * 60 * 1000`
- `config/postgres/init.sql:8-14` — `dashboard_metrics` テーブル定義

#### REQ-012: Postgres + pgvector データベース

PostgreSQL は pgvector 拡張を有効にし、Honcho / GBRAIN / 監視ダッシュボードの永続化ストレージを提供しなければならない。

**実装根拠**:
- `docker-compose.yml:1-17` — `pgvector/pgvector:pg16` イメージ
- `config/postgres/init.sql:4` — `CREATE EXTENSION IF NOT EXISTS vector`

### 条件付き要件

#### REQ-101: GBRAIN 初回初期化

GBRAIN コンテナが初回起動の場合 (`config.json` が存在しない場合)、PGLite で自動初期化しなければならない。

**実装根拠**:
- `config/gbrain/entrypoint.sh:10-13` — `if [ ! -f config.json ]; gbrain init --pglite --non-interactive`

#### REQ-102: GBRAIN OAuth トークン自動発行

GBRAIN 起動後、OAuth クライアント登録とトークン発行を自動実行し、Hermes 用の MCP トークンファイルに保存しなければならない。

**実装根拠**:
- `config/gbrain/entrypoint.sh:36-63` — POST /register → POST /token → write mcp-token.txt

#### REQ-103: Hermes 起動時の MCP トークン注入

Hermes コンテナ起動時に、GBRAIN の MCP トークンが存在する場合は config.yaml に自動注入しなければならない。

**実装根拠**:
- `config/hermes/setup-mcp.sh:40-56` — Python YAML 操作でトークン注入

#### REQ-104: Honcho embedding 次元自動修正

Honcho の Alembic マイグレーションが 1536 次元のベクトルカラムを作成した場合、`EMBEDDING_VECTOR_DIMENSIONS` (デフォルト 768) に自動修正しなければならない。

**実装根拠**:
- `config/honcho/entrypoint.sh:7-33` — pg_attribute チェック → ALTER TABLE で次元変更

#### REQ-105: Ollama URL 環境変数オーバーライド

`OLLAMA_BASE_URL` 環境変数が設定されている場合、全サービスの Ollama 接続先をそちらに切り替えなければならない。

**実装根拠**:
- `docker-compose.yml` — 全 Ollama URL が `${OLLAMA_BASE_URL:-http://host.docker.internal:11434}` 形式
- `config/hermes/setup-mcp.sh:33` — `os.environ.get('OLLAMA_BASE_URL', ...)`
- `monitoring/src/health.ts:82` — `process.env.OLLAMA_HOST`

### 状態要件

#### REQ-201: サービスヘルス状態のリアルタイム表示

ダッシュボードにサービスが「正常」状態にある場合、緑色のステータスドットとレイテンシを表示しなければならない。「異常」状態にある場合、赤色のステータスドットとエラー詳細を表示しなければならない。

**実装根拠**:
- `monitoring/public/style.css:115-144` — `.health-card.up` (緑), `.health-card.down` (赤), `.status-dot.unknown` (灰)
- `monitoring/public/app.js:27-48` — `updateHealth()` で DOM クラス切替

#### REQ-202: メモリ三層構造

Hermes は以下の三層メモリ構造を維持しなければならない:
- Tier 1: MEMORY.md / USER.md (ファイルベース)
- Tier 2: SQLite FTS (セッション検索)
- Tier 3: Honcho (外部メモリプロバイダー)

**実装根拠**:
- `config/hermes/config.yaml:30-36` — `memory_enabled: true`, `user_profile_enabled: true`
- `docs/requirements.md:84-85` — Tier 構造の設計

### オプション要件

#### REQ-301: hermes-webui パスワード認証

hermes-webui はパスワード認証を設定してもよい (`WEBUI_PASSWORD` 環境変数)。

**実装根拠**:
- `docker-compose.yml:145` — `HERMES_WEBUI_PASSWORD: ${WEBUI_PASSWORD:-}`

#### REQ-302: Chart.js によるグラフ表示

監視ダッシュボードは Chart.js によるメトリクス推移グラフを表示してもよい (MVP 後)。

**実装根拠**:
- `monitoring/public/index.html:8,104` — Chart.js CDN 読み込み + `<canvas id="memoryChart" style="display:none;">`

### 制約要件

#### REQ-401: エージェント最大ターン数

Hermes Agent は 1 タスクあたり最大 60 ターンに制限されなければならない。

**実装根拠**:
- `config/hermes/config.yaml:42` — `agent.max_turns: 60`

#### REQ-402: サブエージェント最大反復数

delegate_task によるサブエージェントは最大 50 反復に制限されなければならない。

**実装根拠**:
- `config/hermes/config.yaml:60` — `delegation.max_iterations: 50`

#### REQ-403: ホスト依存最小化

ホスト OS にインストールするのは Ollama / Docker / just / git のみとしなければならない。

**実装根拠**:
- `README.md:15-24` — 前提条件テーブル (4 ツールのみ)
- `docs/requirements.md:264-271` — ホスト最小依存の設計原則

#### REQ-404: データディレクトリ隔離

永続データは `$AGENT_DATA` ディレクトリに集約し、リポジトリディレクトリや Syncthing 同期範囲と分離しなければならない。

**実装根拠**:
- `docker-compose.yml` — 全ボリュームが `${AGENT_DATA}/...` を参照
- `.stignore` — Syncthing 除外設定

#### REQ-405: MCP ツール制限

GBRAIN MCP は 66 ツールのうち 9 ツールのみ (読み書き・検索・ヘルス) を Hermes に公開しなければならない。

**実装根拠**:
- `config/hermes/setup-mcp.sh:47-55` — `tools.include` ホワイトリスト

#### REQ-406: localhost バインド

外部公開ポート (hermes-webui, dashboard, Hermes dashboard) は `127.0.0.1` にバインドしなければならない。

**実装根拠**:
- `docker-compose.yml:45,141,171` — `"127.0.0.1:${PORT}:..."` 形式

---

## 非機能要件

### パフォーマンス

#### NFR-001: GBRAIN ハイブリッド検索

GBRAIN のハイブリッド検索 (全文 + ベクトル) は数千ページ規模で 500ms 以内に応答しなければならない。

**推定根拠**: `docs/requirements.md:313`

#### NFR-002: Honcho プリフェッチ

Honcho のターンごとのプリフェッチは 1 秒以内に完了しなければならない。

**推定根拠**: `docs/requirements.md:314`

#### NFR-003: ダッシュボードポーリング間隔

監視ダッシュボードは 10 秒間隔でヘルス・メトリクスを更新しなければならない。

**実装根拠**: `monitoring/public/app.js:3` — `POLL_INTERVAL = 10000`

### セキュリティ

#### NFR-101: API 認証キー

Hermes API は `API_SERVER_KEY` ヘッダーによる認証を必須としなければならない。

**実装根拠**:
- `docker-compose.yml:43` — `API_SERVER_KEY: ${API_SERVER_KEY}`
- `monitoring/src/metrics.ts:161-163` — ヘッダー付与

#### NFR-102: GBRAIN OAuth 認証

GBRAIN MCP へのアクセスは OAuth 2.0 Bearer トークンで認証しなければならない。

**実装根拠**:
- `config/gbrain/entrypoint.sh:36-63` — OAuth フロー
- `config/hermes/setup-mcp.sh:43` — `Authorization: Bearer <token>`

#### NFR-103: シークレット管理

パスワード・API キーは `.env` ファイルで管理し、リポジトリにコミットしてはならない。

**実装根拠**:
- `.gitignore:2` — `.env` 除外
- `.env.example` — テンプレートのみコミット

### 信頼性

#### NFR-201: ヘルスチェックリトライ

各サービスのヘルスチェックはタイムアウト・リトライ設定を持ち、一時的な障害を吸収しなければならない。

**実装根拠**:
- `docker-compose.yml` — `retries: 5-10`, `interval: 10-15s`, `timeout: 5s`
- GBRAIN: `start_period: 30s` (初期化猶予)

#### NFR-202: メトリクス収集の部分障害許容

メトリクス収集で一部サービスが応答しなくても、他サービスの収集とスナップショット書込を継続しなければならない。

**実装根拠**:
- `monitoring/src/snapshots.ts:17-93` — 各セクションが独立した try/catch
- `monitoring/src/metrics.ts` — `{ available: false, error: "..." }` パターン

#### NFR-203: べき等スクリプト

初期化スクリプト・マイグレーションは繰り返し実行しても安全でなければならない。

**実装根拠**:
- `config/postgres/init.sql` — `IF NOT EXISTS`
- `config/gbrain/entrypoint.sh:10` — `config.json` 存在チェック
- `config/hermes/setup-mcp.sh` — YAML マージ更新

### 再現性

#### NFR-301: Docker イメージの固定タグ

Docker イメージは固定タグで pin し、`latest` は使用しないことが望ましい。

**実装根拠**:
- `docker-compose.yml:3` — `pgvector/pgvector:pg16`
- `config/gbrain/Dockerfile:1` — `oven/bun:1.2-debian`
- `monitoring/Dockerfile:1` — `oven/bun:1.2.14-alpine`
- 例外: `hermes-webui` は `${WEBUI_TAG:-latest}` (要改善)

#### NFR-302: 依存関係のロックファイル

Bun パッケージは `--frozen-lockfile` でインストールし、依存バージョンを固定しなければならない。

**実装根拠**:
- `config/gbrain/Dockerfile:11` — `bun install --frozen-lockfile`
- `monitoring/Dockerfile:6` — `bun install --frozen-lockfile 2>/dev/null || bun install`

### 運用性

#### NFR-401: ワンコマンド運用

起動 (`just up`)、停止 (`just down`)、リセット (`just clean`) が単一コマンドで実行できなければならない。

**実装根拠**: `justfile` — 各レシピ定義

#### NFR-402: サブモジュール管理

vendor ディレクトリは git submodule で管理し、バージョン追跡・一括更新ができなければならない。

**実装根拠**:
- `.gitmodules` — hermes-agent, honcho, gbrain の 3 サブモジュール
- `justfile:60-66,69-77` — `versions`, `update`, `update-service`

### クロスプラットフォーム

#### NFR-501: Mac / Linux 両対応

docker-compose.yml と全設定ファイルは Mac (OrbStack / Docker Desktop) と Linux (Docker Engine) の両方で動作しなければならない。

**実装根拠**:
- `docker-compose.yml` — `extra_hosts: ["host.docker.internal:host-gateway"]` (Linux 対応)
- `OLLAMA_BASE_URL` / `OLLAMA_HOST` 環境変数による接続先オーバーライド

---

## Edge ケース

### エラー処理

#### EDGE-001: GBRAIN MCP トークン取得失敗

OAuth 登録/トークン取得が失敗しても、GBRAIN サーバー自体は稼働を継続する。Hermes は MCP なしで起動する。

**実装根拠**: `config/gbrain/entrypoint.sh:52-55` — WARNING ログ出力、サーバーは継続

#### EDGE-002: Ollama 未起動

Ollama がホスト上で起動していない場合、Hermes の推論と Honcho の Deriver は失敗するが、GBRAIN (PGLite ベース) と監視ダッシュボードは稼働を継続する。

**実装根拠**: `monitoring/src/health.ts:81-89` — Ollama チェックは独立、"down" で報告

#### EDGE-003: Postgres 起動遅延

Postgres の初期化が遅い場合、依存サービス (Honcho, Dashboard) は health check の通過を待つ。

**実装根拠**: `docker-compose.yml` — `depends_on: postgres: { condition: service_healthy }`

### 境界値

#### EDGE-101: メモリ文字数制限

MEMORY.md は 2200 文字、USER.md は 1375 文字に制限される。超過分は Hermes が自動圧縮する。

**実装根拠**: `config/hermes/config.yaml:33-34`

#### EDGE-102: コンテキスト圧縮

コンテキストが上限の 50% に達すると 20% に圧縮される。直近 20 ターンと先頭 3 ターンは保護される。

**実装根拠**: `config/hermes/config.yaml:49-54`

---

## 推定されていない要件

### 確認が必要な事項

1. **Honcho reasoning の Ollama 対応**: reasoning endpoint が Ollama に正しく接続できるか未検証 (fallback: reasoning 無効化で Tier3「保存のみ」)
2. **hermes-webui の Gateway 接続**: Hermes API 経由の接続が安定しているか未検証
3. **複数プロファイル運用**: 1 コンテナ内での複数プロファイル管理は未実装
4. **バックアップ自動化**: nightly pg_dump / rsync は設計のみ、未実装
5. **Langfuse トレース連携**: optional として設計に含まれるが未実装

### 推奨される次ステップ

1. `just up` での全サービス起動 E2E テスト
2. Honcho Deriver → Ollama の推論パス検証
3. GBRAIN ページ書込→Hermes 検索の統合テスト
4. hermes-webui でのチャット→記憶蓄積の E2E テスト
5. `just clean` → `just up` のリセットサイクル検証

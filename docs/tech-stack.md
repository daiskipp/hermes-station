# プロジェクト技術スタック定義

## 生成情報
- **生成日**: 2026-05-21
- **生成ツール**: init-tech-stack
- **プロジェクトタイプ**: AI エージェント基盤 (Agent OS)
- **チーム規模**: 個人開発
- **開発期間**: プロトタイプ/MVP (1-2ヶ月)

## プロジェクト要件サマリー
- **パフォーマンス**: 未定/不明
- **セキュリティ**: 基本レベル (localhost 専用)
- **技術スキル**: JavaScript/TypeScript, Python, Docker
- **デプロイ先**: ローカル (Docker on Mac / OrbStack)
- **予算**: コスト最小化 (SaaS 不使用、全てローカル)

## 設計方針

このプロジェクトは**既製 OSS を Docker で組み合わせる**構成。自作コードは最小限。

| 区分 | コンポーネント | 自作/既製 |
|---|---|---|
| エージェント実行 | Hermes Agent | 既製 (Docker image) |
| 記憶 (誰) | Honcho | 既製 (self-host) |
| 知識 (何) | GBRAIN | 既製 (MCP server) |
| 操作 UI | hermes-webui | 既製 (OSS) |
| 監視ページ | dashboard | **自作** (唯一の自作コード) |
| DB | PostgreSQL + pgvector | 既製 |
| 推論 | Ollama | 既製 (Mac native) |

## コンポーネント別技術スタック

### Hermes Agent (既製)
- **言語**: Python 3.11
- **パッケージマネージャー**: uv
- **イメージ**: `nousresearch/hermes-agent:<固定タグ>`
- **派生 Dockerfile**: CLI executors (Claude Code 等) を同梱

### Honcho (既製, self-host)
- **言語**: Python 3.10+
- **パッケージマネージャー**: uv
- **主要依存**: FastAPI, SQLAlchemy, Alembic, PostgreSQL + pgvector
- **イメージ**: リリースタグを pin

### GBRAIN (既製)
- **言語**: TypeScript
- **ランタイム**: Bun
- **主要依存**: PostgreSQL + pgvector, HNSW vector search
- **接続**: HTTP MCP (第一候補) or stdio (fallback)

### hermes-webui (既製, OSS)
- **言語**: Python + vanilla JS
- **イメージ**: `ghcr.io/nesquena/hermes-webui:<固定タグ>`
- **ポート**: `:8787` (127.0.0.1 bind)

### 監視ページ (自作 — 唯一の自作コード)
- **言語**: TypeScript
- **ランタイム**: Bun
- **UI**: vanilla HTML + Chart.js (CDN)
- **ポート**: `:8080` (127.0.0.1 bind)
- **責務**: GBRAIN/Honcho 成長可視化、全体ヘルス、トークン/コスト表示

### 選択理由
- GBRAIN と同じ Bun + TS ランタイム (gbrain client を再利用可能)
- フレームワーク不要 (薄い監視ページのみ、React/Vue は過剰)
- Chart.js を CDN から読み込み、ビルドステップなし

## データベース
- **メインDB**: PostgreSQL (`pgvector/pgvector:pg16`)
- **用途**: Honcho schema + GBRAIN schema (共存)
- **初期化**: `config/postgres/init.sql` で `CREATE EXTENSION vector;`
- **キャッシュ**: なし (MVP 段階)
- **ファイルストレージ**: `~/agent-data/` (Mac local, Syncthing 除外)

## 推論エンジン
- **Ollama** (Mac native, M4 GPU)
- **第一候補モデル**: Qwen3.5 27B (既に稼働中)
- **Embedding**: nomic-embed-text
- **接続**: `host.docker.internal:11434/v1` (OpenAI 互換)

## 開発環境
- **コンテナ**: Docker 27+ / Docker Compose v2 (OrbStack)
- **ネットワーク**: bridge 1 本 (`agentos`)、サービス間は compose DNS 名で解決
- **バージョン管理**: 全イメージ固定タグ pin (`latest` 禁止)

### 開発ツール (監視ページ用)
- **ランタイム**: Bun (最新安定版)
- **リンター・フォーマッター**: Biome 1.9+ (TS オールインワン)
- **型チェック**: tsc (TypeScript strict)
- **テスト**: bun:test (Bun 組み込み)

### CI/CD
- **CI/CD**: GitHub Actions
- **コード品質**: Biome + tsc
- **デプロイ**: `just up` (ローカル Docker)

## インフラ
- **全サービス**: Docker Compose (ローカル)
- **推論**: Ollama (Mac native, compose 外)
- **データ永続化**: `~/agent-data/` にマウント
- **バックアップ**: nightly pg_dump + rsync → filesrv (MVP 後)

## セキュリティ
- **HTTPS**: 不要 (localhost 専用)
- **認証**: hermes-webui パスワード (`HERMES_WEBUI_PASSWORD`) + Hermes API キー (`API_SERVER_KEY`)
- **環境変数**: `.env` ファイルで管理 (`.gitignore` 登録必須)
- **CLI 認証**: Daisuke 本人が設定 (OAuth/API キー、Claude は代行しない)
- **ネットワーク**: hermes-webui と dashboard のみ 127.0.0.1 公開。他は Docker network 内に閉じる

## 品質基準
- **テストカバレッジ**: 80%以上 (監視ページ)
- **コード品質**: Biome strict
- **型安全性**: TypeScript strict
- **パフォーマンス**: ローカル環境で許容範囲内

## ディレクトリ構造

```
./ (プロジェクトルート = agent_os/)
├── docker-compose.yml        # 全サービス定義
├── justfile                  # just up / health / clean
├── .env.example              # 環境変数テンプレート
├── .gitignore
├── .stignore                 # Syncthing 除外
├── CLAUDE.md
│
├── config/
│   ├── postgres/init.sql     # honcho + gbrain schema, CREATE EXTENSION vector
│   ├── hermes/
│   │   ├── config.yaml       # model / MCP / memory provider 設定
│   │   └── Dockerfile        # hermes + CLI executors 同梱
│   └── honcho/config.toml
│
├── monitoring/               # 監視ページ (自作, Bun+TS, :8080)
│   ├── server.ts             # GBRAIN/Honcho 横断監視
│   ├── public/               # HTML + Chart.js
│   ├── tsconfig.json
│   └── Dockerfile
│
├── docs/
│   ├── requirements.md       # 要件定義書 (v3.5)
│   ├── tech-stack.md         # このファイル
│   ├── design/               # 設計書
│   └── tasks/                # タスク管理
│
└── scripts/
    ├── backup.sh
    └── health-check.sh
```

**注**: `frontend/` や `backend/` ディレクトリは不要。操作 UI は hermes-webui (OSS image)、自作は `monitoring/` のみ。

## セットアップ手順

### 1. ホスト準備 (Mac に入れるもの: これだけ)
```bash
# Ollama (M4 GPU 推論)
brew install ollama
ollama pull qwen3.5:27b
ollama pull nomic-embed-text

# OrbStack (Docker ランタイム)
brew install orbstack

# just (タスクランナー)
brew install just
```

痕跡消去: `brew uninstall ollama orbstack just && rm -rf ~/agent-data` で完了。

### 2. サービス起動
```bash
just up        # 全サービス起動 (Hermes + hermes-webui + Honcho + GBRAIN + Postgres + monitoring)
just health    # 全サービスの health check
just clean     # 全データ・コンテナ消去 (~/agent-data/ 以外の Mac に痕跡を残さない)
```

### 3. アクセス
- **操作 UI**: http://localhost:8787 (hermes-webui)
- **監視ページ**: http://localhost:8080 (自作 dashboard)

## カスタマイズ方法

このファイルはプロジェクトの進行に応じて更新してください：

1. **モデル変更**: Ollama のモデルを切替 (`hermes config set` / `ollama pull`)
2. **profile 追加**: MVP 後に複数 profile / チーム編成
3. **外部チャネル**: Telegram bot 等の追加
4. **バックアップ**: nightly backup の自動化

## 更新履歴
- 2026-05-21: 初回生成 (init-tech-stack により自動生成)
- 2026-05-21: 要件書 (v3.5) に基づき実態に合わせて全面改訂。自前 FastAPI/React を削除、既製品 Docker 構成に修正

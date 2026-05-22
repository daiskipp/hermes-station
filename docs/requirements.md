# Agent OS - Requirements (v3.5)

最終更新: 2026-05-21
ステータス: MVP 設計確定 (v3.5) / レビュー2巡目反映 (Must Have/認証/fallback 補強) / docs/ へ移動

---

## 目的

Mac ホスト (M4 Max 36GB) に痕跡を残さない隔離環境で動く **AI エージェント群** と、その**記憶を永続化する基盤**を構築する。

中核は `Hermes Agent` (Nous Research)。記憶は `Honcho` (会話/ユーザモデル) と `GBRAIN` (知識グラフ) の併用。

> v3 の更新点: Hermes Agent の実機能を確認した結果、
> - 「エージェント群」= Hermes **profiles** (完全分離した複数 agent) で実現
> - Honcho は Hermes 標準の **memory provider** (8個中の1つ) → 自前統合コード不要
> - GBRAIN は **MCP サーバ**として接続
> - LangGraph / Letta / Qdrant / 自前 FastAPI は全て不要

---

## 設計原則

1. **Host 隔離**: Mac には Ollama / OrbStack 以外を入れない。Hermes 含め全て Docker 内。
2. **完全リセット可能**: `make clean` で全データ・コンテナを消去できる。
3. **Syncthing 非汚染**: 永続データは Syncthing 同期範囲外 (`~/agent-data/`) に置く。
4. **Local-first**: 推論は Mac local の Ollama。外部 SaaS 依存を最小化。
5. **Observable**: 全 agent 動作はログ / トレースで追える。
6. **Reproducible**: docker-compose で 1 コマンド起動。

---

## 最小ベース (MVP) のスコープ

「まず最小で動かして、ダッシュボードで全体を見ながら育てる」方針。

MVP に含むもの (フルコア):
- **Hermes Agent** (Docker, **1 profile** = 汎用 orchestrator)。実行backend=local
- **GBRAIN** (MCP server) — knowledge graph
- **Honcho** (self-host) — Tier3 memory provider
- **Postgres + pgvector** — honcho/gbrain 永続化
- **操作 UI = hermes-webui** (OSS 採用) + **監視ページ** (自作, GBRAIN/Honcho 横断) — 全体視認
- **実行委譲先 = Claude Code** (1 executor で開始。Codex/Gemini CLI は MVP 後)
- Ollama は Mac native (compose 外)

MVP では割愛 (後で追加):
- 複数 profile / チーム編成 (まず 1 profile で土台確認)
- Telegram 等の外部チャネル
- cron digest
- 自動 backup

profile の具体用途は MVP 稼働後に決める。MVP は「汎用 1 体 + 記憶 + 可視化」が動くことがゴール。

---

## アーキテクチャ

```
┌──────────────────────────────────────────────┐
│  Mac host (最小依存)                          │
│  ┌────────────────────────────────────────┐  │
│  │  Ollama (native, M4 GPU 利用)          │  │
│  │  - モデルは実装時ベンチ(Qwen3系候補)   │  │
│  │  - nomic-embed-text (embedding)        │  │
│  └────────────────────────────────────────┘  │
│  :11434 (OpenAI 互換 /v1)                     │
└──────────────────────────────────────────────┘
              ↑ host.docker.internal:11434/v1
┌──────────────────────────────────────────────┐
│  Docker (OrbStack)                            │
│                                               │
│  ┌────────────────────────────────────────┐  │
│  │  Hermes Agent (Docker, /opt/data)      │  │
│  │  ┌──────────┬──────────┬────────────┐  │  │
│  │  │ profile  │ profile  │ profile     │  │  │
│  │  │ programmer│ researcher│ designer  │  │  │
│  │  │ SOUL.md  │ SOUL.md  │ SOUL.md     │  │  │
│  │  │ MEMORY/  │ MEMORY/  │ MEMORY/     │  │  │
│  │  │ skills/  │ skills/  │ skills/     │  │  │
│  │  └──────────┴──────────┴────────────┘  │  │
│  │  - 実行 backend = local (=コンテナ内)  │  │
│  │  - Tier1: MEMORY.md / USER.md          │  │
│  │  - Tier2: SQLite FTS (session search)  │  │
│  │  - Tier3: Honcho provider (下記)       │  │
│  │  - cron daemon (60s tick)              │  │
│  └────────────────────────────────────────┘  │
│     │ memory provider          │ MCP          │
│     ↓                          ↓              │
│  ┌──────────────┐   ┌────────────────────┐   │
│  │  Honcho      │   │  GBRAIN (Bun+TS)   │   │
│  │ (self-host)  │   │  - 29 skills       │   │
│  │ - peer model │   │  - knowledge graph │   │
│  │ - reasoning  │   │  - hybrid search   │   │
│  │ - represent. │   │  - MCP server      │   │
│  └──────────────┘   └────────────────────┘   │
│     ↓                          ↓              │
│  ┌────────────────────────────────────────┐  │
│  │  Postgres (pgvector/pgvector:pg16)     │  │
│  │  - honcho schema / gbrain schema       │  │
│  └────────────────────────────────────────┘  │
│                                               │
│  ┌────────────────────────────────────────┐  │
│  │  (optional) Langfuse — tracing         │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘

Volumes: ~/agent-data/ (Mac local, Syncthing 除外)
```

---

## 「エージェント群」= Hermes Profiles

各 profile は完全に分離した Hermes インスタンス (config / memory / skills / sessions / SOUL.md を共有しない)。

初期に作る 3 体 (例 / モデルは実装時ベンチで選定):

| Profile | 役割 | SOUL.md の方向性 | 推論モデル |
|---|---|---|---|
| **programmer** | 日々のコーディング | terse な staff engineer。コードを読んでから書く | coder 系 or Claude Code 委譲 |
| **researcher** | 情報収集・digest | 毎朝 AI/ML の digest を作る。出典必須 | 汎用 (ベンチで選定) |
| **designer** | 図解生成 | 概念を手描き風イラストで説明 | 汎用 + 画像生成 skill |

```
hermes profile create programmer --clone
hermes profile create researcher --clone
hermes profile create designer --clone
```

各 profile に個別の Telegram bot を割り当て可能 (将来)。programmer は Claude Code に実行委譲できる (Claude Max 利用)。

---

## コンポーネント役割分担

| 層 | 担当 | 接続方法 | 主な責務 |
|---|---|---|---|
| **Runtime** | Hermes Agent | Docker image | agent 実行 / ツール / 自己改良 / cron / profiles |
| **Cognition (誰)** | Honcho | **Tier3 memory provider** (config のみ) | ユーザの好み・性格・意図の継続学習 |
| **Knowledge (何)** | GBRAIN | **MCP server** (config のみ) | 人/会社/概念の knowledge graph + hybrid search |
| **Storage** | Postgres (`pgvector/pgvector:pg16`) | docker net (host: `postgres`) | honcho/gbrain 永続化。init.sql で `CREATE EXTENSION vector;` |
| **Inference** | Ollama (Mac native) | host.docker.internal:11434/v1 | LLM 推論。M4 GPU を使う唯一の理由でホスト常駐 |
| **Observability** | Langfuse (任意) | docker network | trace / token flow 可視化 |
| **操作 UI** | hermes-webui (`ghcr.io/nesquena/hermes-webui`) | `:8787`, Hermes を in-process/gateway | chat/profile/session/jobs/memory/skills。OSS 採用 (自作しない) |
| **監視 UI** | 自作 (Bun+TS) | `:8080`, 各サービス API | GBRAIN/Honcho 成長・全体ヘルス・トークン (横断のみ) |

重要: external memory provider は**同時に1つだけ** active にできる。Honcho をそのスロットに使う。
GBRAIN は memory provider ではなく MCP ツールなので競合しない。

---

## モデル選定 (実装時にベンチして決定 / 未確定)

方針: Hermes Agent は **model-agnostic** (Ollama / OpenAI 互換ならどれでも可)。
特定モデルに固定せず、実装フェーズで Mac 上で実際にベンチして選ぶ。
`config.yaml` の base_url を `host.docker.internal:11434/v1` に向けるだけなので、
モデル切替は 1 コマンド (`hermes config set` or `ollama pull`)。

ベンチ候補:

| 用途 | 候補 | サイズ (q4) | メモ |
|---|---|---|---|
| 汎用 / agentic | **Qwen3.5 27B** (既に Mac で稼働中) | ~16 GB | 追加 pull 不要。第一候補 |
| 汎用 / 高速 | Qwen3-30B-A3B (MoE, 実効3B) | ~18 GB | agentic 用途で高評価。応答が速い |
| コーディング | qwen2.5-coder:32b 等の Qwen coder 系 | ~20 GB | コーディング特化 |
| Embedding | nomic-embed-text (or qwen3-embedding) | ~270 MB | 768 次元 |
| (参考) 旧 | hermes3:8b / deephermes3:8b | ~5 GB | 古い (2024-08)。採用優先度低 |

制約:
- `hermes3:70b` 等の 70B 級は q4 で ~40GB+ のため **36GB には載らない**。
- 同時常駐は VRAM を食うので、運用上は「使う profile のモデルだけ Ollama にロード」が現実的。
- profile ごとに model を変えられる (programmer=coder, researcher=汎用 など)。

選定基準 (ベンチ時):
1. tool calling / function calling の安定性 (Hermes が依存)
2. 応答レイテンシ (複数 profile を回せるか)
3. ルーティング/要約の質 (実行は CLI 委譲なので**ローカルのコーディング力は重視しない**)

注: 実行を frontier CLI (下記「実行委譲」) に委ねるため、ローカルモデルは
オーケストレータ/記憶/ルーターに徹する。よって**軽量・高速モデル (例: Qwen3-30B-A3B) が有利**。
コーディング品質は executor (Claude Code 等) が担保する。

Ollama 設定 (Hermes config.yaml):
```yaml
model:
  # モデルは実装時ベンチで選定 (下記は例)。第一候補は既存 Qwen3.5 27B
  name: qwen3.5:27b
  provider: custom
  base_url: http://host.docker.internal:11434/v1
  context_length: 32768
```

モデル切替は 1 コマンド (`hermes config set` / `ollama pull`)。最終決定は M2 のベンチ後。

---

## デプロイモデル: なぜ Docker か

Hermes はネイティブ install (`~/.hermes/`) も可能だが、**Mac host 隔離**のため Docker で動かす:

- Hermes を Docker image (`nousresearch/hermes-agent:<固定タグ>`) で起動。**`latest` は使わない** (Reproducible 原則)。実装時に Docker Hub の最新安定版を確認して pin
- データは `~/agent-data/hermes/` を `/opt/data` にマウント
- **実行 backend = "local"** にすると、agent が実行するコマンドは**コンテナ内**で完結 → Mac のファイルシステムやプロセスに触れない
- これが「ホストに影響しない環境で動くエージェント群」の核心

トレードオフ: ネイティブ install 前提のチュートリアル (profiles / telegram) を Docker 向けに読み替える必要あり。profiles は 1 コンテナ内で複数管理 or コンテナ分割のどちらか (Phase 2 で決定)。

---

## バージョン固定 (Reproducible)

`latest` タグは使わず、全イメージを固定タグで pin (実装時に確認):

| サービス | イメージ | タグ方針 |
|---|---|---|
| Hermes (base) | `nousresearch/hermes-agent` | Docker Hub の最新安定版を pin |
| Hermes 派生 (CLI 同梱) | 自前 build (base + claude/codex/gemini CLI) | base タグに追従 |
| Postgres | `pgvector/pgvector` | `pg16` |
| Honcho | (self-host イメージ) | リリースタグを pin |
| GBRAIN | 自前 build (Bun) | コミット/タグ固定 |
| hermes-webui | `ghcr.io/nesquena/hermes-webui` | リリースタグを pin (例 v0.51.74) |
| 監視ページ | 自前 build (Bun) | — |

---

## ネットワーク設計

compose 内に bridge network 1 本 (`agentos`)。サービス間は compose の DNS 名で解決。

サービス名 (= ホスト名) と用途:
- `postgres:5432` — DB
- `honcho:<port>` — memory provider API
- `gbrain:<port>` — HTTP MCP
- `hermes:8642` — コア API (OpenAI互換/Runs/Jobs), `hermes:9119` — dashboard API
- `hermes-webui:8787` — 操作 UI (OSS)。**127.0.0.1 bind** (localhost 専用)
- `dashboard:8080` — 監視ページ (自作)

接続関係:
- Hermes → Honcho (`honcho:<port>`, memory provider) / GBRAIN (`gbrain:<port>/mcp`, MCP) / Ollama (`host.docker.internal:11434/v1`)
- Hermes API 公開: `:8642` (コア) / `:9119` (dashboard)。`API_SERVER_ENABLED=true` + `API_SERVER_KEY` 必須
- Honcho → `postgres:5432`
- GBRAIN → `postgres:5432`
- hermes-webui → Hermes: **gateway 接続を第一候補** (`hermes:8642`/`:9119`, Bearer=API_SERVER_KEY)。不可なら in-process (hermes コンテナ同居/イメージ派生)
- 監視ページ (dashboard) → GBRAIN / Honcho / Hermes dashboard API (:9119) を叩く (横断監視のみ)

localhost 公開は `hermes-webui:8787` (操作) と `dashboard:8080` (監視) のみ (どちらも 127.0.0.1 bind)。hermes API 等は network 内に閉じ、外部 (LAN/Tailscale) には出さない。

---

## データ配置

| パス | 内容 | 同期/バックアップ |
|---|---|---|
| `~/agent-data/hermes/` | Hermes data (config, SOUL, memories, skills, sessions, state.db, cron) | nightly rsync → filesrv |
| `~/agent-data/postgres/` | Postgres volume (honcho + gbrain) | nightly pg_dump → filesrv |
| `~/agent-data/gbrain/` | brain repo (markdown ページ = source of truth) | nightly rsync → filesrv |
| `~/agent-data/honcho/` | Honcho 設定・キャッシュ | 必要に応じて |
| `.../HomeLabo/ホームラボ/agent_os/` | コード・compose・docs | Syncthing 同期 (OK) |

**重要**: `~/agent-data/` は Syncthing 同期対象から外す。Postgres / SQLite のファイル破損を防ぐ。

---

## ホスト最小依存

Mac に入れるもの:
- **Ollama** (`brew install ollama`) — M4 GPU 推論。これだけは native 必須
- **OrbStack** (`brew install orbstack`) — Docker ランタイム
- 開発時のみ: `make`, `git`

痕跡消去: `brew uninstall ollama orbstack && rm -rf ~/agent-data` で完了。

---

## 主要要件

### Must Have
- [ ] `make up` で Hermes + hermes-webui + Honcho + GBRAIN + Postgres + 監視ページ が起動
- [ ] `make health` で全サービスの health 確認
- [ ] Hermes が Ollama (host) 経由で推論できる
- [ ] Hermes に Honcho が memory provider として active になっている
- [ ] Hermes から GBRAIN の MCP ツールが呼べる
- [ ] hermes-webui が :8787 で起動し chat が通る
- [ ] frontier CLI (Claude Code) への実行委譲が 1 件通る
- [ ] 1 profile が起動し独立して動く (複数 profile は MVP 後)
- [ ] 実行 backend = local でコマンドがコンテナ内に閉じる (Mac 非汚染)
- [ ] `make clean` で全データ消去 → `make up` で再構築
- [ ] `~/agent-data/` 以外の Mac の状態が変わらない

### Should Have
- [ ] Honcho self-host の reasoning も Ollama を使う (外部 API 不使用) ← self-host 決定済み、reasoning endpoint 検証が要
- [ ] Langfuse による trace 可視化
- [ ] nightly backup (pg_dump + rsync → filesrv)
- [ ] 各 profile に Telegram bot

### Nice to Have
- [ ] GBRAIN の publish 機能で knowledge を Web 共有
- [ ] researcher profile の毎朝 digest (Hermes cron)
- [ ] designer profile の画像生成 skill
- [ ] 実行委譲の multi-CLI ルーティング (Claude Code / Codex / Gemini の使い分け)

### Out of Scope
- Proxmox / ubuntu-dev での動作
- 複数 Mac 間の分散
- マルチユーザ
- LangGraph / Letta / Qdrant / 自前 FastAPI (Hermes + GBRAIN + Honcho で代替済み)

---

## パフォーマンス目標

| Operation | 目標 | 備考 |
|---|---|---|
| Ollama 推論 (モデル依存) | initial token < 200ms 目安 (軽量モデル時) | M4 GPU。実行委譲前提でローカルは軽量寄り |
| GBRAIN hybrid search | < 500ms | 数千ページ規模 |
| Honcho prefetch (per turn) | < 1s | provider 自動 |
| Honcho reasoning (background) | < 30s | 非同期 |
| Hermes task (90 turn cap) | task 依存 | 暴走防止に 90 turn 上限あり |

---

## 開発フェーズ (MVP 優先)

| Step | 内容 | 期間目安 |
|---|---|---|
| **M1** | scaffold + docker-compose 骨格 + Postgres (`pgvector/pgvector:pg16`) 起動、init.sql で `CREATE EXTENSION vector;` + honcho/gbrain schema | 0.5日 |
| **M2** | Hermes (Docker, 1 profile) 起動 + Ollama (Mac native) 接続確認 | 1日 |
| **M3** | GBRAIN を MCP 登録 (HTTP MCP 別コンテナが第一候補)、ページ書込/検索が通る。HTTP 不可なら stdio (Hermes に Bun 同梱) へ切替 | 1.5日 (検証込み) |
| **M4** | Honcho self-host を provider 設定。reasoning endpoint を Ollama に向ける検証。不可なら reasoning 無効化し Tier3「保存のみ」で MVP を通す | 1日 |
| **M5** | hermes-webui を compose に追加 (操作 UI, OSS) + 監視ページ自作 (Bun+TS: GBRAIN/Honcho 成長・全体ヘルス・トークン) | 1.5日 |
| **M6** | `make up / health / clean` 整備、runbook、動作確認 | 0.5日 |
| **合計 (MVP)** | | 6-6.5日 |

MVP 後の拡張: 複数 profile / チーム編成、Telegram、cron digest、自動 backup、Langfuse 本格連携、監視ページの推移グラフ磨き、terminal が要るなら hermes-workspace 併用。

---

## 実行委譲 (CLI executors)

利用可能な frontier CLI: **Claude Code / Codex / Gemini CLI** (Daisuke 環境で利用可)。
これらが Agent OS の「実行レイヤー」になる。

役割分担:
- **ローカル Hermes** (Qwen3 系) = オーケストレータ + 記憶 + ルーター。「何を・どの順で・どの CLI に投げるか」を判断
- **frontier CLI** = 実際のコーディング / 編集 / テスト実行を frontier モデル品質で担当

使い分け (将来):
- 深いコーディング = Claude Code (Max 利用)
- 別観点のレビュー / 代替実装 = Codex
- コスト / 速度重視 = Gemini CLI
- Hermes の cross-CLI orchestration (Issue #413) 方向と一致

Docker 隔離との整合:
- CLI は **Hermes コンテナ内に同梱** (`claude`/`codex`/`gemini` を PATH に通す)。Dockerfile でイメージ派生
- 認証は **Daisuke 自身が設定** (Claude Max の OAuth 資格情報をマウント、または各 CLI の API キーを .env)。資格情報の取り扱いは本人が行い、Claude (本アシスタント) は代行しない
- 開発対象は **該当プロジェクトディレクトリだけコンテナにマウント** (フルホストアクセスはしない)。隔離を保ちつつ実ファイルを編集できる

MVP 方針:
- まず **1 executor (Claude Code)** で委譲を確立。Codex / Gemini の使い分けルーティングは MVP 後

---

## マルチエージェント / チーム方針

ADK / CrewAI / LangGraph 等の**外部フレームワークは使わない**。Hermes 組み込みで完結させる。

実現パターン (MVP では使わないが設計として明記):
- **`delegate_task` (subagent 委譲)**: orchestrator profile が子エージェントを spawn して並列処理。階層構造 (ボス→部下)。子同士は直接会話しない。
- **profile 指定の委譲**: `delegate_task` が config.yaml の名前付き profile を呼べる。専門家チーム化 (例: 探索=軽量モデル / 設計=強モデル)。
- **共有ブラックボード = GBRAIN**: ピアツーピア通信が無い代わりに、エージェントが GBRAIN に書く→他が読む、で非同期協調。これが「チームの共通記憶」。

現状の Hermes の限界 (公式認識): 子は使い捨て、state 共有・相互通信は無い (ロードマップ)。
→ 本格的なピアツーピア multi-agent が必要になるまでは、階層委譲 + GBRAIN ブラックボードで対応。

「プロジェクト = orchestrator profile + specialist profiles + 共有 GBRAIN」が将来の標準パターン。

---

## 操作 UI = hermes-webui (採用) + 監視ページ (自作)

操作系は成熟した OSS **hermes-webui** (`nesquena/hermes-webui`, MIT, 7.4k★, v0.51.74) を採用し、
足りない**横断監視**だけを薄く自作する。chat 周りを再発明しない方針。

### 操作 = hermes-webui (そのまま採用)

- Docker イメージ配布: `ghcr.io/nesquena/hermes-webui` (amd64/arm64)、`:8787` で起動、127.0.0.1 bind
- 提供機能 (Daisuke の要望をすべてカバー):
  - **chat** (SSE ストリーミング、tool-call/subagent カード、音声入力、Mermaid)
  - **profile 切替**、**session 閲覧** (CLI session bridge で SQLite からも取込)
  - **Tasks/cron 管理** (一覧/作成/編集/実行/停止/履歴)
  - memory (MEMORY.md/USER.md) 編集、skills 管理 (おまけ)
  - モバイル対応、任意のパスワード認証 (`HERMES_WEBUI_PASSWORD`)
- 構成: Python + vanilla JS。Hermes を in-process 取込 or gateway 接続。`HERMES_WEBUI_AGENT_DIR` / `HERMES_CONFIG_PATH` で Hermes を指す
- compose に 1 サービスとして追加 (固定タグ pin)。前提として Hermes 側で `API_SERVER_ENABLED=true` + `API_SERVER_KEY`

注: hermes-webui に**無い**もの = GBRAIN/Honcho の横断可視化、汎用メトリクス、terminal。→ そこだけ下記で補う。

### 監視ページ (自作, 薄く)

hermes-webui がカバーしない「Hermes 以外 + 全体像」だけを Bun+TS で自作:

1. **記憶の成長** — GBRAIN (ページ/エンティティ/リンク数) / Honcho (peer/session/representation 数)
   - データ源: `gbrain` (HTTP MCP or stats) / Honcho REST API
   - **MVP は現在値表示**。`dashboard_metrics` テーブルへのスナップショット書込は初日から動かす (履歴を失わない)。推移グラフは basic 止まり、磨きは MVP 後
2. **全体ヘルス** — Hermes / hermes-webui / Honcho / GBRAIN / Postgres / Ollama の生死を 1 画面で
3. **トークン / コスト** — Hermes dashboard API (:9119) から取得、または Langfuse 連携 (optional)

実装方針:
- **Bun + TS** 単一サービス (GBRAIN と同ランタイム、gbrain client 再利用)。グラフは Chart.js (CDN)
- `http://localhost:8080`。トップに hermes-webui (`:8787`) へのリンクを置き、操作はそちらへ誘導
- 認証なし (localhost 専用)。Hermes API を叩く際は API_SERVER_KEY を付与

---

## リスクと未確定事項

1. **Hermes の Docker + profiles 運用情報が薄い**
   公式チュートリアルはネイティブ install 前提。Docker での multi-profile 運用は読み替えが必要。
   → Phase 1 で 1 profile の Docker 起動を先に確立してから複数化。

2. **Honcho self-host の reasoning に使う LLM** (self-host は決定事項)
   Honcho は self-host する (managed SaaS は使わない)。background reasoning は LLM を使うため、それを Ollama に向けられるか要確認。
   → M4 で self-host 設定を見て reasoning endpoint を Ollama (host.docker.internal:11434/v1) に指せるか検証。
   **fallback (段階的)**:
   (a) reasoning 用に軽量モデルを別途 Ollama にロードして指す、
   (b) それも不可なら **reasoning を無効化し Tier3 を「保存のみ」(message 蓄積のみ、representation 生成なし) で MVP を通す**。
   いずれも SaaS には逃げない。representation は後日 reasoning が通った時点で backfill。

3. **GBRAIN を Hermes コンテナからどう叩くか** (M3 で検証)
   GBRAIN MCP は stdio (`gbrain serve`) か HTTP。
   - **第一候補**: HTTP MCP (gbrain を別コンテナで起動し HTTP 公開)。疎結合で compose 向き。
   - **fallback**: HTTP が動かない/不安定なら stdio。Hermes コンテナに Bun + gbrain を同梱し `gbrain serve` を stdio で叩く。Dockerfile でイメージ派生が要り工数増 (M3 を 1.5日 に見込み済み)。
   → M3 はまず HTTP を試し、ダメなら即 stdio に倒す。

4. **8B モデルの品質**
   コーディング品質は 32B より落ちる。programmer は Claude Code 委譲で回避する手もある。
   → 実際に試して評価。

5. **Hermes の自己改良がデータを汚す可能性**
   Curator / GEPA が skills を自動更新。想定外挙動は ~/agent-data/hermes/skills/ を見て手修正 (アーカイブは復元可能)。

6. **hermes-webui の Hermes 連携モード** (M5 で検証)
   hermes-webui は Hermes を in-process 取込 (Hermes の venv/モジュールが要る) か gateway 接続。
   - **第一候補**: gateway 接続 (別コンテナの hermes-webui → `hermes:8642`/`:9119`)。疎結合で compose 向き。
   - **fallback**: gateway で機能不足/不動なら in-process (hermes-webui を Hermes コンテナに同居、または Hermes 派生イメージに webui を載せる)。
   → M3 (GBRAIN) と同パターン: まず疎結合、ダメなら同居に倒す。

7. **実行委譲 CLI の認証管理** (runbook 項目)
   Claude Code は Claude Max の OAuth、Codex/Gemini は API キー等。compose/.env.example への載せ方を定義する。
   - API キー系: `.env` (Syncthing 範囲外、コミット禁止) に置き env で渡す
   - Claude Max の OAuth: 資格情報ディレクトリ (例 `~/.claude`) を **read-only volume** で Hermes コンテナにマウント
   - **設定は Daisuke 本人が実施** (Claude は資格情報を代行しない)。runbook に手順を明記。

---

## Success Criteria

- [ ] Mac を再起動しても agent 環境が壊れない
- [ ] `make clean` 後、`~/agent-data/` 以外の Mac 環境に痕跡が残らないことを目視確認
- [ ] 汎用 profile に「このリポジトリの構成を説明して」と聞くと、コンテナ内で動作し Mac に触れない
- [ ] 「私について教えて」と聞くと Honcho の representation を引用した回答が返る
- [ ] 「○○について何を知ってる?」と聞くと GBRAIN のページを引用した回答が返る
- [ ] 1 週間運用して GBRAIN ページ数と Honcho representation が育っていることを確認

---

## ファイル構成 (予定)

```
agent_os/
├─ docker-compose.yml
├─ Makefile
├─ .env.example
├─ .gitignore
├─ .stignore             ← Syncthing 除外
│
├─ docs/
│  ├─ requirements.md    ← この文書
│  ├─ architecture.md
│  ├─ runbook.md
│  └─ ollama-setup.md
│
├─ config/
│  ├─ postgres/init.sql       ← honcho + gbrain schema
│  ├─ hermes/
│  │  ├─ config.yaml          ← model / MCP / memory provider
│  │  └─ Dockerfile           ← hermes + CLI executors (claude 等) 同梱
│  └─ honcho/config.toml
│
├─ monitoring/           ← Bun+TS 監視ページ (自作, localhost:8080)
│  ├─ server.ts          ← GBRAIN/Honcho 横断監視のみ
│  └─ public/
│   （操作 UI = hermes-webui は OSS イメージを compose で起動。自作コード無し）
│
└─ scripts/
   ├─ backup.sh
   └─ health-check.sh
```

---

**Next**: レビュー2巡目を反映 (v3.5)。M1 (scaffold + compose 骨格 + Postgres) から着手可能。
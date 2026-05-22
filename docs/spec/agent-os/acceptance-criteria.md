# Agent OS 受け入れ基準 (逆生成)

**分析日時**: 2026-05-22

---

## 実装済み機能

### 基盤

- [x] `just up` で 7 サービスが起動する
  - [x] Postgres (pgvector) が起動し health check を通過する
  - [x] GBRAIN が HTTP MCP サーバーとして起動する (`/health` 応答)
  - [x] Honcho API が起動する (`/health` 応答)
  - [x] Honcho Deriver がバックグラウンドで稼働する
  - [x] Hermes Agent が Ollama に接続し推論できる
  - [x] hermes-webui が `:8787` で応答する
  - [x] 監視ダッシュボードが `:8080` で応答する
- [x] `just health` で全サービスの OK/FAIL を表示する
- [x] `just down` で全サービスを停止する
- [x] `just clean` で全データ・コンテナ・イメージを消去する (確認プロンプト付き)
- [x] `just clean` → `just up` でゼロから再構築できる

### GBRAIN 連携

- [x] GBRAIN が初回起動時に PGLite で自動初期化する
- [x] GBRAIN が OAuth クライアント登録・トークン発行を自動実行する
- [x] Hermes 起動時に MCP トークンが config.yaml に注入される
- [x] MCP ツールが 9 個に制限される (get_page, put_page, list_pages, search, query, add_tag, get_tags, get_stats, get_health)
- [x] GBRAIN ヘルスチェックが 30s の起動猶予を持つ

### Honcho 連携

- [x] Honcho が Alembic マイグレーションを自動実行する
- [x] embedding 次元が nomic-embed-text 用 (768) に自動修正される
- [x] Deriver が Ollama 経由で推論できる設定になっている

### 監視ダッシュボード

- [x] `/api/health` が 6 サービスのステータスとレイテンシを返す
- [x] `/api/metrics` が GBRAIN (page/chunk/entity/link count) + Honcho (peer/session/app/collection count) を返す
- [x] `/api/tokens` が Hermes トークン情報を返す (利用可能時)
- [x] フロントエンドが 10 秒間隔でポーリングする
- [x] ステータスドットが up=緑 / down=赤 / unknown=灰 で表示される
- [x] 5 分間隔で `dashboard_metrics` テーブルにスナップショットが書き込まれる
- [x] 一部サービスの障害が他の収集をブロックしない

### セキュリティ

- [x] 全外部ポートが `127.0.0.1` バインド
- [x] `.env` がリポジトリに含まれない (`.gitignore`)
- [x] Hermes API に `API_SERVER_KEY` ヘッダー認証が必要
- [x] GBRAIN MCP に OAuth Bearer トークン認証が必要

### クロスプラットフォーム

- [x] `extra_hosts: ["host.docker.internal:host-gateway"]` が Linux 対応で設定済み
- [x] `OLLAMA_BASE_URL` 環境変数で接続先をオーバーライド可能
- [x] `AGENT_DATA` 環境変数でデータパスを指定 (チルダ依存なし)
- [x] README に Mac / Linux 両方のセットアップ手順を記載

### 運用

- [x] `just versions` でサブモジュール・イメージのバージョンを確認できる
- [x] `just update` で全 vendor を最新に更新・再ビルドできる
- [x] `just update-service <name>` で個別サービスを更新できる
- [x] `just rebuild <service>` で更新なし再ビルドできる
- [x] `just psql` で Postgres CLI に接続できる
- [x] `just logs <service>` でサービスログを確認できる

---

## 未実装・検証待ち

### 要検証 (MVP 範囲内)

- [ ] Hermes が Honcho を Tier3 memory provider として実際に使用する
- [ ] hermes-webui でのチャット → Honcho 記憶蓄積 → Deriver 推論の E2E フロー
- [ ] Hermes から GBRAIN の `put_page` / `search` が通る E2E フロー
- [ ] Honcho Deriver → Ollama の推論パスが正常動作する
- [ ] frontier CLI (Claude Code) への実行委譲が 1 件通る

### MVP 後 (Phase 2+)

- [ ] **複数プロファイル**: programmer / researcher / designer の 3 プロファイル運用
- [ ] **Telegram 連携**: 各プロファイルに Telegram bot を割り当て
- [ ] **cron digest**: researcher プロファイルの毎朝 AI/ML digest
- [ ] **自動バックアップ**: nightly pg_dump + rsync → filesrv
- [ ] **Langfuse トレース**: token flow の可視化
- [ ] **推移グラフ**: Chart.js による `dashboard_metrics` のトレンド表示
- [ ] **CLI ルーティング**: Claude Code / Codex / Gemini CLI の使い分け
- [ ] **hermes-webui タグ pin**: `latest` → 固定タグに変更

---

## テスト推奨

### 統合テスト

- [ ] `just up` → 全サービス healthy まで待機 → `just health` 全 OK
- [ ] hermes-webui チャット → Hermes 応答 → Honcho メッセージ保存確認
- [ ] `docker compose exec gbrain gbrain put-page test --content ...` → Hermes `search "test"` でヒット
- [ ] `just clean` → `just up` → 全サービス再起動確認

### 障害テスト

- [ ] Ollama 停止中の `just up` → GBRAIN/Honcho/Dashboard は起動 (Hermes 推論のみ失敗)
- [ ] GBRAIN コンテナ再起動 → OAuth トークン再発行 → Hermes MCP 再接続
- [ ] Postgres 強制再起動 → 依存サービスの自動再接続

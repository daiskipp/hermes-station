# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**hermes-station** — Docker 隔離環境で動く AI エージェント基盤 (Mac / Linux 対応)。
中核は Hermes Agent (Nous Research)、記憶は Honcho (会話/ユーザモデル) + GBRAIN (知識グラフ)。

要件定義: `docs/requirements.md` (v3.5, 設計確定済み)

## Architecture

```
Host:     Ollama (native, GPU) + Docker + just (task runner)
Docker:   Hermes Agent → Honcho (memory provider) + GBRAIN (MCP server)
          Postgres (pgvector) / hermes-webui (OSS, :8787) / monitoring (自作, :8080)
```

- Hermes = オーケストレータ + 記憶 + ルーター (ローカル軽量モデル)
- 実コーディングは frontier CLI (Claude Code 等) に委譲
- データ: `$AGENT_DATA` (デフォルト `~/agent-data/`, Syncthing 同期対象外)
- ネットワーク: bridge 1 本 (`agentos`)、サービス間は compose DNS 名で解決

## Key Commands (予定)

```bash
just up        # 全サービス起動 (Hermes + hermes-webui + Honcho + GBRAIN + Postgres + monitoring)
just health    # 全サービスの health check
just clean     # 全データ・コンテナ消去 ($AGENT_DATA 以外のホストに痕跡を残さない)
```

## Design Principles

1. **Host 隔離**: ホストには Ollama / Docker / just 以外を入れない
2. **完全リセット可能**: `just clean` で全消去 → `just up` で再構築
3. **Syncthing 非汚染**: 永続データは `~/agent-data/` に置く (Syncthing 範囲外)
4. **Local-first**: 推論は Ollama。外部 SaaS 依存を最小化
5. **Reproducible**: Docker イメージは固定タグ pin。`latest` は使わない

## Language / Style

- ドキュメントは日本語 (技術用語は英語のまま)
- コード・コメント・コミットメッセージは英語

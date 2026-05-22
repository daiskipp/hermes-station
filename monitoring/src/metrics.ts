const METRICS_TIMEOUT_MS = 5000;

async function fetchWithTimeout(
  url: string,
  init?: RequestInit,
  timeoutMs: number = METRICS_TIMEOUT_MS
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

// -- GBRAIN metrics via MCP JSON-RPC --

export interface GbrainMetrics {
  available: boolean;
  page_count?: number;
  chunk_count?: number;
  entity_count?: number;
  link_count?: number;
  raw?: Record<string, unknown>;
  error?: string;
}

export async function getGbrainMetrics(): Promise<GbrainMetrics> {
  try {
    const port = process.env.GBRAIN_PORT || "3131";
    const body = {
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: {
        name: "get_brain_identity",
        arguments: {},
      },
    };
    const res = await fetchWithTimeout(`http://gbrain:${port}/mcp`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      return { available: false, error: `HTTP ${res.status}` };
    }
    const data = (await res.json()) as Record<string, unknown>;
    const result = data.result as Record<string, unknown> | undefined;

    // Extract content from MCP tool response
    let parsed: Record<string, unknown> = {};
    if (result && Array.isArray(result.content)) {
      const textContent = (result.content as Array<Record<string, unknown>>).find(
        (c) => c.type === "text"
      );
      if (textContent && typeof textContent.text === "string") {
        try {
          parsed = JSON.parse(textContent.text) as Record<string, unknown>;
        } catch {
          parsed = { rawText: textContent.text };
        }
      }
    }

    return {
      available: true,
      page_count: typeof parsed.page_count === "number" ? parsed.page_count : undefined,
      chunk_count: typeof parsed.chunk_count === "number" ? parsed.chunk_count : undefined,
      entity_count: typeof parsed.entity_count === "number" ? parsed.entity_count : undefined,
      link_count: typeof parsed.link_count === "number" ? parsed.link_count : undefined,
      raw: parsed,
    };
  } catch (err) {
    return {
      available: false,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

// -- Honcho metrics --

export interface HonchoMetrics {
  available: boolean;
  peer_count?: number;
  session_count?: number;
  representation_count?: number;
  app_count?: number;
  collection_count?: number;
  error?: string;
}

export async function getHonchoMetrics(): Promise<HonchoMetrics> {
  try {
    // List apps
    const appsRes = await fetchWithTimeout("http://honcho:8000/v1/apps");
    if (!appsRes.ok) {
      return { available: false, error: `HTTP ${appsRes.status}` };
    }
    const appsData = (await appsRes.json()) as {
      items?: Array<{ id: string }>;
    };
    const apps = appsData.items ?? [];
    const appCount = apps.length;

    // Count collections across apps
    let totalCollections = 0;
    for (const app of apps) {
      try {
        const colRes = await fetchWithTimeout(
          `http://honcho:8000/v1/apps/${app.id}/collections`
        );
        if (colRes.ok) {
          const colData = (await colRes.json()) as { items?: unknown[] };
          totalCollections += colData.items?.length ?? 0;
        }
      } catch {
        // skip on error
      }
    }

    // Try to get peers (v3 API, may not exist)
    let peerCount: number | undefined;
    try {
      const peersRes = await fetchWithTimeout("http://honcho:8000/v1/peers");
      if (peersRes.ok) {
        const peersData = (await peersRes.json()) as { items?: unknown[] };
        peerCount = peersData.items?.length;
      }
    } catch {
      // peers endpoint not available
    }

    return {
      available: true,
      app_count: appCount,
      collection_count: totalCollections,
      ...(peerCount !== undefined ? { peer_count: peerCount } : {}),
    };
  } catch (err) {
    return {
      available: false,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

// -- Hermes token/cost data --

export interface HermesTokens {
  available: boolean;
  data?: Record<string, unknown>;
  error?: string;
}

export async function getHermesTokens(): Promise<HermesTokens> {
  try {
    const port = process.env.HERMES_DASHBOARD_PORT || "9119";
    const apiKey = process.env.API_SERVER_KEY;

    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (apiKey) {
      headers["API_SERVER_KEY"] = apiKey;
    }

    const res = await fetchWithTimeout(`http://hermes:${port}/`, {
      headers,
    });
    if (!res.ok) {
      return { available: false, error: `HTTP ${res.status}` };
    }

    const data = (await res.json()) as Record<string, unknown>;
    return { available: true, data };
  } catch (err) {
    return {
      available: false,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

import sql from "./db.js";

export interface ServiceStatus {
  status: "up" | "down";
  latencyMs: number;
  detail?: string;
}

export interface HealthResult {
  services: Record<string, ServiceStatus>;
}

const HEALTH_TIMEOUT_MS = 3000;

async function fetchWithTimeout(
  url: string,
  timeoutMs: number = HEALTH_TIMEOUT_MS
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function checkService(
  name: string,
  checker: () => Promise<string | undefined>
): Promise<ServiceStatus> {
  const start = performance.now();
  try {
    const detail = await checker();
    const latencyMs = Math.round(performance.now() - start);
    return { status: "up", latencyMs, ...(detail ? { detail } : {}) };
  } catch (err) {
    const latencyMs = Math.round(performance.now() - start);
    const message = err instanceof Error ? err.message : String(err);
    return { status: "down", latencyMs, detail: message };
  }
}

async function checkGbrain(): Promise<string | undefined> {
  const port = process.env.GBRAIN_PORT || "3131";
  const res = await fetchWithTimeout(`http://gbrain:${port}/health`);
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return undefined;
}

async function checkHoncho(): Promise<string | undefined> {
  const res = await fetchWithTimeout("http://honcho:8000/health");
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return undefined;
}

async function checkHermes(): Promise<string | undefined> {
  const port = process.env.HERMES_DASHBOARD_PORT || "9119";
  const res = await fetchWithTimeout(`http://hermes:${port}/`);
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return undefined;
}

async function checkHermesWebui(): Promise<string | undefined> {
  const res = await fetchWithTimeout("http://hermes-webui:8787/");
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return undefined;
}

async function checkPostgres(): Promise<string | undefined> {
  const result = await Promise.race([
    sql`SELECT 1 AS ok`,
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error("timeout")), HEALTH_TIMEOUT_MS)
    ),
  ]);
  if (!result || result.length === 0) throw new Error("empty result");
  return undefined;
}

async function checkOllama(): Promise<string | undefined> {
  const ollamaHost = process.env.OLLAMA_HOST || "host.docker.internal:11434";
  const res = await fetchWithTimeout(
    `http://${ollamaHost}/api/tags`
  );
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data = (await res.json()) as { models?: unknown[] };
  const count = data.models?.length ?? 0;
  return `${count} model(s) loaded`;
}

export async function getAllHealth(): Promise<HealthResult> {
  const [gbrain, honcho, hermes, hermesWebui, postgres, ollama] =
    await Promise.all([
      checkService("gbrain", checkGbrain),
      checkService("honcho", checkHoncho),
      checkService("hermes", checkHermes),
      checkService("hermes-webui", checkHermesWebui),
      checkService("postgres", checkPostgres),
      checkService("ollama", checkOllama),
    ]);

  return {
    services: {
      gbrain,
      honcho,
      hermes,
      "hermes-webui": hermesWebui,
      postgres,
      ollama,
    },
  };
}

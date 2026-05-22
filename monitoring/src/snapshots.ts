import sql from "./db.js";
import { getAllHealth } from "./health.js";
import { getGbrainMetrics, getHonchoMetrics } from "./metrics.js";

const SNAPSHOT_INTERVAL_MS = 5 * 60 * 1000; // 5 minutes

async function writeSnapshot(): Promise<void> {
  const now = new Date();
  const rows: Array<{
    recorded_at: Date;
    service: string;
    metric_name: string;
    metric_value: number;
  }> = [];

  // Collect health latencies
  try {
    const health = await getAllHealth();
    for (const [name, status] of Object.entries(health.services)) {
      rows.push({
        recorded_at: now,
        service: name,
        metric_name: "health_up",
        metric_value: status.status === "up" ? 1 : 0,
      });
      rows.push({
        recorded_at: now,
        service: name,
        metric_name: "latency_ms",
        metric_value: status.latencyMs,
      });
    }
  } catch (err) {
    console.error("[snapshot] health collection failed:", err);
  }

  // Collect GBRAIN metrics
  try {
    const gbrain = await getGbrainMetrics();
    if (gbrain.available) {
      for (const key of ["page_count", "chunk_count", "entity_count", "link_count"] as const) {
        const val = gbrain[key];
        if (val !== undefined) {
          rows.push({
            recorded_at: now,
            service: "gbrain",
            metric_name: key,
            metric_value: val,
          });
        }
      }
    }
  } catch (err) {
    console.error("[snapshot] gbrain metrics failed:", err);
  }

  // Collect Honcho metrics
  try {
    const honcho = await getHonchoMetrics();
    if (honcho.available) {
      for (const key of ["peer_count", "session_count", "representation_count", "app_count", "collection_count"] as const) {
        const val = honcho[key];
        if (val !== undefined) {
          rows.push({
            recorded_at: now,
            service: "honcho",
            metric_name: key,
            metric_value: val,
          });
        }
      }
    }
  } catch (err) {
    console.error("[snapshot] honcho metrics failed:", err);
  }

  // Insert all rows
  if (rows.length > 0) {
    try {
      await sql`
        INSERT INTO dashboard_metrics ${sql(
          rows,
          "recorded_at",
          "service",
          "metric_name",
          "metric_value"
        )}
      `;
      console.log(`[snapshot] wrote ${rows.length} metrics at ${now.toISOString()}`);
    } catch (err) {
      console.error("[snapshot] DB insert failed:", err);
    }
  }
}

let intervalId: ReturnType<typeof setInterval> | null = null;

export function startSnapshots(): void {
  // Initial snapshot on startup
  writeSnapshot().catch((err) =>
    console.error("[snapshot] initial snapshot failed:", err)
  );

  // Periodic snapshots every 5 minutes
  intervalId = setInterval(() => {
    writeSnapshot().catch((err) =>
      console.error("[snapshot] periodic snapshot failed:", err)
    );
  }, SNAPSHOT_INTERVAL_MS);

  console.log(
    `[snapshot] scheduled every ${SNAPSHOT_INTERVAL_MS / 1000}s`
  );
}

export function stopSnapshots(): void {
  if (intervalId) {
    clearInterval(intervalId);
    intervalId = null;
  }
}

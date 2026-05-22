import { join, extname } from "path";
import { getAllHealth } from "./health.js";
import {
  getGbrainMetrics,
  getHonchoMetrics,
  getHermesTokens,
} from "./metrics.js";
import { startSnapshots } from "./snapshots.js";

const PORT = Number(process.env.PORT) || 8080;
const PUBLIC_DIR = join(import.meta.dir, "..", "public");

const MIME_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
};

function jsonResponse(data: unknown, status: number = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function serveStatic(filePath: string): Promise<Response> {
  const file = Bun.file(filePath);
  const exists = await file.exists();
  if (!exists) {
    return new Response("Not Found", { status: 404 });
  }
  const ext = extname(filePath);
  const contentType = MIME_TYPES[ext] || "application/octet-stream";
  return new Response(file, {
    headers: { "Content-Type": contentType },
  });
}

const server = Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname;

    // API routes
    if (path === "/api/health") {
      try {
        const health = await getAllHealth();
        return jsonResponse(health);
      } catch (err) {
        return jsonResponse(
          { error: err instanceof Error ? err.message : String(err) },
          500
        );
      }
    }

    if (path === "/api/metrics") {
      try {
        const [gbrain, honcho] = await Promise.all([
          getGbrainMetrics(),
          getHonchoMetrics(),
        ]);
        return jsonResponse({ gbrain, honcho });
      } catch (err) {
        return jsonResponse(
          { error: err instanceof Error ? err.message : String(err) },
          500
        );
      }
    }

    if (path === "/api/tokens") {
      try {
        const tokens = await getHermesTokens();
        return jsonResponse(tokens);
      } catch (err) {
        return jsonResponse(
          { error: err instanceof Error ? err.message : String(err) },
          500
        );
      }
    }

    // Static file serving
    if (path === "/" || path === "/index.html") {
      return serveStatic(join(PUBLIC_DIR, "index.html"));
    }

    // Serve files from public/
    if (path.startsWith("/public/")) {
      const relPath = path.slice("/public/".length);
      return serveStatic(join(PUBLIC_DIR, relPath));
    }

    // Also try direct static file resolution (e.g., /style.css -> public/style.css)
    const staticPath = join(PUBLIC_DIR, path);
    if (staticPath.startsWith(PUBLIC_DIR)) {
      const file = Bun.file(staticPath);
      if (await file.exists()) {
        return serveStatic(staticPath);
      }
    }

    return new Response("Not Found", { status: 404 });
  },
});

// Start periodic metric snapshots
startSnapshots();

console.log(`[hermes-station-dashboard] listening on http://localhost:${server.port}`);

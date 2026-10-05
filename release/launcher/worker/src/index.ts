import { env } from "cloudflare:workers";
import release from "./release.json";

export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed\n", { status: 405, headers: { Allow: "GET, HEAD" } });
    }
    if (url.pathname === "/health") {
      return Response.json({ status: "ok", ...release });
    }
    if (url.pathname === "/release.json") {
      return Response.json({ iso: null }, { headers: { "Cache-Control": "no-store" } });
    }
    const root = url.pathname === "/";
    if (!root && url.pathname !== "/launcher.sh" && url.pathname !== `/downloads/${release.archive}`) {
      return new Response("Not found\n", { status: 404 });
    }
    if (root) url.pathname = "/launcher.sh";
    const asset = await env.ASSETS.fetch(new Request(url, request));
    if (!asset.ok) {
      console.error(JSON.stringify({ event: "missing_launcher_asset", path: url.pathname, status: asset.status }));
      return new Response("qvOS launcher is temporarily unavailable.\n", { status: 503 });
    }
    const headers = new Headers(asset.headers);
    headers.delete("Content-Encoding");
    const response = new Response(asset.body, { status: asset.status, headers, encodeBody: "manual" });
    response.headers.set("X-Content-Type-Options", "nosniff");
    response.headers.set("Cache-Control", root || url.pathname === "/launcher.sh"
      ? "no-store" : "public, max-age=31536000, immutable");
    response.headers.set("Content-Type", url.pathname.endsWith(".sh")
      ? "text/plain; charset=utf-8" : "application/octet-stream");
    return response;
  },
} satisfies ExportedHandler;

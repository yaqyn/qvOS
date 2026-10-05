import { bindings, defineConfig } from "cf/config";
import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

export default defineConfig({
  accountId: "2220cc93c8046cf865546d00b0915450",
  worker: {
    name: "qvos-launcher",
    compatibilityDate: "2026-10-05",
    entrypoint,
    domains: ["qvos.yaqyn.dev"],
    workersDev: true,
    assets: { runWorkerFirst: true, htmlHandling: "none" },
    env: { ASSETS: bindings.assets() },
    observability: {
      enabled: true,
      logs: { enabled: true, headSamplingRate: 1 },
      traces: { enabled: true, headSamplingRate: 0.01 },
    },
  },
});

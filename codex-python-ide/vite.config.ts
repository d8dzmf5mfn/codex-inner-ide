import { fileURLToPath, URL } from "node:url";
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig(({ mode }) => ({
  plugins: [react()],
  ...(mode === "test" ? {} : {
    define: {
      "import.meta.url": "document.baseURI",
      "process.env.NODE_ENV": JSON.stringify("production")
    }
  }),
  build: {
    outDir: "dist",
    emptyOutDir: true,
    sourcemap: true,
    target: "es2022",
    cssCodeSplit: false,
    lib: {
      entry: fileURLToPath(new URL("./src/main.tsx", import.meta.url)),
      name: "CodexInnerIDE",
      formats: ["iife"],
      fileName: () => "ide.js",
      cssFileName: "ide"
    }
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./tests/setup.ts"]
  }
}));

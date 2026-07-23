import { describe, expect, it } from "vitest";
import {
  LANGUAGE_DEFINITIONS,
  languageForPath,
  preferredInitialFilePath,
  selectionLanguageForPath,
  supportsCodexEdit,
  supportsPythonExecution
} from "../src/core/languages";

describe("language registry", () => {
  it.each([
    ["script.py", "python", "python"],
    ["src/Main.JAVA", "java", "java"],
    ["public/index.html", "html", "html"],
    ["src/App.tsx", "typescript", "typescript"],
    ["vite.config.mjs", "javascript", "javascript"],
    ["styles/main.css", "css", "css"],
    ["tsconfig.json", "json", "json"],
    ["README.md", "markdown", "markdown"],
    ["notes.unknown", "plaintext", "plaintext"]
  ])("maps %s to %s", (path, id, monacoId) => {
    expect(languageForPath(path)).toMatchObject({ id, monacoId });
  });

  it("keeps extensions and default suffixes normalized and unique", () => {
    const extensions = LANGUAGE_DEFINITIONS.flatMap((definition) => [...definition.extensions]);
    expect(new Set(extensions).size).toBe(extensions.length);
    for (const definition of LANGUAGE_DEFINITIONS) {
      expect(definition.defaultExtension.startsWith(".")).toBe(true);
      expect(definition.extensions).toContain(definition.defaultExtension);
    }
  });

  it("keeps execution and Codex edit capabilities Python-only", () => {
    expect(supportsPythonExecution("main.py")).toBe(true);
    expect(supportsCodexEdit("main.py")).toBe(true);
    expect(supportsPythonExecution("Main.java")).toBe(false);
    expect(supportsCodexEdit("src/App.ts")).toBe(false);
    expect(languageForPath("SCRIPT.PY").id).toBe("python");
    expect(supportsPythonExecution("SCRIPT.PY")).toBe(false);
  });

  it("uses real language ids for handoff and text for unknown files", () => {
    expect(selectionLanguageForPath("src/App.ts")).toBe("typescript");
    expect(selectionLanguageForPath("LICENSE")).toBe("text");
  });

  it("preserves Python preference, then opens the first recognized language", () => {
    const files = [
      { kind: "file" as const, relativePath: "LICENSE" },
      { kind: "file" as const, relativePath: "src/App.ts" },
      { kind: "file" as const, relativePath: "main.py" }
    ];
    expect(preferredInitialFilePath(files)).toBe("main.py");
    expect(preferredInitialFilePath(files.slice(0, 2))).toBe("src/App.ts");
    expect(preferredInitialFilePath(files.slice(0, 1))).toBeNull();
  });
});

import { describe, expect, it } from "vitest";
import {
  LANGUAGE_DEFINITIONS,
  languageForPath,
  preferredInitialFilePath,
  registeredLanguageForPath,
  resolveNewFileName,
  runtimeActionForPath,
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

  it("maps each language to its runtime action while keeping Codex edit Python-only", () => {
    expect(supportsPythonExecution("main.py")).toBe(true);
    expect(supportsCodexEdit("main.py")).toBe(true);
    expect(supportsPythonExecution("Main.java")).toBe(false);
    expect(supportsCodexEdit("src/App.ts")).toBe(false);
    expect(languageForPath("SCRIPT.PY").id).toBe("python");
    expect(supportsPythonExecution("SCRIPT.PY")).toBe(false);
    expect(runtimeActionForPath("Main.java")).toBe("run");
    expect(runtimeActionForPath("app.js")).toBe("run");
    expect(runtimeActionForPath("app.ts")).toBe("run");
    expect(runtimeActionForPath("index.html")).toBe("preview");
    expect(runtimeActionForPath("styles.css")).toBe("preview");
    expect(runtimeActionForPath("data.json")).toBe("validate");
    expect(runtimeActionForPath("README.md")).toBe("preview");
    expect(runtimeActionForPath("notes.txt")).toBeNull();
  });

  it("uses real language ids for handoff and text for unknown files", () => {
    expect(selectionLanguageForPath("src/App.ts")).toBe("typescript");
    expect(selectionLanguageForPath("LICENSE")).toBe("text");
  });

  it("resolves recognized extensions without treating unknown files as registered", () => {
    expect(registeredLanguageForPath("src/App.tsx")?.id).toBe("typescript");
    expect(registeredLanguageForPath("notes.custom")).toBeNull();
    expect(registeredLanguageForPath(".gitignore")).toBeNull();
  });

  it("adds the selected language suffix only when a file has no explicit extension", () => {
    expect(resolveNewFileName("Main", "java")).toEqual({
      fileName: "Main.java",
      appendedDefaultExtension: true
    });
    expect(resolveNewFileName("index.html", "typescript")).toEqual({
      fileName: "index.html",
      appendedDefaultExtension: false
    });
    expect(resolveNewFileName(".gitignore", "python")).toEqual({
      fileName: ".gitignore",
      appendedDefaultExtension: false
    });
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

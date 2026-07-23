import { beforeEach, describe, expect, it } from "vitest";
import {
  COMPLETION_TAB_PRECONDITION,
  collectCompletionCandidates,
  completionPrefixAt,
  completionIndex,
  extractSymbols,
  isNoSuggestionsWidget,
  registerCompletionProviders,
  setUserCompletionSnippets,
  shouldSkipIndexedDirectory
} from "../src/core/completions";
import { LANGUAGE_DEFINITIONS, languageForId } from "../src/core/languages";

describe("language-aware completions", () => {
  beforeEach(() => {
    completionIndex.reset("test-workspace");
    setUserCompletionSnippets([]);
  });

  it("extracts user-defined symbols for the active language", () => {
    const python = extractSymbols(
      "class Printer:\n    pass\n\ndef process(value):\n    return value\n\nresult = process(1)\n",
      languageForId("python")
    );
    expect(python.map((value) => [value.label, value.kind])).toEqual([
      ["process", "function"],
      ["Printer", "class"],
      ["result", "variable"]
    ]);

    const typescript = extractSymbols(
      "interface Project {}\nconst prepare = () => {};\nfunction printValue() {}",
      languageForId("typescript")
    );
    expect(typescript.map((value) => value.label)).toEqual(["printValue", "prepare", "Project"]);
  });

  it("merges and de-duplicates sources in the required priority order", () => {
    completionIndex.updateFile({
      relativePath: "lib/helpers.py",
      content: "def prepare_workspace():\n    pass\n"
    });
    setUserCompletionSnippets([{
      id: "custom-print",
      languageId: "python",
      triggerPrefix: "pr",
      displayName: "Print debug value",
      description: "Custom logging",
      body: "print(\"${1:value}\")"
    }]);

    const candidates = collectCompletionCandidates({
      languageId: "python",
      relativePath: "main.py",
      content: "def process_request():\n    pass\n",
      prefix: "pr"
    });

    expect(candidates.slice(0, 2).map((value) => [value.label, value.source])).toEqual([
      ["process_request", "current"],
      ["prepare_workspace", "workspace"]
    ]);
    expect(candidates.find((value) => value.label === "print")?.source).toBe("language");
    expect(candidates.find((value) => value.label === "Print debug value")?.source).toBe("user");

    const duplicate = collectCompletionCandidates({
      languageId: "python",
      relativePath: "main.py",
      content: "def print():\n    pass\n",
      prefix: "pr"
    }).filter((value) => value.label === "print");
    expect(duplicate).toHaveLength(1);
    expect(duplicate[0].source).toBe("current");
  });

  it("updates indexed paths after rename and deletion", () => {
    completionIndex.updateFile({ relativePath: "src/helpers.js", content: "const projectValue = 1;" });
    completionIndex.renamePath("src", "client");
    expect(completionIndex.symbols("javascript")[0]).toMatchObject({
      label: "projectValue",
      relativePath: "client/helpers.js"
    });
    completionIndex.removePath("client");
    expect(completionIndex.symbols("javascript")).toEqual([]);
  });

  it("skips generated directory contents and registers every language profile", () => {
    expect(shouldSkipIndexedDirectory("node_modules")).toBe(true);
    expect(shouldSkipIndexedDirectory("client/dist")).toBe(true);
    expect(shouldSkipIndexedDirectory("client/src")).toBe(false);
    expect(LANGUAGE_DEFINITIONS.every((language) => language.completion != null)).toBe(true);
  });

  it("provides broad offline core catalogs for every supported programming language", () => {
    const minimumCatalogSizes: Partial<Record<(typeof LANGUAGE_DEFINITIONS)[number]["id"], number>> = {
      python: 180,
      java: 90,
      javascript: 80,
      typescript: 100,
      html: 110,
      css: 140,
      json: 20,
      markdown: 10
    };
    for (const language of LANGUAGE_DEFINITIONS) {
      const minimum = minimumCatalogSizes[language.id];
      if (minimum) expect(language.completion.templates.length, language.id).toBeGreaterThanOrEqual(minimum);
    }

    const pythonPR = collectCompletionCandidates({
      languageId: "python",
      relativePath: "main.py",
      content: "",
      prefix: "pr"
    });
    expect(pythonPR.length).toBeGreaterThan(5);
    expect(pythonPR.map((value) => value.label)).toEqual(expect.arrayContaining([
      "print",
      "property",
      "PrettyPrinter",
      "PriorityQueue",
      "Process",
      "ProcessPoolExecutor",
      "Protocol"
    ]));
  });

  it.each([
    ["python", "dat", ["dataclass", "date", "datetime"]],
    ["python", "path", ["Path"]],
    ["java", "arr", ["ArrayList", "Arrays"]],
    ["java", "compl", ["CompletableFuture", "CompletionStage"]],
    ["javascript", "str", ["String", "structuredClone"]],
    ["javascript", "doc", ["document"]],
    ["typescript", "part", ["Partial"]],
    ["typescript", "inter", ["interface", "IntersectionObserver"]],
    ["html", "sec", ["section"]],
    ["html", "aria", ["aria-label"]],
    ["css", "grid-t", ["grid-template", "grid-template-columns", "grid-template-rows"]],
    ["css", "prefers", ["prefers-color-scheme", "prefers-reduced-motion"]],
    ["json", "$", ["$schema", "$ref", "$defs"]],
    ["json", "prop", ["properties"]],
    ["markdown", "str", ["strikethrough"]],
    ["markdown", "tab", ["table"]]
  ] as const)("matches %s catalog entries for the %s prefix", (languageId, prefix, expectedLabels) => {
    const labels = collectCompletionCandidates({
      languageId,
      relativePath: `sample.${languageForId(languageId).defaultExtension.replace(/^\./, "")}`,
      content: "",
      prefix
    }).map((value) => value.label);
    expect(labels).toEqual(expect.arrayContaining([...expectedLabels]));
  });

  it("returns a complete empty result instead of leaving the widget loading", () => {
    let pythonProvider: {
      provideCompletionItems(model: unknown, position: unknown): { incomplete?: boolean; suggestions: unknown[] };
    } | undefined;
    const disposable = { dispose() {} };
    const api = {
      Range: class {},
      languages: {
        CompletionItemInsertTextRule: { InsertAsSnippet: 4 },
        CompletionItemKind: {
          Keyword: 17,
          Function: 1,
          Variable: 5,
          Class: 7,
          Property: 9,
          Snippet: 27
        },
        registerCompletionItemProvider(language: string, provider: typeof pythonProvider) {
          if (language === "python") pythonProvider = provider;
          return disposable;
        }
      }
    };
    registerCompletionProviders(api as never);

    const result = pythonProvider!.provideCompletionItems({
      getLineContent: () => "zzzz-no-match",
      uri: { path: "/main.py" },
      getValue: () => ""
    }, { lineNumber: 1, column: 14 });
    expect(result).toEqual({ incomplete: false, suggestions: [] });
  });

  it("recognizes only the empty suggestion message for immediate dismissal", () => {
    const root = document.createElement("div");
    root.innerHTML = '<div class="suggest-widget message"><div class="message">No suggestions.</div></div>';
    expect(isNoSuggestionsWidget(root)).toBe(true);

    root.querySelector(".suggest-widget > .message")!.textContent = "Loading...";
    expect(isNoSuggestionsWidget(root)).toBe(false);

    root.querySelector(".suggest-widget")!.classList.remove("message");
    root.querySelector(".suggest-widget > .message")!.textContent = "No suggestions.";
    expect(isNoSuggestionsWidget(root)).toBe(false);
  });

  it("recognizes prefixes that Monaco does not treat as plain words", () => {
    expect(completionPrefixAt("$", 2)).toBe("$");
    expect(completionPrefixAt("  $sch", 7)).toBe("$sch");
    expect(completionPrefixAt("grid-t", 7)).toBe("grid-t");
    expect(completionPrefixAt("@med", 5)).toBe("@med");
  });

  it("accepts with Tab only while the suggestion widget has editor focus", () => {
    expect(COMPLETION_TAB_PRECONDITION).toBe("suggestWidgetVisible && editorTextFocus");
    expect(COMPLETION_TAB_PRECONDITION).not.toContain("codexInnerEditReady");
  });
});

import type * as Monaco from "monaco-editor/editor/editor.api.js";
import {
  LANGUAGE_DEFINITIONS,
  languageForId,
  languageForPath,
  type CompletionItemKind,
  type LanguageDefinition,
  type LanguageId
} from "./languages";
import type { CodexInnerIdeHostV1, FileChange, FileSnapshot, UserCompletionSnippet } from "../types/inner-host";

export const COMPLETION_TAB_PRECONDITION = "suggestWidgetVisible && editorTextFocus";
export const MAX_INDEXED_FILES = 1_500;
export const MAX_INDEXED_CHARACTERS = 500_000;

export function completionPrefixAt(line: string, column: number): string {
  return line.slice(0, Math.max(0, column - 1)).match(/[@$A-Za-z_][\w$@-]*$/)?.[0] ?? "";
}

const skippedDirectories = new Set([
  ".git", ".build", ".next", ".nuxt", ".output", ".turbo", ".venv", "build", "coverage",
  "deriveddata", "dist", "node_modules", "out", "pods", "target", "vendor", "venv"
]);

export type CompletionSource = "current" | "workspace" | "language" | "user";

export type CompletionCandidate = {
  label: string;
  insertText: string;
  detail: string;
  kind: CompletionItemKind;
  source: CompletionSource;
  snippet: boolean;
  triggerPrefix?: string;
  relativePath?: string;
};

type IndexedFile = {
  languageId: LanguageId;
  symbols: CompletionCandidate[];
};

export class WorkspaceCompletionIndex {
  private workspaceId: string | null = null;
  private files = new Map<string, IndexedFile>();

  reset(workspaceId: string) {
    this.workspaceId = workspaceId;
    this.files.clear();
  }

  updateFile(snapshot: Pick<FileSnapshot, "relativePath" | "content">) {
    if (snapshot.content.length > MAX_INDEXED_CHARACTERS) {
      this.files.delete(snapshot.relativePath);
      return;
    }
    const language = languageForPath(snapshot.relativePath);
    this.files.set(snapshot.relativePath, {
      languageId: language.id,
      symbols: extractSymbols(snapshot.content, language).map((symbol) => ({
        ...symbol,
        source: "workspace",
        detail: `Workspace symbol · ${snapshot.relativePath}`,
        relativePath: snapshot.relativePath
      }))
    });
  }

  removePath(relativePath: string) {
    for (const path of this.files.keys()) {
      if (path === relativePath || path.startsWith(`${relativePath}/`)) this.files.delete(path);
    }
  }

  renamePath(from: string, to: string) {
    const moved = [...this.files.entries()]
      .filter(([path]) => path === from || path.startsWith(`${from}/`));
    for (const [path] of moved) {
      const value = this.files.get(path)!;
      this.files.delete(path);
      const nextPath = to + path.slice(from.length);
      this.files.set(nextPath, {
        ...value,
        symbols: value.symbols.map((symbol) => ({
          ...symbol,
          relativePath: nextPath,
          detail: `Workspace symbol · ${nextPath}`
        }))
      });
    }
  }

  symbols(languageId: LanguageId, excludingPath?: string): CompletionCandidate[] {
    return [...this.files.entries()]
      .sort(([left], [right]) => left.localeCompare(right))
      .flatMap(([path, file]) => file.languageId === languageId && path !== excludingPath ? file.symbols : []);
  }

  belongsTo(workspaceId: string) {
    return this.workspaceId === workspaceId;
  }
}

export const completionIndex = new WorkspaceCompletionIndex();

let userSnippets: UserCompletionSnippet[] = [];

export function setUserCompletionSnippets(snippets: readonly UserCompletionSnippet[]) {
  userSnippets = snippets.map((snippet) => ({ ...snippet }));
}

export function getUserCompletionSnippets(): UserCompletionSnippet[] {
  return userSnippets.map((snippet) => ({ ...snippet }));
}

export async function indexWorkspace(
  host: CodexInnerIdeHostV1,
  workspaceId: string
): Promise<void> {
  completionIndex.reset(workspaceId);
  const queue = [""];
  const files: string[] = [];
  while (queue.length > 0 && files.length < MAX_INDEXED_FILES) {
    const directory = queue.shift()!;
    let entries;
    try {
      entries = await host.files.list(directory);
    } catch {
      continue;
    }
    for (const entry of entries) {
      if (entry.kind === "directory") {
        if (!shouldSkipIndexedDirectory(entry.relativePath)) queue.push(entry.relativePath);
      } else if (languageForPath(entry.relativePath).id !== "plaintext") {
        files.push(entry.relativePath);
        if (files.length >= MAX_INDEXED_FILES) break;
      }
    }
  }

  for (let offset = 0; offset < files.length; offset += 16) {
    const snapshots = await Promise.allSettled(
      files.slice(offset, offset + 16).map((path) => host.files.read(path))
    );
    if (!completionIndex.belongsTo(workspaceId)) return;
    for (const result of snapshots) {
      if (result.status === "fulfilled") completionIndex.updateFile(result.value);
    }
  }
}

export async function updateCompletionIndexFromChange(
  host: CodexInnerIdeHostV1,
  change: FileChange
): Promise<void> {
  if (change.kind === "deleted") {
    completionIndex.removePath(change.relativePath);
    return;
  }
  try {
    completionIndex.updateFile(await host.files.read(change.relativePath));
  } catch {
    // Directory events and files that disappear between watch and read do not need an index entry.
  }
}

export function shouldSkipIndexedDirectory(relativePath: string): boolean {
  const name = relativePath.split("/").at(-1)?.toLowerCase() ?? "";
  return skippedDirectories.has(name);
}

export function extractSymbols(content: string, language: LanguageDefinition): CompletionCandidate[] {
  const values: CompletionCandidate[] = [];
  const seen = new Set<string>();
  for (const definition of language.completion.symbolPatterns) {
    const flags = definition.pattern.flags.includes("g")
      ? definition.pattern.flags
      : `${definition.pattern.flags}g`;
    const expression = new RegExp(definition.pattern.source, flags);
    for (const match of content.matchAll(expression)) {
      const label = match[1]?.trim();
      const key = label?.toLocaleLowerCase() ?? "";
      if (!label || label.length > 120 || seen.has(key)) continue;
      seen.add(key);
      values.push({
        label,
        insertText: label,
        detail: "Current file symbol",
        kind: definition.kind,
        source: "current",
        snippet: false
      });
    }
  }
  return values;
}

export function collectCompletionCandidates(input: {
  languageId: LanguageId;
  relativePath: string;
  content: string;
  prefix: string;
}): CompletionCandidate[] {
  const language = languageForId(input.languageId);
  const current = extractSymbols(input.content, language);
  const workspace = completionIndex.symbols(input.languageId, input.relativePath);
  const builtins = language.completion.templates.map((item): CompletionCandidate => ({
    ...item,
    source: "language",
    snippet: item.snippet ?? false
  }));
  const custom = userSnippets
    .filter((snippet) => snippet.languageId === input.languageId)
    .map((snippet): CompletionCandidate => ({
      label: snippet.displayName,
      insertText: snippet.body,
      detail: snippet.description || "User completion snippet",
      kind: "snippet",
      source: "user",
      snippet: true,
      triggerPrefix: snippet.triggerPrefix
    }));
  const prefix = input.prefix.toLocaleLowerCase();
  const priorities: Record<CompletionSource, number> = {
    current: 0,
    workspace: 1,
    language: 2,
    user: 3
  };
  const seen = new Set<string>();
  return [...current, ...workspace, ...builtins, ...custom]
    .filter((candidate) => {
      const label = candidate.label.toLocaleLowerCase();
      const trigger = candidate.triggerPrefix?.toLocaleLowerCase() ?? label;
      return !prefix || label.startsWith(prefix) || trigger.startsWith(prefix);
    })
    .sort((left, right) => priorities[left.source] - priorities[right.source]
      || left.label.localeCompare(right.label))
    .filter((candidate) => {
      const key = candidate.label;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
}

export function registerCompletionProviders(api: typeof Monaco): Monaco.IDisposable[] {
  return LANGUAGE_DEFINITIONS.map((language) => api.languages.registerCompletionItemProvider(
    language.monacoId,
    {
      triggerCharacters: [".", "@", ":", "$"],
      provideCompletionItems(model, position) {
        const prefix = completionPrefixAt(model.getLineContent(position.lineNumber), position.column);
        if (!prefix) return { incomplete: false, suggestions: [] };
        const relativePath = model.uri.path.replace(/^\/+/, "");
        const values = collectCompletionCandidates({
          languageId: language.id,
          relativePath,
          content: model.getValue(),
          prefix
        });
        return {
          incomplete: false,
          suggestions: values.map((candidate, index): Monaco.languages.CompletionItem => ({
            label: candidate.label,
            filterText: candidate.triggerPrefix ?? candidate.label,
            insertText: candidate.insertText,
            insertTextRules: candidate.snippet
              ? api.languages.CompletionItemInsertTextRule.InsertAsSnippet
              : undefined,
            detail: candidate.detail,
            kind: monacoKind(api, candidate.kind),
            sortText: `${String(index).padStart(5, "0")}-${candidate.label}`,
            range: new api.Range(
              position.lineNumber,
              position.column - prefix.length,
              position.lineNumber,
              position.column
            )
          }))
        };
      }
    }
  ));
}

function monacoKind(api: typeof Monaco, kind: CompletionItemKind): Monaco.languages.CompletionItemKind {
  switch (kind) {
  case "function": return api.languages.CompletionItemKind.Function;
  case "variable": return api.languages.CompletionItemKind.Variable;
  case "class": return api.languages.CompletionItemKind.Class;
  case "property": return api.languages.CompletionItemKind.Property;
  case "snippet": return api.languages.CompletionItemKind.Snippet;
  default: return api.languages.CompletionItemKind.Keyword;
  }
}

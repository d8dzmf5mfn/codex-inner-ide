export type LanguageId =
  | "python"
  | "java"
  | "html"
  | "typescript"
  | "javascript"
  | "css"
  | "json"
  | "markdown"
  | "plaintext";

export type SelectionLanguageId = Exclude<LanguageId, "plaintext"> | "text";
export type LanguageIconKind = "code" | "markup" | "data" | "text";
export type LanguageExecution = "run" | "preview" | "validate" | null;
export type LanguageEditProvider = "python" | null;

export type LanguageDefinition = Readonly<{
  id: LanguageId;
  label: string;
  monacoId: string;
  extensions: readonly string[];
  defaultExtension: string;
  iconKind: LanguageIconKind;
  execution: LanguageExecution;
  editProvider: LanguageEditProvider;
}>;

export const LANGUAGE_DEFINITIONS = [
  language("python", "Python", "python", [".py"], ".py", "code", "run", "python"),
  language("java", "Java", "java", [".java"], ".java", "code", "run"),
  language("html", "HTML", "html", [".html", ".htm"], ".html", "markup", "preview"),
  language("typescript", "TypeScript", "typescript", [".ts", ".tsx", ".mts", ".cts"], ".ts", "code", "run"),
  language("javascript", "JavaScript", "javascript", [".js", ".jsx", ".mjs", ".cjs"], ".js", "code", "run"),
  language("css", "CSS", "css", [".css"], ".css", "code", "preview"),
  language("json", "JSON", "json", [".json", ".jsonc"], ".json", "data", "validate"),
  language("markdown", "Markdown", "markdown", [".md", ".markdown"], ".md", "text", "preview"),
  language("plaintext", "Plain Text", "plaintext", [".txt", ".log"], ".txt", "text")
] as const satisfies readonly LanguageDefinition[];

const plainText = LANGUAGE_DEFINITIONS.find((definition) => definition.id === "plaintext")!;
const languagesById = new Map(
  LANGUAGE_DEFINITIONS.map((definition) => [definition.id, definition] as const)
);
const languagesByExtension = new Map(
  LANGUAGE_DEFINITIONS.flatMap((definition) =>
    definition.extensions.map((extension) => [extension, definition] as const)
  )
);

export function languageForId(id: LanguageId): LanguageDefinition {
  return languagesById.get(id) ?? plainText;
}

export function registeredLanguageForPath(relativePath: string): LanguageDefinition | null {
  const filename = relativePath.split(/[\\/]/).at(-1)?.toLowerCase() ?? "";
  const dot = filename.lastIndexOf(".");
  if (dot <= 0) return null;
  return languagesByExtension.get(filename.slice(dot)) ?? null;
}

export function languageForPath(relativePath: string): LanguageDefinition {
  return registeredLanguageForPath(relativePath) ?? plainText;
}

export function resolveNewFileName(
  fileName: string,
  languageId: LanguageId
): { fileName: string; appendedDefaultExtension: boolean } {
  const explicitDotfile = fileName.startsWith(".");
  const dot = fileName.lastIndexOf(".");
  const hasExtension = dot > 0 && dot < fileName.length - 1;
  if (explicitDotfile || hasExtension) {
    return { fileName, appendedDefaultExtension: false };
  }
  return {
    fileName: `${fileName}${languageForId(languageId).defaultExtension}`,
    appendedDefaultExtension: true
  };
}

export function supportsPythonExecution(relativePath: string): boolean {
  return relativePath.endsWith(".py") && languageForPath(relativePath).id === "python";
}

export function runtimeActionForPath(relativePath: string): LanguageExecution {
  return languageForPath(relativePath).execution;
}

export function supportsCodexEdit(relativePath: string): boolean {
  return relativePath.endsWith(".py") && languageForPath(relativePath).editProvider === "python";
}

export function selectionLanguageForPath(relativePath: string): SelectionLanguageId {
  const id = languageForPath(relativePath).id;
  return id === "plaintext" ? "text" : id;
}

export function preferredInitialFilePath(
  entries: readonly { kind: "file" | "directory"; relativePath: string }[]
): string | null {
  const files = entries.filter((entry) => entry.kind === "file");
  return files.find((entry) => supportsPythonExecution(entry.relativePath))?.relativePath
    ?? files.find((entry) => languageForPath(entry.relativePath).id !== "plaintext")?.relativePath
    ?? null;
}

function language(
  id: LanguageId,
  label: string,
  monacoId: string,
  extensions: readonly string[],
  defaultExtension: string,
  iconKind: LanguageIconKind,
  execution: LanguageExecution = null,
  editProvider: LanguageEditProvider = null
): LanguageDefinition {
  return {
    id,
    label,
    monacoId,
    extensions,
    defaultExtension,
    iconKind,
    execution,
    editProvider
  };
}

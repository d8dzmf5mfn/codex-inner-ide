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
export type LanguageExecution = "python" | null;
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
  language("python", "Python", "python", [".py"], ".py", "code", "python", "python"),
  language("java", "Java", "java", [".java"], ".java", "code"),
  language("html", "HTML", "html", [".html", ".htm"], ".html", "markup"),
  language("typescript", "TypeScript", "typescript", [".ts", ".tsx", ".mts", ".cts"], ".ts", "code"),
  language("javascript", "JavaScript", "javascript", [".js", ".jsx", ".mjs", ".cjs"], ".js", "code"),
  language("css", "CSS", "css", [".css"], ".css", "code"),
  language("json", "JSON", "json", [".json", ".jsonc"], ".json", "data"),
  language("markdown", "Markdown", "markdown", [".md", ".markdown"], ".md", "text"),
  language("plaintext", "Plain Text", "plaintext", [".txt", ".log"], ".txt", "text")
] as const satisfies readonly LanguageDefinition[];

const plainText = LANGUAGE_DEFINITIONS.find((definition) => definition.id === "plaintext")!;
const languagesByExtension = new Map(
  LANGUAGE_DEFINITIONS.flatMap((definition) =>
    definition.extensions.map((extension) => [extension, definition] as const)
  )
);

export function languageForPath(relativePath: string): LanguageDefinition {
  const filename = relativePath.split(/[\\/]/).at(-1)?.toLowerCase() ?? "";
  const dot = filename.lastIndexOf(".");
  if (dot <= 0) return plainText;
  return languagesByExtension.get(filename.slice(dot)) ?? plainText;
}

export function supportsPythonExecution(relativePath: string): boolean {
  return relativePath.endsWith(".py") && languageForPath(relativePath).execution === "python";
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

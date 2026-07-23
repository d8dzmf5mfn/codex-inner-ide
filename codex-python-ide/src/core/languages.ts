import { CORE_COMPLETION_CATALOGS } from "./completion-catalogs";

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
export type CompletionItemKind = "keyword" | "function" | "variable" | "class" | "property" | "snippet";

export type CompletionTemplate = Readonly<{
  label: string;
  insertText: string;
  detail: string;
  kind: CompletionItemKind;
  snippet?: boolean;
}>;

export type CompletionSymbolPattern = Readonly<{
  pattern: RegExp;
  kind: CompletionItemKind;
}>;

export type LanguageCompletionProfile = Readonly<{
  symbolPatterns: readonly CompletionSymbolPattern[];
  templates: readonly CompletionTemplate[];
}>;

export type LanguageDefinition = Readonly<{
  id: LanguageId;
  label: string;
  monacoId: string;
  extensions: readonly string[];
  defaultExtension: string;
  iconKind: LanguageIconKind;
  execution: LanguageExecution;
  editProvider: LanguageEditProvider;
  completion: LanguageCompletionProfile;
}>;

export const LANGUAGE_DEFINITIONS = [
  language("python", "Python", "python", [".py"], ".py", "code", "run", "python", {
    symbolPatterns: [
      symbol(/(?:^|\n)\s*def\s+([A-Za-z_]\w*)/g, "function"),
      symbol(/(?:^|\n)\s*class\s+([A-Za-z_]\w*)/g, "class"),
      symbol(/(?:^|\n)\s*([A-Za-z_]\w*)\s*=(?!=)/g, "variable")
    ],
    templates: [
      ...keywords("and", "as", "async", "await", "break", "class", "continue", "def", "elif", "else", "except", "False", "finally", "for", "from", "if", "import", "in", "is", "lambda", "None", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"),
      template("print", "print(${1:value})", "Print a value", "function", true),
      template("property", "@property\ndef ${1:name}(self):\n    return ${2:value}", "Property definition", "snippet", true),
      template("main", "if __name__ == \"__main__\":\n    ${1:main()}", "Main entry point", "snippet", true),
      ...catalog("python")
    ]
  }),
  language("java", "Java", "java", [".java"], ".java", "code", "run", null, {
    symbolPatterns: [
      symbol(/\b(?:class|interface|enum|record)\s+([A-Za-z_]\w*)/g, "class"),
      symbol(/\b(?:public|protected|private|static|final|synchronized|native|abstract|default|\s)+[\w<>,.?\[\]]+\s+([A-Za-z_]\w*)\s*\(/g, "function"),
      symbol(/\b(?:final\s+)?[A-Z_a-z][\w<>,.?\[\]]*\s+([a-z_]\w*)\s*(?:=|;)/g, "variable")
    ],
    templates: [
      ...keywords("abstract", "boolean", "break", "case", "catch", "class", "continue", "default", "do", "else", "enum", "extends", "final", "finally", "for", "if", "implements", "import", "instanceof", "interface", "new", "package", "private", "protected", "public", "record", "return", "static", "super", "switch", "this", "throw", "throws", "try", "void", "while"),
      template("println", "System.out.println(${1:value});", "Print a line", "function", true),
      template("main", "public static void main(String[] args) {\n    ${1}\n}", "Main method", "snippet", true),
      template("public method", "public ${1:void} ${2:name}(${3}) {\n    ${4}\n}", "Public method", "snippet", true),
      ...catalog("java")
    ]
  }),
  language("html", "HTML", "html", [".html", ".htm"], ".html", "markup", "preview", null, {
    symbolPatterns: [
      symbol(/\bid=["']([A-Za-z_][\w-]*)["']/g, "property"),
      symbol(/\bclass=["']([A-Za-z_][\w-]*)/g, "property")
    ],
    templates: [
      ...keywords("article", "aside", "body", "button", "div", "footer", "form", "head", "header", "html", "img", "input", "label", "link", "main", "meta", "nav", "script", "section", "span", "style", "title"),
      template("doctype", "<!doctype html>", "HTML document type", "snippet"),
      template("document", "<!doctype html>\n<html lang=\"${1:en}\">\n<head>\n  <meta charset=\"UTF-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n  <title>${2:Document}</title>\n</head>\n<body>\n  ${3}\n</body>\n</html>", "HTML document", "snippet", true),
      ...catalog("html")
    ]
  }),
  language("typescript", "TypeScript", "typescript", [".ts", ".tsx", ".mts", ".cts"], ".ts", "code", "run", null, javascriptCompletion(true)),
  language("javascript", "JavaScript", "javascript", [".js", ".jsx", ".mjs", ".cjs"], ".js", "code", "run", null, javascriptCompletion(false)),
  language("css", "CSS", "css", [".css"], ".css", "code", "preview", null, {
    symbolPatterns: [
      symbol(/(?:^|[}\s])\.([A-Za-z_][\w-]*)/g, "class"),
      symbol(/--([A-Za-z_][\w-]*)\s*:/g, "variable")
    ],
    templates: [
      ...keywords("align-items", "background", "border", "color", "display", "flex", "font-family", "font-size", "gap", "grid", "height", "justify-content", "margin", "padding", "position", "width"),
      template("media", "@media (${1:width <= 768px}) {\n  ${2}\n}", "Media query", "snippet", true),
      template("root", ":root {\n  --${1:color}: ${2:#000};\n}", "Root custom properties", "snippet", true),
      ...catalog("css")
    ]
  }),
  language("json", "JSON", "json", [".json", ".jsonc"], ".json", "data", "validate", null, {
    symbolPatterns: [symbol(/"([^"\\]+)"\s*:/g, "property")],
    templates: [
      ...keywords("false", "null", "true"),
      template("object", "{\n  \"${1:key}\": ${2:value}\n}", "JSON object", "snippet", true),
      template("array", "[\n  ${1}\n]", "JSON array", "snippet", true),
      ...catalog("json")
    ]
  }),
  language("markdown", "Markdown", "markdown", [".md", ".markdown"], ".md", "text", "preview", null, {
    symbolPatterns: [symbol(/(?:^|\n)#{1,6}\s+(.+)/g, "property")],
    templates: [
      template("heading", "# ${1:Heading}", "Heading", "snippet", true),
      template("link", "[${1:label}](${2:https://example.com})", "Link", "snippet", true),
      template("code", "``` ${1:language}\n${2}\n```", "Fenced code block", "snippet", true),
      ...catalog("markdown")
    ]
  }),
  language("plaintext", "Plain Text", "plaintext", [".txt", ".log"], ".txt", "text", null, null, {
    symbolPatterns: [],
    templates: [...catalog("plaintext")]
  })
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
  execution: LanguageExecution,
  editProvider: LanguageEditProvider,
  completion: LanguageCompletionProfile
): LanguageDefinition {
  return {
    id,
    label,
    monacoId,
    extensions,
    defaultExtension,
    iconKind,
    execution,
    editProvider,
    completion
  };
}

function symbol(pattern: RegExp, kind: CompletionItemKind): CompletionSymbolPattern {
  return { pattern, kind };
}

function template(
  label: string,
  insertText: string,
  detail: string,
  kind: CompletionItemKind,
  snippet = false
): CompletionTemplate {
  return { label, insertText, detail, kind, snippet };
}

function keywords(...values: string[]): CompletionTemplate[] {
  return values.map((value) => template(value, value, "Language keyword", "keyword"));
}

function javascriptCompletion(typescript: boolean): LanguageCompletionProfile {
  const languageKeywords = [
    "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default",
    "delete", "do", "else", "export", "extends", "false", "finally", "for", "from", "function", "if",
    "import", "in", "instanceof", "let", "new", "null", "return", "static", "super", "switch", "this",
    "throw", "true", "try", "typeof", "undefined", "var", "void", "while", "yield"
  ];
  if (typescript) languageKeywords.push("as", "enum", "implements", "interface", "keyof", "namespace", "readonly", "satisfies", "type", "unknown");
  return {
    symbolPatterns: [
      symbol(/\b(?:async\s+)?function\s+([A-Za-z_$][\w$]*)/g, "function"),
      symbol(/\bclass\s+([A-Za-z_$][\w$]*)/g, "class"),
      symbol(/\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)/g, "variable"),
      ...(typescript
        ? [
          symbol(/\b(?:interface|type|enum|namespace)\s+([A-Za-z_$][\w$]*)/g, "class")
        ]
        : [])
    ],
    templates: [
      ...keywords(...languageKeywords),
      template("console.log", "console.log(${1:value});", "Log a value", "function", true),
      template("Promise", "new Promise((resolve, reject) => {\n  ${1}\n})", "Create a Promise", "snippet", true),
      template("arrow function", "const ${1:name} = (${2}) => {\n  ${3}\n};", "Arrow function", "snippet", true),
      ...catalog("javascript"),
      ...(typescript ? catalog("typescript") : [])
    ]
  };
}

function catalog(languageId: string): CompletionTemplate[] {
  return (CORE_COMPLETION_CATALOGS[languageId] ?? []).map((item) => ({ ...item }));
}

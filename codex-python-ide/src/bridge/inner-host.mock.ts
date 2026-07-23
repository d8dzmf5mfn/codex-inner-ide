import type {
  CodexInnerIdeHostV1,
  FileChange,
  FileEntry,
  FileKind,
  FileSnapshot,
  GlobalPreferences,
  HandoffResult,
  IdeWindowState,
  PythonExecutionEvent,
  PythonEditProposalEvent,
  PythonInterpreter,
  RecentWorkspace,
  RuntimeDescriptor,
  RuntimeExecutionEvent,
  WorkspaceBinding
} from "../types/inner-host";

const initialFiles: Record<string, string> = {
  "main.py": `from pathlib import Path


def count_words(path: Path) -> int:
    return len(path.read_text(encoding="utf-8").split())


if __name__ == "__main__":
    print("Codex Inner IDE is ready")
`,
  "utils.py": `def clamp(value: int, minimum: int, maximum: int) -> int:
    return max(minimum, min(value, maximum))
`,
  "tests/test_main.py": `from pathlib import Path

from main import count_words


def test_count_words(tmp_path: Path) -> None:
    sample = tmp_path / "sample.txt"
    sample.write_text("one two three", encoding="utf-8")
    assert count_words(sample) == 3
`,
  "README.md": "# Python example\n\nOpened by the Codex Inner IDE development host.\n",
  "Main.java": "public class Main { public static void main(String[] args) { System.out.println(\"Hello Java\"); } }\n",
  "app.js": "console.log(\"Hello JavaScript\");\n",
  "app.ts": "const message: string = \"Hello TypeScript\";\nconsole.log(message);\n",
  "index.html": "<!doctype html><html><head><link rel=\"stylesheet\" href=\"styles.css\"></head><body><h1>HTML Preview</h1></body></html>\n",
  "styles.css": "body { font-family: system-ui; padding: 2rem; }\n",
  "data.json": "{\"ready\": true}\n"
};

function randomId(): string {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

async function digest(content: string): Promise<string> {
  const bytes = new TextEncoder().encode(content);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function directEntries(files: Map<string, string>, directories: Set<string>, directory: string): FileEntry[] {
  const prefix = directory ? `${directory}/` : "";
  const values = new Map<string, FileKind>();
  for (const relativePath of [...directories, ...files.keys()]) {
    if (!relativePath.startsWith(prefix)) continue;
    const remainder = relativePath.slice(prefix.length);
    if (!remainder) continue;
    const [name, ...rest] = remainder.split("/");
    const directPath = prefix + name;
    const isDirectory = rest.length > 0 || directories.has(directPath);
    if (isDirectory || !values.has(name)) values.set(name, isDirectory ? "directory" : "file");
  }
  return Array.from(values, ([name, kind]) => ({
    name,
    relativePath: prefix + name,
    kind
  })).sort((left, right) => left.kind === right.kind
    ? left.name.localeCompare(right.name)
    : left.kind === "directory" ? -1 : 1);
}

function handoff(): HandoffResult {
  return {
    destination: "chatgpt",
    mechanism: "quickChatShortcut",
    submitted: false
  };
}

export function createMockInnerHost(): CodexInnerIdeHostV1 {
  const files = new Map(Object.entries(initialFiles));
  const directories = new Set<string>(["tests"]);
  const fileListeners = new Set<(change: FileChange) => void>();
  const pythonListeners = new Set<(event: PythonExecutionEvent) => void>();
  const runtimeListeners = new Set<(event: RuntimeExecutionEvent) => void>();
  const editListeners = new Set<(event: PythonEditProposalEvent) => void>();
  const primaryWorkspace: WorkspaceBinding = {
    id: "mock-workspace",
    name: "python-example",
    rootLabel: "demo/python-example"
  };
  const secondaryWorkspace: WorkspaceBinding = {
    id: "mock-secondary",
    name: "web-example",
    rootLabel: "demo/web-example"
  };
  let currentWorkspace = primaryWorkspace;
  let recentWorkspaces: RecentWorkspace[] = [
    { ...primaryWorkspace, available: true },
    { ...secondaryWorkspace, available: true },
    { id: "mock-missing", name: "missing-example", rootLabel: "demo/missing-example", available: false }
  ];
  const stateByWorkspace = new Map<string, IdeWindowState>();
  let preferences: GlobalPreferences = { themeMode: "auto", completionSnippets: [] };

  const interpreter: PythonInterpreter = {
    id: "mock-python",
    executable: "/usr/bin/python3",
    version: "Python 3.14",
    source: "path"
  };

  const emitFile = (change: FileChange) => fileListeners.forEach((listener) => listener(change));
  const descriptor = (languageId: string): RuntimeDescriptor => {
    const action = languageId === "html" || languageId === "css" || languageId === "markdown"
      ? "preview"
      : languageId === "json" ? "validate" : languageId === "plaintext" ? "none" : "run";
    return {
      id: `mock-${languageId}`,
      languageId,
      label: action === "preview" ? `${languageId.toUpperCase()} Preview` : `Mock ${languageId}`,
      version: "Development",
      source: action === "preview" || action === "validate" ? "builtin" : "path",
      action,
      available: action !== "none",
      unavailableReason: action === "none" ? "Plain text cannot run" : null
    };
  };

  return {
    apiVersion: "1",
    workspace: {
      async current() { return structuredClone(currentWorkspace); },
      async choose() {
        currentWorkspace = secondaryWorkspace;
        recentWorkspaces = [
          { ...secondaryWorkspace, available: true },
          ...recentWorkspaces.filter((workspace) => workspace.id !== secondaryWorkspace.id)
        ].slice(0, 10);
        return structuredClone(currentWorkspace);
      },
      async recent() { return structuredClone(recentWorkspaces); },
      async openRecent(id) {
        const workspace = recentWorkspaces.find((value) => value.id === id);
        if (!workspace) throw new Error("Unknown recent workspace");
        if (!workspace.available) throw new Error("This recent workspace is no longer available");
        currentWorkspace = workspace.id === primaryWorkspace.id ? primaryWorkspace : secondaryWorkspace;
        return structuredClone(currentWorkspace);
      },
      async removeRecent(id) {
        recentWorkspaces = recentWorkspaces.filter((workspace) => workspace.id !== id);
      },
      async relocateRecent(id) {
        if (!recentWorkspaces.some((workspace) => workspace.id === id)) {
          throw new Error("Unknown recent workspace");
        }
        currentWorkspace = {
          id: "mock-relocated",
          name: "relocated-example",
          rootLabel: "demo/relocated-example"
        };
        recentWorkspaces = [
          { ...currentWorkspace, available: true },
          ...recentWorkspaces.filter((workspace) => workspace.id !== id)
        ].slice(0, 10);
        return structuredClone(currentWorkspace);
      }
    },
    files: {
      async list(relativePath = "") { return directEntries(files, directories, relativePath); },
      async read(relativePath) {
        const content = files.get(relativePath);
        if (content === undefined) throw new Error(`File not found: ${relativePath}`);
        return { relativePath, content, digest: await digest(content), readonly: false };
      },
      async write(request) {
        const current = files.get(request.relativePath);
        if (current === undefined) throw new Error(`File not found: ${request.relativePath}`);
        if (await digest(current) !== request.expectedDigest) {
          const error = new Error("File changed on disk");
          error.name = "FileChangedError";
          throw error;
        }
        files.set(request.relativePath, request.content);
        const snapshot: FileSnapshot = {
          relativePath: request.relativePath,
          content: request.content,
          digest: await digest(request.content),
          readonly: false
        };
        emitFile({ relativePath: request.relativePath, kind: "changed", source: "ide" });
        return snapshot;
      },
      async create({ relativePath, kind }) {
        if (kind === "file") files.set(relativePath, "");
        else directories.add(relativePath);
        const entry = { name: relativePath.split("/").at(-1) ?? relativePath, relativePath, kind };
        emitFile({ relativePath, kind: "created", source: "ide" });
        return entry;
      },
      async rename({ from, to }) {
        const isDirectory = directories.has(from);
        const affected = [...files.entries()].filter(([path]) => path === from || path.startsWith(`${from}/`));
        for (const [path, content] of affected) {
          files.delete(path);
          files.set(to + path.slice(from.length), content);
        }
        for (const path of [...directories]) {
          if (path === from || path.startsWith(`${from}/`)) {
            directories.delete(path);
            directories.add(to + path.slice(from.length));
          }
        }
        const kind: FileKind = isDirectory ? "directory" : "file";
        emitFile({ relativePath: from, kind: "deleted", source: "ide" });
        emitFile({ relativePath: to, kind: "created", source: "ide" });
        return { name: to.split("/").at(-1) ?? to, relativePath: to, kind };
      },
      async trash(relativePath) {
        for (const path of [...files.keys()]) {
          if (path === relativePath || path.startsWith(`${relativePath}/`)) files.delete(path);
        }
        for (const path of [...directories]) {
          if (path === relativePath || path.startsWith(`${relativePath}/`)) directories.delete(path);
        }
        emitFile({ relativePath, kind: "deleted", source: "ide" });
      },
      watch(listener) {
        fileListeners.add(listener);
        return () => fileListeners.delete(listener);
      }
    },
    python: {
      async discover() { return [interpreter]; },
      async createVenv() {
        return { ...interpreter, id: "mock-venv", executable: ".venv/bin/python", source: ".venv" };
      },
      async run(relativePath, interpreterId) {
        if (interpreterId !== interpreter.id) throw new Error("Interpreter is unavailable");
        const runId = randomId();
        queueMicrotask(() => {
          pythonListeners.forEach((listener) => listener({ runId, kind: "started" }));
          const text = files.get(relativePath)?.includes("raise RuntimeError")
            ? `Traceback (most recent call last):\n  File "${relativePath}", line 1\nRuntimeError: development preview\n`
            : "Codex Inner IDE is ready\n";
          pythonListeners.forEach((listener) => listener({ runId, kind: "output", stream: "stdout", text }));
          pythonListeners.forEach((listener) => listener({
            runId,
            kind: "exited",
            exitCode: text.includes("RuntimeError") ? 1 : 0,
            diagnostics: text.includes("RuntimeError")
              ? [{ relativePath, line: 1, column: 1, severity: "error", message: "RuntimeError: development preview" }]
              : []
          }));
        });
        return { runId };
      },
      async terminate(runId) {
        pythonListeners.forEach((listener) => listener({ runId, kind: "exited", exitCode: 143 }));
      },
      async checkSyntax() { return []; },
      subscribe(listener) {
        pythonListeners.add(listener);
        return () => pythonListeners.delete(listener);
      }
    },
    runtime: {
      async discover(languageId) { return [descriptor(languageId)]; },
      async execute(request) {
        const runId = randomId();
        queueMicrotask(() => {
          runtimeListeners.forEach((listener) => listener({
            runId,
            languageId: request.languageId,
            kind: "started"
          }));
          const text = request.languageId === "json" ? "Valid JSON\n" : `Ran ${request.relativePath}\n`;
          runtimeListeners.forEach((listener) => listener({
            runId,
            languageId: request.languageId,
            kind: "output",
            stream: "stdout",
            text
          }));
          runtimeListeners.forEach((listener) => listener({
            runId,
            languageId: request.languageId,
            kind: "exited",
            exitCode: 0,
            diagnostics: []
          }));
        });
        return { runId };
      },
      async terminate(runId) {
        runtimeListeners.forEach((listener) => listener({
          runId,
          languageId: "plaintext",
          kind: "exited",
          exitCode: 143
        }));
      },
      async check() { return []; },
      subscribe(listener) {
        runtimeListeners.add(listener);
        return () => runtimeListeners.delete(listener);
      }
    },
    preview: {
      async open(request) {
        if (request.languageId === "markdown") {
          return {
            relativePath: request.relativePath,
            languageId: request.languageId,
            content: files.get(request.relativePath) ?? "",
            entryRelativePath: request.relativePath
          };
        }
        const entry = request.languageId === "css" ? "index.html" : request.relativePath;
        const content = files.get(entry) ?? "<p>Preview unavailable</p>";
        return {
          relativePath: request.relativePath,
          languageId: request.languageId,
          url: `data:text/html;charset=utf-8,${encodeURIComponent(content)}`,
          entryRelativePath: entry
        };
      },
      async openExternal(request) { return this.open(request); }
    },
    preferences: {
      async load() { return structuredClone(preferences); },
      async save(next) {
        preferences = structuredClone(next);
        return structuredClone(preferences);
      }
    },
    chatgpt: {
      async moreDetails() { return handoff(); }
    },
    edits: {
      async request(request) {
        const proposalId = randomId();
        const content = files.get("main.py") ?? "";
        const baseBufferDigest = await digest(content);
        queueMicrotask(() => editListeners.forEach((listener) => listener({
          proposal: {
            proposalId,
            workspaceId: currentWorkspace.id,
            relativePath: "main.py",
            scope: request.scope === "selection" ? "selection" : "file",
            baseBufferDigest,
            summary: request.instruction,
            replacementText: `${content}\n# Proposed by Codex\n`,
            state: "ready"
          }
        })));
        return { proposalId, state: "generating" };
      },
      async cancel(proposalId) {
        editListeners.forEach((listener) => listener({
          proposal: {
            proposalId,
            workspaceId: currentWorkspace.id,
            relativePath: "main.py",
            scope: "file",
            baseBufferDigest: "",
            summary: "Cancelled",
            replacementText: "",
            state: "rejected"
          }
        }));
        return { cancelled: true };
      },
      async decide() {},
      subscribe(listener) {
        editListeners.add(listener);
        return () => editListeners.delete(listener);
      }
    },
    window: {
      setDirty() {},
      setPinned() {},
      async loadState() { return structuredClone(stateByWorkspace.get(currentWorkspace.id) ?? null); },
      async saveState(nextState) { stateByWorkspace.set(currentWorkspace.id, structuredClone(nextState)); },
      async closeIde() {}
    }
  };
}

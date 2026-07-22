import type {
  CodexInnerIdeHostV1,
  FileChange,
  FileEntry,
  FileKind,
  FileSnapshot,
  HandoffResult,
  IdeWindowState,
  PythonExecutionEvent,
  PythonEditProposalEvent,
  PythonInterpreter
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
  "README.md": "# Python example\n\nOpened by the Codex Inner IDE development host.\n"
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

function handoff(destination: "codex" | "chatgpt"): HandoffResult {
  return {
    destination,
    mechanism: destination === "codex" ? "composer" : "quickChatShortcut",
    submitted: false
  };
}

export function createMockInnerHost(): CodexInnerIdeHostV1 {
  const files = new Map(Object.entries(initialFiles));
  const directories = new Set<string>(["tests"]);
  const fileListeners = new Set<(change: FileChange) => void>();
  const pythonListeners = new Set<(event: PythonExecutionEvent) => void>();
  const editListeners = new Set<(event: PythonEditProposalEvent) => void>();
  let state: IdeWindowState | null = null;

  const interpreter: PythonInterpreter = {
    id: "mock-python",
    executable: "/usr/bin/python3",
    version: "Python 3.14",
    source: "path"
  };

  const emitFile = (change: FileChange) => fileListeners.forEach((listener) => listener(change));

  return {
    apiVersion: "1",
    workspace: {
      async current() {
        return { id: "mock-workspace", name: "python-example", rootLabel: "demo/python-example" };
      },
      async choose() { return this.current(); }
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
    codex: {
      async addToChat() { return handoff("codex"); }
    },
    chatgpt: {
      async moreDetails() { return handoff("chatgpt"); }
    },
    edits: {
      async request(request) {
        const proposalId = randomId();
        const content = files.get("main.py") ?? "";
        const baseBufferDigest = await digest(content);
        queueMicrotask(() => editListeners.forEach((listener) => listener({
          proposal: {
            proposalId,
            workspaceId: "mock-workspace",
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
            workspaceId: "mock-workspace",
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
      async loadState() { return state; },
      async saveState(nextState) { state = structuredClone(nextState); },
      async closeIde() {}
    }
  };
}

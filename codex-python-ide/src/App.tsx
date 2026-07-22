import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Code2, Play, RotateCcw, Save, TriangleAlert, X } from "lucide-react";
import { resolveInnerHost } from "./bridge/inner-host";
import {
  editDocument,
  markDocumentSaved,
  openDocument,
  replaceCleanDocument,
  type OpenDocument
} from "./core/documents";
import { EditorPane } from "./components/EditorPane";
import { FileTree } from "./components/FileTree";
import { OutputPanel } from "./components/OutputPanel";
import type {
  CodexInnerIdeHostV1,
  Diagnostic,
  DocumentViewState,
  FileEntry,
  FileKind,
  FileSnapshot,
  IdeSelectionContext,
  PythonInterpreter,
  SelectionRange,
  WorkspaceBinding
} from "./types/inner-host";

type Conflict = { relativePath: string; disk: FileSnapshot };
type LoadedIde = {
  workspace: WorkspaceBinding;
  rootEntries: FileEntry[];
  interpreters: PythonInterpreter[];
  savedExpanded: string[];
  savedViews: Record<string, DocumentViewState>;
};

export function App() {
  const host = useMemo(resolveInnerHost, []);
  return host ? <PythonIde host={host} /> : <MissingHost />;
}

function MissingHost() {
  return (
    <main className="missing-host">
      <Code2 size={28} strokeWidth={1.5} aria-hidden="true" />
      <h1>Local IDE bridge unavailable</h1>
      <p>Launch this renderer through the Codex Inner IDE menu-bar controller.</p>
    </main>
  );
}

function PythonIde({ host }: { host: CodexInnerIdeHostV1 }) {
  const [loaded, setLoaded] = useState<LoadedIde | null>(null);
  const [documents, setDocuments] = useState<OpenDocument[]>([]);
  const [activePath, setActivePath] = useState<string | null>(null);
  const [selectedInterpreterId, setSelectedInterpreterId] = useState("");
  const [bottomPanelOpen, setBottomPanelOpen] = useState(true);
  const [expandedDirectories, setExpandedDirectories] = useState<string[]>([]);
  const [documentViews, setDocumentViews] = useState<Record<string, DocumentViewState>>({});
  const [treeRevision, setTreeRevision] = useState(0);
  const [running, setRunning] = useState(false);
  const [runId, setRunId] = useState<string | null>(null);
  const [exitCode, setExitCode] = useState<number | null>(null);
  const [output, setOutput] = useState("");
  const [diagnostics, setDiagnostics] = useState<Diagnostic[]>([]);
  const [revealDiagnostic, setRevealDiagnostic] = useState<Diagnostic | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [conflict, setConflict] = useState<Conflict | null>(null);
  const documentsRef = useRef(documents);

  useEffect(() => {
    documentsRef.current = documents;
    host.window.setDirty(documents.some((document) => document.dirty));
  }, [documents, host]);

  useEffect(() => {
    let cancelled = false;
    void Promise.all([
      host.workspace.current(),
      host.files.list(""),
      host.python.discover().catch(() => [] as PythonInterpreter[]),
      host.window.loadState()
    ]).then(async ([workspace, rootEntries, interpreters, savedState]) => {
      const preferred = savedState?.openPaths ?? [];
      const fallback = rootEntries.find((entry) => entry.kind === "file" && entry.name.endsWith(".py"))?.relativePath;
      const paths = preferred.length > 0 ? preferred : fallback ? [fallback] : [];
      const results = await Promise.allSettled(paths.map((path) => host.files.read(path)));
      const initialDocuments = results
        .filter((result): result is PromiseFulfilledResult<FileSnapshot> => result.status === "fulfilled")
        .map((result) => openDocument(result.value));
      const openPaths = initialDocuments.map((document) => document.relativePath);
      const initialActive = savedState?.activePath && openPaths.includes(savedState.activePath)
        ? savedState.activePath
        : openPaths[0] ?? null;
      if (cancelled) return;
      setLoaded({
        workspace,
        rootEntries,
        interpreters,
        savedExpanded: savedState?.expandedDirectories ?? [],
        savedViews: savedState?.documentViews ?? {}
      });
      setDocuments(initialDocuments);
      setActivePath(initialActive);
      setSelectedInterpreterId(interpreters[0]?.id ?? "");
      setBottomPanelOpen(savedState?.bottomPanelOpen ?? true);
      setExpandedDirectories(savedState?.expandedDirectories ?? []);
      setDocumentViews(savedState?.documentViews ?? {});
    }).catch((reason: unknown) => {
      if (!cancelled) setError(message(reason, "Unable to initialize the IDE"));
    });
    return () => { cancelled = true; };
  }, [host]);

  useEffect(() => {
    if (!loaded) return;
    const timer = window.setTimeout(() => {
      void host.window.saveState({
        openPaths: documents.map((document) => document.relativePath),
        activePath,
        bottomPanelOpen,
        expandedDirectories,
        documentViews
      });
    }, 180);
    return () => window.clearTimeout(timer);
  }, [activePath, bottomPanelOpen, documentViews, documents, expandedDirectories, host, loaded]);

  useEffect(() => host.files.watch((change) => {
    setTreeRevision((value) => value + 1);
    void host.files.list("").then((rootEntries) => setLoaded((current) => current ? { ...current, rootEntries } : current));
    if (change.source === "ide") return;
    const current = documentsRef.current.find((document) => document.relativePath === change.relativePath);
    if (change.kind === "deleted") {
      if (current?.dirty) setError(`${change.relativePath} was removed externally; its unsaved buffer remains open.`);
      else if (current) closeDocument(change.relativePath, false);
      return;
    }
    if (!current) return;
    void host.files.read(change.relativePath).then((snapshot) => {
      if (current.dirty && snapshot.digest !== current.digest) {
        setConflict({ relativePath: current.relativePath, disk: snapshot });
      } else {
        setDocuments((items) => items.map((item) =>
          item.relativePath === snapshot.relativePath ? replaceCleanDocument(item, snapshot) : item
        ));
      }
    }).catch(() => undefined);
  }), [host]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => host.python.subscribe((event) => {
    if (event.kind === "started") {
      setRunId(event.runId);
      setRunning(true);
    } else if (event.kind === "output" && event.text) {
      setOutput((value) => value + event.text);
    } else if (event.kind === "exited" || event.kind === "failed") {
      if (event.text) setOutput((value) => value + `${event.text}\n`);
      setRunId(null);
      setRunning(false);
      setExitCode(event.exitCode ?? -1);
      if (event.diagnostics) setDiagnostics(event.diagnostics);
    }
  }), [host]);

  const activeDocument = documents.find((document) => document.relativePath === activePath) ?? null;

  const openFile = useCallback(async (relativePath: string) => {
    setError(null);
    if (documentsRef.current.some((document) => document.relativePath === relativePath)) {
      setActivePath(relativePath);
      return;
    }
    try {
      const snapshot = await host.files.read(relativePath);
      setDocuments((items) => [...items, openDocument(snapshot)]);
      setActivePath(relativePath);
      if (snapshot.readonlyReason) setNotice(`${relativePath}: ${snapshot.readonlyReason}`);
    } catch (reason) {
      setError(message(reason, `Unable to open ${relativePath}`));
    }
  }, [host]);

  const savePath = useCallback(async (relativePath: string, expectedDigest?: string) => {
    const document = documentsRef.current.find((item) => item.relativePath === relativePath);
    if (!document || document.readonly || !document.dirty) return true;
    try {
      const snapshot = await host.files.write({
        relativePath,
        content: document.content,
        expectedDigest: expectedDigest ?? document.digest
      });
      setDocuments((items) => items.map((item) =>
        item.relativePath === relativePath ? markDocumentSaved(item, snapshot) : item
      ));
      setConflict(null);
      setNotice(`Saved ${relativePath}`);
      if (relativePath.endsWith(".py") && selectedInterpreterId) {
        setDiagnostics(await host.python.checkSyntax(relativePath, selectedInterpreterId));
      }
      return true;
    } catch (reason) {
      if (reason instanceof Error && reason.name === "FileChangedError") {
        setConflict({ relativePath, disk: await host.files.read(relativePath) });
        return false;
      }
      setError(message(reason, `Unable to save ${relativePath}`));
      return false;
    }
  }, [host, selectedInterpreterId]);

  const saveAll = useCallback(async () => {
    for (const document of documentsRef.current.filter((item) => item.dirty)) {
      if (!await savePath(document.relativePath)) return false;
    }
    return true;
  }, [savePath]);

  useEffect(() => {
    window.__codexInnerIdeRequestSaveAll = saveAll;
    return () => { delete window.__codexInnerIdeRequestSaveAll; };
  }, [saveAll]);

  useEffect(() => {
    const listener = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
        event.preventDefault();
        if (event.shiftKey) void saveAll();
        else if (activePath) void savePath(activePath);
      }
    };
    window.addEventListener("keydown", listener);
    return () => window.removeEventListener("keydown", listener);
  }, [activePath, saveAll, savePath]);

  const runActiveFile = async () => {
    if (!activeDocument?.relativePath.endsWith(".py") || !selectedInterpreterId) return;
    if (!await savePath(activeDocument.relativePath)) return;
    setRunning(true);
    setBottomPanelOpen(true);
    setOutput("");
    setDiagnostics([]);
    setExitCode(null);
    setError(null);
    try {
      const started = await host.python.run(activeDocument.relativePath, selectedInterpreterId);
      setRunId(started.runId);
    } catch (reason) {
      setRunning(false);
      setExitCode(-1);
      setOutput(`${message(reason, "Python execution failed")}\n`);
    }
  };

  const handoffSelection = async (
    destination: "codex" | "chatgpt",
    range: SelectionRange,
    selectedText: string
  ) => {
    if (!loaded || !activeDocument) return;
    if (selectedText.length > 40_000) {
      setError("Selection exceeds the 40,000-character handoff limit.");
      return;
    }
    const latest = documentsRef.current.find((document) => document.relativePath === activeDocument.relativePath) ?? activeDocument;
    const lines = latest.content.split("\n");
    const start = Math.max(0, range.startLine - 11);
    const end = Math.min(lines.length, range.endLine + 10);
    try {
      const context: IdeSelectionContext = {
        workspaceId: loaded.workspace.id,
        relativePath: latest.relativePath,
        language: latest.relativePath.endsWith(".py") ? "python" : "text",
        range,
        selectedText,
        surroundingText: lines.slice(start, end).join("\n"),
        dirty: latest.dirty
      };
      const result = destination === "codex"
        ? await host.codex.addToChat(context)
        : await host.chatgpt.moreDetails(context);
      if (result.mechanism === "clipboard") {
        setNotice(`${destination === "codex" ? "Codex" : "ChatGPT"} handoff was unavailable. Context copied to the clipboard.`);
      } else if (destination === "codex") {
        setNotice("Selection added to the Codex composer. Nothing was sent.");
      } else {
        setNotice("Selection added to ChatGPT Quick Chat. Nothing was sent.");
      }
    } catch (reason) {
      setError(message(reason, "Unable to hand off the selection"));
    }
  };

  const closeDocument = (path: string, confirmDirty = true) => {
    const current = documentsRef.current;
    const document = current.find((item) => item.relativePath === path);
    if (confirmDirty && document?.dirty && !window.confirm(`Discard unsaved changes in ${path}?`)) return;
    const next = current.filter((item) => item.relativePath !== path);
    setDocuments(next);
    if (activePath === path) setActivePath(next.at(-1)?.relativePath ?? null);
  };

  const refreshTree = () => {
    setTreeRevision((value) => value + 1);
    void host.files.list("").then((rootEntries) => setLoaded((current) => current ? { ...current, rootEntries } : current));
  };

  if (!loaded) return <main className="loading-state">{error ?? "Opening workspace…"}</main>;

  return (
    <main className="ide-shell">
      <header className="titlebar">
        <div className="titlebar-project">
          <Code2 size={17} strokeWidth={1.6} aria-hidden="true" />
          <span>{loaded.workspace.name}</span>
          <span className="root-label">{loaded.workspace.rootLabel}</span>
        </div>
        <div className="titlebar-actions">
          {loaded.interpreters.length > 0 ? (
            <select aria-label="Python interpreter" value={selectedInterpreterId} onChange={(event) => setSelectedInterpreterId(event.target.value)}>
              {loaded.interpreters.map((interpreter) => (
                <option key={interpreter.id} value={interpreter.id}>{interpreter.version} · {interpreter.executable}</option>
              ))}
            </select>
          ) : (
            <button type="button" onClick={() => void host.python.createVenv().then((interpreter) => {
              setLoaded((current) => current ? { ...current, interpreters: [interpreter] } : current);
              setSelectedInterpreterId(interpreter.id);
            }).catch((reason) => setError(message(reason, "Unable to create .venv")))}>Create .venv</button>
          )}
          <button type="button" onClick={() => activePath && void savePath(activePath)} disabled={!activeDocument?.dirty}>
            <Save size={15} strokeWidth={1.7} aria-hidden="true" /> Save
          </button>
          <button className="run-button" type="button" onClick={() => void runActiveFile()} disabled={running || !activeDocument?.relativePath.endsWith(".py") || !selectedInterpreterId}>
            <Play size={15} strokeWidth={1.8} fill="currentColor" aria-hidden="true" />
            {running ? "Running…" : "Run Python"}
          </button>
          <button type="button" aria-label="Close IDE" onClick={() => void host.window.closeIde()}><X size={15} /></button>
        </div>
      </header>

      {(error || notice || conflict) && (
        <div className={`notice-bar${error || conflict ? " notice-error" : ""}`} role="status">
          {conflict ? (
            <>
              <TriangleAlert size={15} aria-hidden="true" />
              <span>{conflict.relativePath} changed on disk.</span>
              <button type="button" onClick={() => {
                setDocuments((items) => items.map((item) => item.relativePath === conflict.relativePath ? openDocument(conflict.disk) : item));
                setConflict(null);
              }}><RotateCcw size={13} /> Reload</button>
              <button type="button" onClick={() => void savePath(conflict.relativePath, conflict.disk.digest)}>Keep Editor Version</button>
              <button type="button" onClick={() => setConflict(null)}>Cancel</button>
            </>
          ) : <>
            <span>{error ?? notice}</span>
            <button type="button" onClick={() => { setError(null); setNotice(null); }}>Dismiss</button>
          </>}
        </div>
      )}

      <div className="workspace-grid">
        <FileTree
          rootEntries={loaded.rootEntries}
          activePath={activePath}
          initialExpanded={loaded.savedExpanded}
          revision={treeRevision}
          onExpandedChange={setExpandedDirectories}
          onLoadDirectory={(path) => host.files.list(path)}
          onOpenFile={(path) => void openFile(path)}
          onCreate={async (path, kind: FileKind) => { await host.files.create({ relativePath: path, kind }); refreshTree(); if (kind === "file") await openFile(path); }}
          onRename={async (from, to) => {
            await host.files.rename({ from, to });
            setDocuments((items) => items.map((document) => document.relativePath === from || document.relativePath.startsWith(`${from}/`)
              ? { ...document, relativePath: to + document.relativePath.slice(from.length) }
              : document));
            if (activePath === from || activePath?.startsWith(`${from}/`)) setActivePath(to + activePath.slice(from.length));
            refreshTree();
          }}
          onTrash={async (path) => {
            if (documentsRef.current.some((document) => (document.relativePath === path || document.relativePath.startsWith(`${path}/`)) && document.dirty)) {
              throw new Error("Save or discard open changes before moving this item to Trash.");
            }
            await host.files.trash(path);
            setDocuments((items) => items.filter((document) => document.relativePath !== path && !document.relativePath.startsWith(`${path}/`)));
            refreshTree();
          }}
          onError={(reason) => setError(message(reason, "File operation failed"))}
        />
        <div className="editor-stack">
          <EditorPane
            documents={documents}
            activePath={activePath}
            onActivate={setActivePath}
            onClose={(path) => closeDocument(path)}
            onChange={(content) => activePath && setDocuments((items) => items.map((item) => item.relativePath === activePath ? editDocument(item, content) : item))}
            documentViews={documentViews}
            onViewStateChange={(path, state) => setDocumentViews((views) => ({ ...views, [path]: state }))}
            revealDiagnostic={revealDiagnostic}
            onAddToChat={(range, text) => void handoffSelection("codex", range, text)}
            onMoreDetails={(range, text) => void handoffSelection("chatgpt", range, text)}
          />
          <OutputPanel
            open={bottomPanelOpen}
            running={running}
            exitCode={exitCode}
            output={output}
            diagnostics={diagnostics}
            onToggle={() => setBottomPanelOpen((open) => !open)}
            onStop={() => runId && void host.python.terminate(runId)}
            onOpenDiagnostic={(diagnostic) => {
              void openFile(diagnostic.relativePath).then(() => setRevealDiagnostic({ ...diagnostic }));
            }}
          />
        </div>
      </div>
    </main>
  );
}

function message(reason: unknown, fallback: string) {
  return reason instanceof Error ? reason.message : fallback;
}

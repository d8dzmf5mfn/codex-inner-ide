import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Code2 } from "lucide-react";
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
import { EditRequestBar, IdeTitleBar, StatusNotice } from "./components/IdeChrome";
import { OutputPanel } from "./components/OutputPanel";
import { PreviewPane } from "./components/PreviewPane";
import { CompletionSnippetDialog } from "./components/CompletionSnippetDialog";
import { digestText } from "./core/edits";
import {
  completionIndex,
  indexWorkspace,
  setUserCompletionSnippets,
  updateCompletionIndexFromChange
} from "./core/completions";
import {
  languageForPath,
  preferredInitialFilePath,
  runtimeActionForPath,
  selectionLanguageForPath,
  supportsCodexEdit
} from "./core/languages";
import { useRuntimeExecution } from "./hooks/useRuntimeExecution";
import { useTheme } from "./hooks/useTheme";
import type {
  ActivePythonEditContext,
  CodexInnerIdeHostV1,
  Diagnostic,
  DocumentViewState,
  FileEntry,
  FileKind,
  FileSnapshot,
  GlobalPreferences,
  IdeSelectionContext,
  PythonEditProposal,
  PythonEditScope,
  PreviewDescriptor,
  RecentWorkspace,
  RuntimeDescriptor,
  SelectionRange,
  ThemeMode,
  WorkspaceBinding
} from "./types/inner-host";

type Conflict = { relativePath: string; disk: FileSnapshot };
type ActiveSelection = { relativePath: string; range: SelectionRange; selectedText: string };
type EditComposer = { scope: PythonEditScope; instruction: string };
type LoadedIde = {
  workspace: WorkspaceBinding;
  rootEntries: FileEntry[];
  savedExpanded: string[];
  savedViews: Record<string, DocumentViewState>;
};
type WorkspaceSession = {
  loaded: LoadedIde;
  documents: OpenDocument[];
  activePath: string | null;
  bottomPanelOpen: boolean;
  expandedDirectories: string[];
  documentViews: Record<string, DocumentViewState>;
  pinned: boolean;
  sidebarCollapsed: boolean;
};

export function App() {
  const host = useMemo(resolveInnerHost, []);
  return host ? <InnerIde host={host} /> : <MissingHost />;
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

function InnerIde({ host }: { host: CodexInnerIdeHostV1 }) {
  const [loaded, setLoaded] = useState<LoadedIde | null>(null);
  const [recentWorkspaces, setRecentWorkspaces] = useState<RecentWorkspace[]>([]);
  const [workspaceSwitching, setWorkspaceSwitching] = useState(false);
  const [documents, setDocuments] = useState<OpenDocument[]>([]);
  const [activePath, setActivePath] = useState<string | null>(null);
  const [runtimes, setRuntimes] = useState<Record<string, RuntimeDescriptor[]>>({});
  const [selectedRuntimeIds, setSelectedRuntimeIds] = useState<Record<string, string>>({});
  const [preview, setPreview] = useState<PreviewDescriptor | null>(null);
  const [bottomPanelOpen, setBottomPanelOpen] = useState(true);
  const [expandedDirectories, setExpandedDirectories] = useState<string[]>([]);
  const [documentViews, setDocumentViews] = useState<Record<string, DocumentViewState>>({});
  const [treeRevision, setTreeRevision] = useState(0);
  const [revealDiagnostic, setRevealDiagnostic] = useState<Diagnostic | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [conflict, setConflict] = useState<Conflict | null>(null);
  const [activeSelection, setActiveSelection] = useState<ActiveSelection | null>(null);
  const [editComposer, setEditComposer] = useState<EditComposer | null>(null);
  const [lastEditRequest, setLastEditRequest] = useState<EditComposer>({ scope: "file", instruction: "" });
  const [proposal, setProposal] = useState<PythonEditProposal | null>(null);
  const [proposalMessage, setProposalMessage] = useState<string | null>(null);
  const [pinned, setPinned] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [globalPreferences, setGlobalPreferences] = useState<GlobalPreferences>({
    themeMode: "auto",
    completionSnippets: []
  });
  const [snippetsOpen, setSnippetsOpen] = useState(false);
  const documentsRef = useRef(documents);
  const theme = useTheme(globalPreferences.themeMode);
  const {
    running,
    exitCode,
    output,
    diagnostics,
    execute,
    stop,
    check,
    reset: resetRuntime
  } = useRuntimeExecution(host);

  const applyWorkspaceSession = useCallback((session: WorkspaceSession) => {
    setLoaded(session.loaded);
    setDocuments(session.documents);
    setActivePath(session.activePath);
    setBottomPanelOpen(session.bottomPanelOpen);
    setExpandedDirectories(session.expandedDirectories);
    setDocumentViews(session.documentViews);
    setPinned(session.pinned);
    setSidebarCollapsed(session.sidebarCollapsed);
    setRuntimes({});
    setSelectedRuntimeIds({});
    setPreview(null);
    setRevealDiagnostic(null);
    setConflict(null);
    setActiveSelection(null);
    setEditComposer(null);
    setProposal(null);
    setProposalMessage(null);
    resetRuntime();
    host.window.setPinned(session.pinned);
  }, [host, resetRuntime]);

  const refreshRecentWorkspaces = useCallback(async () => {
    try {
      setRecentWorkspaces(await host.workspace.recent());
    } catch (reason) {
      setNotice(message(reason, "Unable to load recent workspaces"));
    }
  }, [host]);

  useEffect(() => {
    documentsRef.current = documents;
    host.window.setDirty(documents.some((document) => document.dirty));
  }, [documents, host]);

  useEffect(() => {
    let cancelled = false;
    void loadWorkspaceSession(host).then((session) => {
      if (cancelled) return;
      applyWorkspaceSession(session);
    }).catch((reason: unknown) => {
      if (!cancelled) setError(message(reason, "Unable to initialize the IDE"));
    });
    void refreshRecentWorkspaces();
    return () => { cancelled = true; };
  }, [applyWorkspaceSession, host, refreshRecentWorkspaces]);

  useEffect(() => {
    let cancelled = false;
    void host.preferences.load().then((preferences) => {
      if (cancelled) return;
      setGlobalPreferences(preferences);
      setUserCompletionSnippets(preferences.completionSnippets);
    }).catch((reason: unknown) => {
      if (!cancelled) setNotice(message(reason, "Unable to load completion snippets"));
    });
    return () => { cancelled = true; };
  }, [host]);

  const updateThemeMode = useCallback(async (themeMode: ThemeMode) => {
    try {
      const saved = await host.preferences.save({ ...globalPreferences, themeMode });
      setGlobalPreferences(saved);
    } catch (reason) {
      setError(message(reason, "Unable to save the theme preference"));
    }
  }, [globalPreferences, host]);

  useEffect(() => {
    if (!loaded) return;
    void indexWorkspace(host, loaded.workspace.id).catch((reason: unknown) => {
      setNotice(message(reason, "Workspace completion indexing is unavailable"));
    });
  }, [host, loaded?.workspace.id]);

  const persistCurrentWorkspaceState = useCallback(async () => {
    if (!loaded) return;
    await host.window.saveState({
      openPaths: documents.map((document) => document.relativePath),
      activePath,
      bottomPanelOpen,
      expandedDirectories,
      documentViews,
      pinned,
      sidebarCollapsed
    });
  }, [activePath, bottomPanelOpen, documentViews, documents, expandedDirectories, host, loaded, pinned, sidebarCollapsed]);

  useEffect(() => {
    if (!loaded) return;
    const timer = window.setTimeout(() => {
      void persistCurrentWorkspaceState();
    }, 180);
    return () => window.clearTimeout(timer);
  }, [loaded, persistCurrentWorkspaceState]);

  const switchWorkspace = useCallback(async (operation: () => Promise<WorkspaceBinding>) => {
    if (!loaded || workspaceSwitching) return;
    setWorkspaceSwitching(true);
    setError(null);
    try {
      await persistCurrentWorkspaceState();
      const next = await operation();
      if (next.id !== loaded.workspace.id) {
        applyWorkspaceSession(await loadWorkspaceSession(host, next));
        setNotice(`Opened workspace ${next.name}`);
      }
      await refreshRecentWorkspaces();
    } catch (reason) {
      setError(message(reason, "Unable to switch workspace"));
    } finally {
      setWorkspaceSwitching(false);
    }
  }, [applyWorkspaceSession, host, loaded, persistCurrentWorkspaceState, refreshRecentWorkspaces, workspaceSwitching]);

  const removeRecentWorkspace = useCallback(async (id: string) => {
    try {
      await host.workspace.removeRecent(id);
      await refreshRecentWorkspaces();
    } catch (reason) {
      setError(message(reason, "Unable to remove recent workspace"));
    }
  }, [host, refreshRecentWorkspaces]);

  useEffect(() => host.files.watch((change) => {
    void updateCompletionIndexFromChange(host, change);
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

  useEffect(() => host.edits.subscribe((event) => {
    const { proposal: next, message: nextMessage } = event;
    if (next.state === "accepted" || next.state === "rejected") {
      setProposal((current) => current?.proposalId === next.proposalId ? null : current);
      setProposalMessage(null);
      return;
    }
    if (next.state === "failed") {
      setProposal((current) => current?.proposalId === next.proposalId ? null : current);
      setProposalMessage(null);
      setError(nextMessage ?? "Codex did not return a valid edit proposal.");
      return;
    }
    setProposal(next);
    setProposalMessage(nextMessage ?? null);
    if (next.state === "ready") setEditComposer(null);
  }), [host]);

  const activeDocument = documents.find((document) => document.relativePath === activePath) ?? null;
  const activeLanguage = languageForPath(activeDocument?.relativePath ?? "");
  const activeRuntimes = runtimes[activeLanguage.id] ?? [];
  const selectedRuntimeId = selectedRuntimeIds[activeLanguage.id]
    ?? activeRuntimes.find((runtime) => runtime.available)?.id
    ?? activeRuntimes[0]?.id
    ?? "";

  useEffect(() => {
    if (!activeDocument || runtimeActionForPath(activeDocument.relativePath) === null) return;
    let cancelled = false;
    void host.runtime.discover(activeLanguage.id).then((values) => {
      if (cancelled) return;
      setRuntimes((current) => ({ ...current, [activeLanguage.id]: values }));
      setSelectedRuntimeIds((current) => ({
        ...current,
        [activeLanguage.id]: values.some((value) => value.id === current[activeLanguage.id])
          ? current[activeLanguage.id]
          : values.find((value) => value.available)?.id ?? values[0]?.id ?? ""
      }));
    }).catch((reason: unknown) => {
      if (!cancelled) setNotice(message(reason, `${activeLanguage.label} runtime discovery is unavailable`));
    });
    return () => { cancelled = true; };
  }, [activeDocument?.relativePath, activeLanguage.id, activeLanguage.label, host, loaded?.workspace.id]);

  useEffect(() => {
    setActiveSelection((current) => current?.relativePath === activePath ? current : null);
  }, [activePath]);

  useEffect(() => {
    window.__codexInnerIdeGetActiveEditContext = async (instruction, requestedScope) => {
      if (!loaded || !activePath) return null;
      const document = documentsRef.current.find((item) => item.relativePath === activePath);
      if (!document || document.readonly || !supportsCodexEdit(document.relativePath)) return null;
      const selection = activeSelection?.relativePath === activePath ? activeSelection : null;
      const scope: PythonEditScope = requestedScope === "auto"
        ? selection ? "selection" : "file"
        : requestedScope;
      if (scope === "selection" && !selection) return null;
      const context: ActivePythonEditContext = {
        workspaceId: loaded.workspace.id,
        relativePath: document.relativePath,
        scope,
        range: scope === "selection" ? selection?.range ?? null : null,
        bufferContent: document.content,
        bufferDigest: await digestText(document.content),
        instruction,
        readonly: document.readonly
      };
      return context;
    };
    return () => { delete window.__codexInnerIdeGetActiveEditContext; };
  }, [activePath, activeSelection, loaded]);

  useEffect(() => {
    if (host.hostMode !== "browser") return;
    const timer = window.setTimeout(() => {
      const getter = window.__codexInnerIdeGetActiveEditContext;
      if (typeof getter !== "function") return;
      void getter("status", "auto")
        .then((context) => host.window.updateActiveContext(context))
        .catch(() => undefined);
    }, 180);
    return () => window.clearTimeout(timer);
  }, [activePath, activeSelection, documents, host]);

  useEffect(() => {
    if (!proposal || (proposal.state !== "generating" && proposal.state !== "ready")) return;
    const document = documents.find((item) => item.relativePath === proposal.relativePath);
    if (!document) {
      setProposal((current) => current?.proposalId === proposal.proposalId
        ? { ...current, state: "stale" }
        : current);
      void host.edits.decide(proposal.proposalId, "stale").catch(() => undefined);
      return;
    }
    let cancelled = false;
    void digestText(document.content).then((digest) => {
      if (cancelled || digest === proposal.baseBufferDigest) return;
      setProposal((current) => current?.proposalId === proposal.proposalId
        ? { ...current, state: "stale" }
        : current);
      void host.edits.decide(proposal.proposalId, "stale").catch(() => undefined);
    });
    return () => { cancelled = true; };
  }, [documents, host, proposal]);

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
      completionIndex.updateFile(snapshot);
      setConflict(null);
      setNotice(`Saved ${relativePath}`);
      const language = languageForPath(relativePath);
      const action = runtimeActionForPath(relativePath);
      const runtimeId = selectedRuntimeIds[language.id];
      if (runtimeId && action !== null && action !== "preview") {
        try {
          await check({ relativePath, languageId: language.id, runtimeId });
        } catch (reason) {
          setNotice(message(reason, `Saved ${relativePath}; validation is unavailable`));
        }
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
  }, [check, host, selectedRuntimeIds]);

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
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "b") {
        event.preventDefault();
        setSidebarCollapsed((value) => !value);
      } else if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
        event.preventDefault();
        if (event.shiftKey) void saveAll();
        else if (activePath) void savePath(activePath);
      }
    };
    window.addEventListener("keydown", listener);
    return () => window.removeEventListener("keydown", listener);
  }, [activePath, saveAll, savePath]);

  const runActiveFile = async () => {
    if (running) {
      stop();
      return;
    }
    if (!activeDocument) return;
    const language = languageForPath(activeDocument.relativePath);
    const action = runtimeActionForPath(activeDocument.relativePath);
    if (!action) return;
    if (!await savePath(activeDocument.relativePath)) return;
    setError(null);
    if (action === "preview") {
      try {
        const value = await host.preview.open({
          relativePath: activeDocument.relativePath,
          languageId: language.id,
          runtimeId: selectedRuntimeId || null,
          htmlEntryRelativePath: preview?.entryRelativePath ?? null
        });
        setPreview(value);
      } catch (reason) {
        setError(message(reason, `Unable to preview ${activeDocument.relativePath}`));
      }
      return;
    }
    setBottomPanelOpen(true);
    await execute({
      relativePath: activeDocument.relativePath,
      languageId: language.id,
      runtimeId: selectedRuntimeId || null
    });
  };

  const handoffSelection = async (range: SelectionRange, selectedText: string) => {
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
        language: selectionLanguageForPath(latest.relativePath),
        range,
        selectedText,
        surroundingText: lines.slice(start, end).join("\n"),
        dirty: latest.dirty
      };
      const result = await host.chatgpt.moreDetails(context);
      if (result.mechanism === "clipboard") {
        setNotice("Quick Chat handoff was unavailable. Context copied to the clipboard.");
      } else {
        setNotice("Selection added to ChatGPT Quick Chat. Nothing was sent.");
      }
    } catch (reason) {
      setError(message(reason, "Unable to hand off the selection"));
    }
  };

  const openEditComposer = (
    scope: "selection" | "file",
    selection?: { range: SelectionRange; selectedText: string }
  ) => {
    if (!activeDocument || !supportsCodexEdit(activeDocument.relativePath) || activeDocument.readonly) {
      setError("Open an editable Python file before requesting a Codex proposal.");
      return;
    }
    if (proposal?.state === "generating" || proposal?.state === "ready") {
      setError("Accept, reject, or cancel the current Codex proposal first.");
      return;
    }
    if (selection) {
      setActiveSelection({ relativePath: activeDocument.relativePath, ...selection });
    }
    setEditComposer({ scope, instruction: lastEditRequest.instruction });
  };

  const submitEditRequest = async () => {
    if (!editComposer) return;
    const instruction = editComposer.instruction.trim();
    if (!instruction) {
      setError("Describe the Python change you want Codex to propose.");
      return;
    }
    setError(null);
    setNotice(null);
    setLastEditRequest({ ...editComposer, instruction });
    try {
      await host.edits.request({ instruction, scope: editComposer.scope });
      setEditComposer(null);
    } catch (reason) {
      setError(message(reason, "Unable to start the Codex edit proposal"));
    }
  };

  const applyProposalToBuffer = (proposalId: string, content: string) => {
    if (!proposal || proposal.proposalId !== proposalId) return;
    setProposal({ ...proposal, state: "accepted" });
    setDocuments((items) => items.map((item) =>
      item.relativePath === proposal.relativePath ? editDocument(item, content) : item
    ));
    setNotice("Codex proposal applied to the editor buffer. Press ⌘S to save it to disk.");
    void host.edits.decide(proposalId, "accepted").catch((reason) => {
      setError(message(reason, "Unable to record the proposal decision"));
    });
  };

  const rejectProposal = (proposalId: string) => {
    setProposal((current) => current?.proposalId === proposalId ? null : current);
    setProposalMessage(null);
    void host.edits.decide(proposalId, "rejected").catch((reason) => {
      setError(message(reason, "Unable to reject the proposal"));
    });
  };

  const cancelProposal = (proposalId: string) => {
    void host.edits.cancel(proposalId).then(() => {
      setProposal((current) => current?.proposalId === proposalId ? null : current);
      setProposalMessage(null);
    }).catch((reason) => setError(message(reason, "Unable to cancel the proposal")));
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
      <IdeTitleBar
        workspace={loaded.workspace}
        themeMode={globalPreferences.themeMode}
        runtimes={activeRuntimes}
        selectedRuntimeId={selectedRuntimeId}
        activeDocument={activeDocument}
        running={running}
        pinned={pinned}
        sidebarCollapsed={sidebarCollapsed}
        hostMode={host.hostMode}
        onSelectRuntime={(id) => setSelectedRuntimeIds((current) => ({
          ...current,
          [activeLanguage.id]: id
        }))}
        onRecheckRuntime={() => {
          void host.runtime.discover(activeLanguage.id).then((values) => {
            setRuntimes((current) => ({ ...current, [activeLanguage.id]: values }));
            setSelectedRuntimeIds((current) => ({
              ...current,
              [activeLanguage.id]: values.find((value) => value.available)?.id
                ?? values[0]?.id
                ?? ""
            }));
            if (values.some((value) => value.available)) {
              setNotice(`${activeLanguage.label} runtime is ready.`);
            }
          }).catch((reason) => setError(message(reason, "Unable to recheck the runtime")));
        }}
        onCopySetupCommand={(command) => {
          void host.runtime.copySetupCommand(command)
            .then(() => setNotice("Setup command copied. It was not executed."))
            .catch((reason) => setError(message(reason, "Unable to copy the setup command")));
        }}
        onOpenSetupDownload={(url) => {
          void host.runtime.openSetupDownload(url)
            .catch((reason) => setError(message(reason, "Unable to open the official download page")));
        }}
        onCreateVenv={() => void host.python.createVenv().then((interpreter) => {
          const runtime: RuntimeDescriptor = {
            id: interpreter.id,
            languageId: "python",
            label: interpreter.version,
            version: interpreter.version,
            executable: interpreter.executable,
            source: interpreter.source,
            action: "run",
            available: true,
            setupOptions: []
          };
          setRuntimes((current) => ({ ...current, python: [runtime] }));
          setSelectedRuntimeIds((current) => ({ ...current, python: runtime.id }));
        }).catch((reason) => setError(message(reason, "Unable to create .venv")))}
        onSave={() => { if (activePath) void savePath(activePath); }}
        onManageSnippets={() => setSnippetsOpen(true)}
        onThemeModeChange={(mode) => void updateThemeMode(mode)}
        onToggleSidebar={() => setSidebarCollapsed((value) => !value)}
        onEditCurrentFile={() => openEditComposer("file")}
        onRun={() => void runActiveFile()}
        onTogglePin={() => {
          const next = !pinned;
          setPinned(next);
          host.window.setPinned(next);
        }}
        onClose={() => void host.window.closeIde()}
      />

      {editComposer && (
        <EditRequestBar
          scope={editComposer.scope}
          instruction={editComposer.instruction}
          onInstructionChange={(instruction) => setEditComposer((current) => current ? { ...current, instruction } : current)}
          onSubmit={() => void submitEditRequest()}
          onCancel={() => setEditComposer(null)}
        />
      )}

      <StatusNotice
        error={error}
        notice={notice}
        conflict={conflict}
        onReloadConflict={() => {
          if (!conflict) return;
          setDocuments((items) => items.map((item) => item.relativePath === conflict.relativePath ? openDocument(conflict.disk) : item));
          setConflict(null);
        }}
        onKeepEditorVersion={() => { if (conflict) void savePath(conflict.relativePath, conflict.disk.digest); }}
        onCancelConflict={() => setConflict(null)}
        onDismiss={() => { setError(null); setNotice(null); }}
      />

      <div className={`workspace-grid${sidebarCollapsed ? " workspace-grid-sidebar-collapsed" : ""}`}>
        {!sidebarCollapsed && <FileTree
          key={loaded.workspace.id}
          workspace={loaded.workspace}
          recentWorkspaces={recentWorkspaces}
          workspaceSwitching={workspaceSwitching}
          rootEntries={loaded.rootEntries}
          activePath={activePath}
          initialExpanded={expandedDirectories}
          revision={treeRevision}
          onExpandedChange={setExpandedDirectories}
          onLoadDirectory={(path) => host.files.list(path)}
          onOpenFile={(path) => void openFile(path)}
          onCreate={async (path, kind: FileKind) => { await host.files.create({ relativePath: path, kind }); refreshTree(); if (kind === "file") await openFile(path); }}
          onRename={async (from, to) => {
            await host.files.rename({ from, to });
            completionIndex.renamePath(from, to);
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
            completionIndex.removePath(path);
            setDocuments((items) => items.filter((document) => document.relativePath !== path && !document.relativePath.startsWith(`${path}/`)));
            refreshTree();
          }}
          onChooseWorkspace={() => switchWorkspace(() => host.workspace.choose())}
          onOpenRecentWorkspace={(id) => switchWorkspace(() => host.workspace.openRecent(id))}
          onRemoveRecentWorkspace={removeRecentWorkspace}
          onRelocateRecentWorkspace={(id) => switchWorkspace(() => host.workspace.relocateRecent(id))}
          onError={(reason) => setError(message(reason, "File operation failed"))}
        />}
        <div className="editor-stack">
          <div className="editor-main-row">
            <EditorPane
            documents={documents}
            activePath={activePath}
            onActivate={setActivePath}
            onClose={(path) => closeDocument(path)}
            onChange={(content) => activePath && setDocuments((items) => items.map((item) => item.relativePath === activePath ? editDocument(item, content) : item))}
            documentViews={documentViews}
            onViewStateChange={(path, state) => setDocumentViews((views) => ({ ...views, [path]: state }))}
            revealDiagnostic={revealDiagnostic}
            theme={theme}
            onMoreDetails={(range, text) => void handoffSelection(range, text)}
            onEditSelection={(range, text) => openEditComposer("selection", { range, selectedText: text })}
            onSelectionChange={(selection) => setActiveSelection(selection && activePath
              ? { relativePath: activePath, ...selection }
              : null)}
            proposal={proposal}
            proposalMessage={proposalMessage}
            onProposalApplied={applyProposalToBuffer}
            onProposalRejected={rejectProposal}
            onProposalStale={(proposalId) => {
              setProposal((current) => current?.proposalId === proposalId ? { ...current, state: "stale" } : current);
              void host.edits.decide(proposalId, "stale").catch(() => undefined);
            }}
            onProposalCancelled={cancelProposal}
            onRegenerate={() => {
              setProposal(null);
              setEditComposer(lastEditRequest);
            }}
            />
            {preview && (
              <PreviewPane
                preview={preview}
                onClose={() => setPreview(null)}
                onOpenExternal={() => void host.preview.openExternal({
                  relativePath: preview.relativePath,
                  languageId: preview.languageId,
                  htmlEntryRelativePath: preview.entryRelativePath ?? null
                }).catch((reason) => setError(message(reason, "Unable to open preview in the default browser")))}
              />
            )}
          </div>
          <OutputPanel
            languageLabel={activeLanguage.label}
            open={bottomPanelOpen}
            running={running}
            exitCode={exitCode}
            output={output}
            diagnostics={diagnostics}
            onToggle={() => setBottomPanelOpen((open) => !open)}
            onStop={stop}
            onOpenDiagnostic={(diagnostic) => {
              void openFile(diagnostic.relativePath).then(() => setRevealDiagnostic({ ...diagnostic }));
            }}
          />
        </div>
      </div>

      {snippetsOpen && (
        <CompletionSnippetDialog
          snippets={globalPreferences.completionSnippets}
          onClose={() => setSnippetsOpen(false)}
          onChange={async (completionSnippets) => {
            const saved = await host.preferences.save({ ...globalPreferences, completionSnippets });
            setGlobalPreferences(saved);
            setUserCompletionSnippets(saved.completionSnippets);
          }}
        />
      )}
    </main>
  );
}

function message(reason: unknown, fallback: string) {
  return reason instanceof Error ? reason.message : fallback;
}

async function loadWorkspaceSession(
  host: CodexInnerIdeHostV1,
  workspaceOverride?: WorkspaceBinding
): Promise<WorkspaceSession> {
  const workspace = workspaceOverride ?? await host.workspace.current();
  const [rootEntries, savedState] = await Promise.all([
    host.files.list(""),
    host.window.loadState()
  ]);
  const preferred = savedState?.openPaths ?? [];
  const fallback = preferredInitialFilePath(rootEntries);
  const paths = preferred.length > 0 ? preferred : fallback ? [fallback] : [];
  const results = await Promise.allSettled(paths.map((path) => host.files.read(path)));
  const documents = results
    .filter((result): result is PromiseFulfilledResult<FileSnapshot> => result.status === "fulfilled")
    .map((result) => openDocument(result.value));
  const openPaths = documents.map((document) => document.relativePath);
  const activePath = savedState?.activePath && openPaths.includes(savedState.activePath)
    ? savedState.activePath
    : openPaths[0] ?? null;
  return {
    loaded: {
      workspace,
      rootEntries,
      savedExpanded: savedState?.expandedDirectories ?? [],
      savedViews: savedState?.documentViews ?? {}
    },
    documents,
    activePath,
    bottomPanelOpen: savedState?.bottomPanelOpen ?? true,
    expandedDirectories: savedState?.expandedDirectories ?? [],
    documentViews: savedState?.documentViews ?? {},
    pinned: savedState?.pinned ?? false,
    sidebarCollapsed: savedState?.sidebarCollapsed ?? false
  };
}

import type { SelectionLanguageId } from "../core/languages";

export type FileKind = "file" | "directory";

export type FileEntry = {
  name: string;
  relativePath: string;
  kind: FileKind;
};

export type FileSnapshot = {
  relativePath: string;
  content: string;
  digest: string;
  readonly: boolean;
  readonlyReason?: string | null;
};

export type WriteFileRequest = {
  relativePath: string;
  content: string;
  expectedDigest: string;
};

export type WorkspaceBinding = {
  id: string;
  name: string;
  rootLabel: string;
};

export type PythonInterpreter = {
  id: string;
  executable: string;
  version: string;
  source: "task" | ".venv" | "venv" | "path";
};

export type RuntimeAction = "run" | "preview" | "validate" | "none";

export type RuntimeDescriptor = {
  id: string;
  languageId: string;
  label: string;
  version: string;
  executable?: string | null;
  source: "task" | ".venv" | "venv" | "project" | "path" | "builtin" | "missing" | string;
  action: RuntimeAction;
  available: boolean;
  unavailableReason?: string | null;
};

export type RuntimeExecuteRequest = {
  relativePath: string;
  languageId: string;
  runtimeId?: string | null;
};

export type RuntimeCheckRequest = RuntimeExecuteRequest;

export type Diagnostic = {
  relativePath: string;
  line: number;
  column: number;
  severity: "error" | "warning";
  message: string;
};

export type PythonExecutionEvent = {
  runId: string;
  kind: "started" | "output" | "exited" | "failed";
  stream?: "stdout" | "stderr" | null;
  text?: string | null;
  exitCode?: number | null;
  diagnostics?: Diagnostic[] | null;
};

export type RuntimeExecutionEvent = {
  runId: string;
  languageId: string;
  kind: "started" | "output" | "exited" | "failed";
  stream?: "stdout" | "stderr" | null;
  text?: string | null;
  exitCode?: number | null;
  diagnostics?: Diagnostic[] | null;
};

export type PreviewDescriptor = {
  relativePath: string;
  languageId: string;
  url?: string | null;
  content?: string | null;
  entryRelativePath?: string | null;
};

export type ThemeMode = "auto" | "light" | "dark";

export type UserCompletionSnippet = {
  id: string;
  languageId: import("../core/languages").LanguageId;
  triggerPrefix: string;
  displayName: string;
  description: string;
  body: string;
};

export type GlobalPreferences = {
  themeMode: ThemeMode;
  completionSnippets: UserCompletionSnippet[];
};

export type FileChange = {
  relativePath: string;
  kind: "changed" | "created" | "deleted";
  source?: "external" | "ide";
};

export type SelectionRange = {
  startLine: number;
  startColumn: number;
  endLine: number;
  endColumn: number;
};

export type PythonEditScope = "auto" | "selection" | "file";
export type PythonEditProposalState =
  | "generating"
  | "ready"
  | "stale"
  | "accepted"
  | "rejected"
  | "failed";

export type ActivePythonEditContext = {
  workspaceId: string;
  relativePath: string;
  scope: PythonEditScope;
  range?: SelectionRange | null;
  bufferContent: string;
  bufferDigest: string;
  instruction: string;
  readonly: boolean;
};

export type PythonEditProposal = {
  proposalId: string;
  workspaceId: string;
  relativePath: string;
  scope: Exclude<PythonEditScope, "auto">;
  range?: SelectionRange | null;
  baseBufferDigest: string;
  summary: string;
  replacementText: string;
  state: PythonEditProposalState;
};

export type PythonEditProposalEvent = {
  proposal: PythonEditProposal;
  message?: string | null;
};

export type IdeSelectionContext = {
  workspaceId: string;
  relativePath: string;
  language: SelectionLanguageId;
  range: SelectionRange;
  selectedText: string;
  surroundingText: string;
  dirty: boolean;
};

export type HandoffResult = {
  destination: "chatgpt";
  mechanism: "quickChatShortcut" | "compatibilitySignal" | "clipboard";
  submitted: false;
};

export type DocumentViewState = {
  cursorLine: number;
  cursorColumn: number;
  scrollTop: number;
  scrollLeft: number;
};

export type IdeWindowState = {
  openPaths: string[];
  activePath: string | null;
  bottomPanelOpen: boolean;
  expandedDirectories: string[];
  documentViews?: Record<string, DocumentViewState>;
  pinned?: boolean;
  sidebarCollapsed?: boolean;
};

export type RecentWorkspace = {
  id: string;
  name: string;
  rootLabel: string;
  available: boolean;
};

export type Unsubscribe = () => void;

export interface CodexInnerIdeHostV1 {
  readonly apiVersion: "1";
  readonly hostMode: "native" | "browser" | "mock";
  workspace: {
    current(): Promise<WorkspaceBinding>;
    choose(): Promise<WorkspaceBinding>;
    recent(): Promise<RecentWorkspace[]>;
    openRecent(id: string): Promise<WorkspaceBinding>;
    removeRecent(id: string): Promise<void>;
    relocateRecent(id: string): Promise<WorkspaceBinding>;
  };
  files: {
    list(relativePath?: string): Promise<FileEntry[]>;
    read(relativePath: string): Promise<FileSnapshot>;
    write(request: WriteFileRequest): Promise<FileSnapshot>;
    create(request: { relativePath: string; kind: FileKind }): Promise<FileEntry>;
    rename(request: { from: string; to: string }): Promise<FileEntry>;
    trash(relativePath: string): Promise<void>;
    watch(listener: (change: FileChange) => void): Unsubscribe;
  };
  python: {
    discover(): Promise<PythonInterpreter[]>;
    createVenv(): Promise<PythonInterpreter>;
    run(relativePath: string, interpreterId: string): Promise<{ runId: string }>;
    terminate(runId: string): Promise<void>;
    checkSyntax(relativePath: string, interpreterId: string): Promise<Diagnostic[]>;
    subscribe(listener: (event: PythonExecutionEvent) => void): Unsubscribe;
  };
  runtime: {
    discover(languageId: string): Promise<RuntimeDescriptor[]>;
    execute(request: RuntimeExecuteRequest): Promise<{ runId: string }>;
    check(request: RuntimeCheckRequest): Promise<Diagnostic[]>;
    terminate(runId: string): Promise<void>;
    subscribe(listener: (event: RuntimeExecutionEvent) => void): Unsubscribe;
  };
  preview: {
    open(request: RuntimeExecuteRequest & { htmlEntryRelativePath?: string | null }): Promise<PreviewDescriptor>;
    openExternal(request: RuntimeExecuteRequest & { htmlEntryRelativePath?: string | null }): Promise<PreviewDescriptor>;
  };
  preferences: {
    load(): Promise<GlobalPreferences>;
    save(preferences: GlobalPreferences): Promise<GlobalPreferences>;
  };
  chatgpt: {
    moreDetails(context: IdeSelectionContext): Promise<HandoffResult>;
  };
  edits: {
    request(request: {
      instruction: string;
      scope: PythonEditScope;
    }): Promise<{ proposalId: string; state: PythonEditProposalState }>;
    cancel(proposalId: string): Promise<{ cancelled: boolean }>;
    decide(proposalId: string, decision: "accepted" | "rejected" | "stale"): Promise<void>;
    subscribe(listener: (event: PythonEditProposalEvent) => void): Unsubscribe;
  };
  window: {
    setDirty(dirty: boolean): void;
    setPinned(pinned: boolean): void;
    updateActiveContext(context: ActivePythonEditContext | null, clientId?: string): void;
    loadState(): Promise<IdeWindowState | null>;
    saveState(state: IdeWindowState): Promise<void>;
    closeIde(): Promise<void>;
  };
}

declare global {
  interface Window {
    codexInnerIdeHost?: { v1?: CodexInnerIdeHostV1 };
    __codexInnerIdeReactRoot?: { unmount(): void };
    __codexInnerIdeRequestSaveAll?: () => Promise<boolean>;
    __codexInnerIdeGetActiveEditContext?: (
      instruction: string,
      scope: PythonEditScope
    ) => Promise<ActivePythonEditContext | null>;
  }
}

import { type FormEvent } from "react";
import {
  Braces,
  CircleCheck,
  Copy,
  Code2,
  ExternalLink,
  Eye,
  PanelLeftClose,
  PanelLeftOpen,
  Pin,
  PinOff,
  Play,
  RotateCcw,
  Save,
  Sparkles,
  Square,
  TriangleAlert,
  X
} from "lucide-react";
import type { FileSnapshot, PythonEditScope, RuntimeDescriptor, ThemeMode, WorkspaceBinding } from "../types/inner-host";
import type { OpenDocument } from "../core/documents";
import { languageForPath, runtimeActionForPath, supportsCodexEdit } from "../core/languages";

type IdeTitleBarProps = {
  workspace: WorkspaceBinding;
  themeMode: ThemeMode;
  runtimes: RuntimeDescriptor[];
  selectedRuntimeId: string;
  activeDocument: OpenDocument | null;
  running: boolean;
  pinned: boolean;
  sidebarCollapsed: boolean;
  hostMode: "native" | "browser" | "mock";
  onSelectRuntime: (id: string) => void;
  onRecheckRuntime: () => void;
  onCopySetupCommand: (command: string) => void;
  onOpenSetupDownload: (url: string) => void;
  onCreateVenv: () => void;
  onSave: () => void;
  onManageSnippets: () => void;
  onThemeModeChange: (mode: ThemeMode) => void;
  onToggleSidebar: () => void;
  onEditCurrentFile: () => void;
  onRun: () => void;
  onTogglePin: () => void;
  onClose: () => void;
};

export function IdeTitleBar({
  workspace,
  themeMode,
  runtimes,
  selectedRuntimeId,
  activeDocument,
  running,
  pinned,
  sidebarCollapsed,
  hostMode,
  onSelectRuntime,
  onRecheckRuntime,
  onCopySetupCommand,
  onOpenSetupDownload,
  onCreateVenv,
  onSave,
  onManageSnippets,
  onThemeModeChange,
  onToggleSidebar,
  onEditCurrentFile,
  onRun,
  onTogglePin,
  onClose
}: IdeTitleBarProps) {
  const activePath = activeDocument?.relativePath ?? "";
  const language = languageForPath(activePath);
  const runtimeAction = runtimeActionForPath(activePath);
  const selectedRuntime = runtimes.find((runtime) => runtime.id === selectedRuntimeId) ?? runtimes[0];
  const setupOptions = selectedRuntime?.setupOptions ?? [];
  const activeCodexEdit = supportsCodexEdit(activePath);
  const actionLabel = runtimeAction === "preview"
    ? `Preview ${language.label}`
    : runtimeAction === "validate" ? `Validate ${language.label}` : `Run ${language.label}`;
  const runLabel = running ? `Stop ${language.label}` : actionLabel;
  const RunIcon = running
    ? Square
    : runtimeAction === "preview" ? Eye : runtimeAction === "validate" ? CircleCheck : Play;
  return (
    <header className="titlebar">
      <div className="titlebar-project">
        <button
          className="titlebar-sidebar-toggle"
          type="button"
          aria-label={sidebarCollapsed ? "Show sidebar" : "Hide sidebar"}
          title={`${sidebarCollapsed ? "Show" : "Hide"} sidebar (⌘B)`}
          onClick={onToggleSidebar}
        >
          {sidebarCollapsed ? <PanelLeftOpen size={16} /> : <PanelLeftClose size={16} />}
        </button>
        <Code2 size={17} strokeWidth={1.6} aria-hidden="true" />
        <span>{workspace.name}</span>
        <span className="root-label">{workspace.rootLabel}</span>
      </div>
      <div className="titlebar-actions">
        <select
          className="theme-select"
          aria-label="Theme"
          value={themeMode}
          onChange={(event) => onThemeModeChange(event.target.value as ThemeMode)}
        >
          <option value="auto">Auto</option>
          <option value="light">Light</option>
          <option value="dark">Dark</option>
        </select>
        {runtimes.length > 0 ? (
          <select aria-label={`${language.label} runtime`} value={selectedRuntimeId || runtimes[0]?.id} onChange={(event) => onSelectRuntime(event.target.value)}>
            {runtimes.map((runtime) => (
              <option key={runtime.id} value={runtime.id} disabled={!runtime.available}>
                {runtime.label}{runtime.executable ? ` · ${runtime.executable}` : ""}
              </option>
            ))}
          </select>
        ) : language.id === "python" ? (
          <button type="button" onClick={onCreateVenv}>Create .venv</button>
        ) : <span className="runtime-unavailable">No runtime</span>}
        {selectedRuntime?.available === false && setupOptions.length > 0 && (
          <details className="runtime-setup">
            <summary>Setup</summary>
            <div className="runtime-setup-popover">
              <strong>{selectedRuntime.label}</strong>
              <p>{selectedRuntime.unavailableReason}</p>
              {setupOptions.map((option) => (
                <section key={option.id} className="runtime-setup-option">
                  <div>
                    <b>{option.label}</b>
                    <span>{option.scope === "workspace" ? "Workspace" : "System"}</span>
                  </div>
                  <p>{option.description}</p>
                  {option.command && (
                    <div className="runtime-setup-command">
                      <code>{option.command}</code>
                      <button type="button" onClick={() => onCopySetupCommand(option.command!)}>
                        <Copy size={13} aria-hidden="true" /> Copy
                      </button>
                    </div>
                  )}
                  {option.downloadURL && (
                    <button type="button" onClick={() => onOpenSetupDownload(option.downloadURL!)}>
                      <ExternalLink size={13} aria-hidden="true" /> Official download
                    </button>
                  )}
                </section>
              ))}
              <button type="button" className="runtime-recheck" onClick={onRecheckRuntime}>
                <RotateCcw size={13} aria-hidden="true" /> Recheck
              </button>
            </div>
          </details>
        )}
        <button type="button" onClick={onManageSnippets} title="Manage completion snippets">
          <Braces size={15} strokeWidth={1.7} aria-hidden="true" /> <span className="button-label">Snippets</span>
        </button>
        <button type="button" onClick={onSave} disabled={!activeDocument?.dirty}>
          <Save size={15} strokeWidth={1.7} aria-hidden="true" /> <span className="button-label">Save</span>
        </button>
        <button type="button" onClick={onEditCurrentFile} disabled={!activeCodexEdit || activeDocument?.readonly}>
          <Sparkles size={15} strokeWidth={1.7} aria-hidden="true" /> <span className="button-label">Edit current file</span>
        </button>
        <button
          className="run-button"
          type="button"
          aria-label={runLabel}
          title={selectedRuntime?.available === false ? selectedRuntime.unavailableReason ?? runLabel : runLabel}
          onClick={onRun}
          disabled={!running && (!activeDocument || runtimeAction === null || !selectedRuntime?.available)}
        >
          <RunIcon
            size={running ? 13 : 16}
            strokeWidth={1.8}
            fill={running || runtimeAction === "run" ? "currentColor" : "none"}
            aria-hidden="true"
          />
        </button>
        {hostMode !== "browser" && (
          <button
            type="button"
            className={pinned ? "pin-button pin-button-active" : "pin-button"}
            aria-label={pinned ? "Unpin IDE window" : "Pin IDE window on top"}
            aria-pressed={pinned}
            title={pinned ? "Unpin window" : "Keep window on top"}
            onClick={onTogglePin}
          >
            {pinned ? <PinOff size={15} aria-hidden="true" /> : <Pin size={15} aria-hidden="true" />}
          </button>
        )}
        <button type="button" aria-label="Close IDE" onClick={onClose}><X size={15} /></button>
      </div>
    </header>
  );
}

type EditRequestBarProps = {
  scope: PythonEditScope;
  instruction: string;
  onInstructionChange: (instruction: string) => void;
  onSubmit: () => void;
  onCancel: () => void;
};

export function EditRequestBar({
  scope,
  instruction,
  onInstructionChange,
  onSubmit,
  onCancel
}: EditRequestBarProps) {
  const submit = (event: FormEvent) => {
    event.preventDefault();
    onSubmit();
  };
  return (
    <form className="edit-request-bar" onSubmit={submit}>
      <Sparkles size={16} aria-hidden="true" />
      <label htmlFor="codex-edit-instruction">
        {scope === "selection" ? "Edit selected Python" : "Edit current Python file"}
      </label>
      <textarea
        id="codex-edit-instruction"
        autoFocus
        value={instruction}
        placeholder="Describe the change. Press ⌘Enter to generate a read-only proposal."
        onChange={(event) => onInstructionChange(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === "Enter" && event.metaKey) {
            event.preventDefault();
            onSubmit();
          }
          if (event.key === "Escape") onCancel();
        }}
      />
      <button type="submit">Generate proposal</button>
      <button type="button" onClick={onCancel}>Cancel</button>
    </form>
  );
}

type StatusNoticeProps = {
  error: string | null;
  notice: string | null;
  conflict: { relativePath: string; disk: FileSnapshot } | null;
  onReloadConflict: () => void;
  onKeepEditorVersion: () => void;
  onCancelConflict: () => void;
  onDismiss: () => void;
};

export function StatusNotice({
  error,
  notice,
  conflict,
  onReloadConflict,
  onKeepEditorVersion,
  onCancelConflict,
  onDismiss
}: StatusNoticeProps) {
  if (!error && !notice && !conflict) return null;
  return (
    <div className={`notice-bar${error || conflict ? " notice-error" : ""}`} role="status">
      {conflict ? (
        <>
          <TriangleAlert size={15} aria-hidden="true" />
          <span>{conflict.relativePath} changed on disk.</span>
          <button type="button" onClick={onReloadConflict}><RotateCcw size={13} /> Reload</button>
          <button type="button" onClick={onKeepEditorVersion}>Keep Editor Version</button>
          <button type="button" onClick={onCancelConflict}>Cancel</button>
        </>
      ) : (
        <>
          <span>{error ?? notice}</span>
          <button type="button" onClick={onDismiss}>Dismiss</button>
        </>
      )}
    </div>
  );
}

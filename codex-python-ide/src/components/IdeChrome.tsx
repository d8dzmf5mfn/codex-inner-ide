import { type FormEvent } from "react";
import {
  Code2,
  Moon,
  Pin,
  PinOff,
  Play,
  RotateCcw,
  Save,
  Sparkles,
  Sun,
  TriangleAlert,
  X
} from "lucide-react";
import type { FileSnapshot, PythonEditScope, PythonInterpreter, WorkspaceBinding } from "../types/inner-host";
import type { OpenDocument } from "../core/documents";
import { supportsCodexEdit, supportsPythonExecution } from "../core/languages";

type IdeTitleBarProps = {
  workspace: WorkspaceBinding;
  theme: "light" | "dark";
  interpreters: PythonInterpreter[];
  selectedInterpreterId: string;
  activeDocument: OpenDocument | null;
  running: boolean;
  pinned: boolean;
  onSelectInterpreter: (id: string) => void;
  onCreateVenv: () => void;
  onSave: () => void;
  onEditCurrentFile: () => void;
  onRun: () => void;
  onTogglePin: () => void;
  onClose: () => void;
};

export function IdeTitleBar({
  workspace,
  theme,
  interpreters,
  selectedInterpreterId,
  activeDocument,
  running,
  pinned,
  onSelectInterpreter,
  onCreateVenv,
  onSave,
  onEditCurrentFile,
  onRun,
  onTogglePin,
  onClose
}: IdeTitleBarProps) {
  const activePath = activeDocument?.relativePath ?? "";
  const activePython = supportsPythonExecution(activePath);
  const activeCodexEdit = supportsCodexEdit(activePath);
  return (
    <header className="titlebar">
      <div className="titlebar-project">
        <Code2 size={17} strokeWidth={1.6} aria-hidden="true" />
        <span>{workspace.name}</span>
        <span className="root-label">{workspace.rootLabel}</span>
      </div>
      <div className="titlebar-actions">
        <span className="time-theme-label" title="Theme follows local time: light 07:00–18:59, dark 19:00–06:59">
          {theme === "light" ? <Sun size={14} /> : <Moon size={14} />}
          Auto
        </span>
        {interpreters.length > 0 ? (
          <select aria-label="Python interpreter" value={selectedInterpreterId} onChange={(event) => onSelectInterpreter(event.target.value)}>
            {interpreters.map((interpreter) => (
              <option key={interpreter.id} value={interpreter.id}>{interpreter.version} · {interpreter.executable}</option>
            ))}
          </select>
        ) : (
          <button type="button" onClick={onCreateVenv}>Create .venv</button>
        )}
        <button type="button" onClick={onSave} disabled={!activeDocument?.dirty}>
          <Save size={15} strokeWidth={1.7} aria-hidden="true" /> Save
        </button>
        <button type="button" onClick={onEditCurrentFile} disabled={!activeCodexEdit || activeDocument?.readonly}>
          <Sparkles size={15} strokeWidth={1.7} aria-hidden="true" /> Edit current file
        </button>
        <button className="run-button" type="button" onClick={onRun} disabled={running || !activePython || !selectedInterpreterId}>
          <Play size={15} strokeWidth={1.8} fill="currentColor" aria-hidden="true" />
          {running ? "Running…" : "Run Python"}
        </button>
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

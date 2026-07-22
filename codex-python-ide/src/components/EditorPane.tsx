import { useEffect, useRef, useState } from "react";
import Editor, { type OnMount } from "@monaco-editor/react";
import { Check, LoaderCircle, RotateCcw, Sparkles, X } from "lucide-react";
import { digestText, previewLines } from "../core/edits";
import type {
  Diagnostic,
  DocumentViewState,
  PythonEditProposal,
  SelectionRange
} from "../types/inner-host";
import type { OpenDocument } from "../core/documents";

type SelectionMenu = {
  left: number;
  top: number;
  range: SelectionRange;
  selectedText: string;
};

type EditorPaneProps = {
  documents: OpenDocument[];
  activePath: string | null;
  onActivate: (relativePath: string) => void;
  onClose: (relativePath: string) => void;
  onChange: (content: string) => void;
  documentViews: Record<string, DocumentViewState>;
  onViewStateChange: (relativePath: string, state: DocumentViewState) => void;
  revealDiagnostic: Diagnostic | null;
  theme: "light" | "dark";
  onMoreDetails: (range: SelectionRange, selectedText: string) => void;
  onEditSelection: (range: SelectionRange, selectedText: string) => void;
  onSelectionChange: (selection: { range: SelectionRange; selectedText: string } | null) => void;
  proposal: PythonEditProposal | null;
  proposalMessage: string | null;
  onProposalApplied: (proposalId: string, content: string) => void;
  onProposalRejected: (proposalId: string) => void;
  onProposalStale: (proposalId: string) => void;
  onProposalCancelled: (proposalId: string) => void;
  onRegenerate: () => void;
};

export function EditorPane({
  documents,
  activePath,
  onActivate,
  onClose,
  onChange,
  documentViews,
  onViewStateChange,
  revealDiagnostic,
  theme,
  onMoreDetails,
  onEditSelection,
  onSelectionChange,
  proposal,
  proposalMessage,
  onProposalApplied,
  onProposalRejected,
  onProposalStale,
  onProposalCancelled,
  onRegenerate
}: EditorPaneProps) {
  const activeDocument = documents.find((document) => document.relativePath === activePath) ?? null;
  const activeProposal = proposal?.relativePath === activePath ? proposal : null;
  const [selectionMenu, setSelectionMenu] = useState<SelectionMenu | null>(null);
  const [mountRevision, setMountRevision] = useState(0);
  const editorElementRef = useRef<HTMLDivElement>(null);
  const editorRef = useRef<Parameters<OnMount>[0] | null>(null);
  const monacoRef = useRef<Parameters<OnMount>[1] | null>(null);
  const readyContextRef = useRef<ReturnType<Parameters<OnMount>[0]["createContextKey"]> | null>(null);
  const decorationRef = useRef<ReturnType<Parameters<OnMount>[0]["createDecorationsCollection"]> | null>(null);
  const viewZoneRef = useRef<string | null>(null);
  const proposalRef = useRef(activeProposal);
  const applyingRef = useRef(false);

  useEffect(() => { proposalRef.current = activeProposal; }, [activeProposal]);

  useEffect(() => {
    if (!revealDiagnostic || revealDiagnostic.relativePath !== activePath) return;
    editorRef.current?.revealLineInCenter(revealDiagnostic.line);
    editorRef.current?.setPosition({ lineNumber: revealDiagnostic.line, column: revealDiagnostic.column });
    editorRef.current?.focus();
  }, [activePath, revealDiagnostic]);

  useEffect(() => {
    const editor = editorRef.current;
    const monaco = monacoRef.current;
    decorationRef.current?.clear();
    if (editor && viewZoneRef.current) {
      const zone = viewZoneRef.current;
      editor.changeViewZones((accessor) => accessor.removeZone(zone));
      viewZoneRef.current = null;
    }
    readyContextRef.current?.set(activeProposal?.state === "ready");
    if (!editor || !monaco || !activeDocument || activeProposal?.state !== "ready") return;

    const preview = previewLines(activeDocument.content, activeProposal);
    const model = editor.getModel();
    if (!model) return;
    const startLine = Math.min(Math.max(1, preview.startLine), model.getLineCount());
    const endLine = Math.min(Math.max(startLine, preview.endLine), model.getLineCount());
    const deleteRange = activeProposal.scope === "selection" && activeProposal.range
      ? new monaco.Range(
        activeProposal.range.startLine,
        activeProposal.range.startColumn,
        activeProposal.range.endLine,
        activeProposal.range.endColumn
      )
      : new monaco.Range(startLine, 1, endLine, model.getLineMaxColumn(endLine));
    decorationRef.current = editor.createDecorationsCollection([{
      range: deleteRange,
      options: {
        className: "codex-edit-removed",
        isWholeLine: activeProposal.scope === "file",
        overviewRuler: { color: "#e58b8b", position: monaco.editor.OverviewRulerLane.Right }
      }
    }]);

    const node = document.createElement("div");
    node.className = "codex-edit-added-zone";
    const label = document.createElement("div");
    label.className = "codex-edit-added-label";
    label.textContent = "Codex proposal";
    const code = document.createElement("pre");
    code.textContent = preview.replacement || "(remove selected code)";
    node.append(label, code);
    editor.changeViewZones((accessor) => {
      viewZoneRef.current = accessor.addZone({
        afterLineNumber: Math.max(0, endLine),
        heightInLines: Math.min(12, Math.max(2, preview.replacement.split("\n").length + 1)),
        domNode: node
      });
    });
    return () => {
      decorationRef.current?.clear();
      if (viewZoneRef.current) {
        const zone = viewZoneRef.current;
        editor.changeViewZones((accessor) => accessor.removeZone(zone));
        viewZoneRef.current = null;
      }
    };
  }, [activeDocument, activeProposal, mountRevision]);

  const applyProposal = async () => {
    const editor = editorRef.current;
    const value = proposalRef.current;
    const model = editor?.getModel();
    if (!editor || !model || value?.state !== "ready") return;
    if (await digestText(model.getValue()) !== value.baseBufferDigest) {
      onProposalStale(value.proposalId);
      return;
    }
    const range = value.scope === "selection" && value.range
      ? {
        startLineNumber: value.range.startLine,
        startColumn: value.range.startColumn,
        endLineNumber: value.range.endLine,
        endColumn: value.range.endColumn
      }
      : model.getFullModelRange();
    applyingRef.current = true;
    editor.pushUndoStop();
    editor.executeEdits("codex-inner-edit", [{
      range,
      text: value.replacementText,
      forceMoveMarkers: true
    }]);
    editor.pushUndoStop();
    applyingRef.current = false;
    onProposalApplied(value.proposalId, model.getValue());
    editor.focus();
  };

  const handleMount: OnMount = (editor, monaco) => {
    editorRef.current = editor;
    monacoRef.current = monaco;
    readyContextRef.current = editor.createContextKey("codexInnerEditReady", false);
    setMountRevision((value) => value + 1);
    if (activeDocument) {
      const saved = documentViews[activeDocument.relativePath];
      if (saved) {
        editor.setPosition({ lineNumber: saved.cursorLine, column: saved.cursorColumn });
        editor.setScrollPosition({ scrollTop: saved.scrollTop, scrollLeft: saved.scrollLeft });
      }
      const saveView = () => {
        const position = editor.getPosition();
        if (!position) return;
        onViewStateChange(activeDocument.relativePath, {
          cursorLine: position.lineNumber,
          cursorColumn: position.column,
          scrollTop: editor.getScrollTop(),
          scrollLeft: editor.getScrollLeft()
        });
      };
      editor.onDidScrollChange(saveView);
      editor.onDidChangeCursorPosition(saveView);
    }
    editor.addAction({
      id: "codex-inner-edit.accept",
      label: "Accept Codex edit proposal",
      keybindings: [monaco.KeyCode.Enter],
      precondition: "codexInnerEditReady && editorTextFocus && !suggestWidgetVisible && !renameInputVisible && !inSnippetMode && !findInputFocus",
      run: () => applyProposal()
    });
    editor.addAction({
      id: "codex-inner-edit.reject",
      label: "Reject Codex edit proposal",
      keybindings: [monaco.KeyCode.Escape],
      precondition: "codexInnerEditReady && editorTextFocus && !suggestWidgetVisible && !renameInputVisible && !inSnippetMode && !findInputFocus",
      run: () => {
        const value = proposalRef.current;
        if (value?.state === "ready") onProposalRejected(value.proposalId);
      }
    });
    editor.focus();
    editor.onDidChangeCursorSelection(({ selection }) => {
      if (selection.isEmpty()) {
        setSelectionMenu(null);
        onSelectionChange(null);
        return;
      }

      const model = editor.getModel();
      const visiblePosition = editor.getScrolledVisiblePosition(selection.getEndPosition());
      if (!model || !visiblePosition || !editorElementRef.current) return;
      const container = editorElementRef.current.getBoundingClientRect();
      const left = Math.min(Math.max(16, visiblePosition.left + 54), Math.max(16, container.width - 330));
      const top = Math.min(visiblePosition.top + visiblePosition.height + 10, Math.max(16, container.height - 160));
      const next = {
        left,
        top,
        range: {
          startLine: selection.startLineNumber,
          startColumn: selection.startColumn,
          endLine: selection.endLineNumber,
          endColumn: selection.endColumn
        },
        selectedText: model.getValueInRange(selection)
      };
      setSelectionMenu(next);
      onSelectionChange({ range: next.range, selectedText: next.selectedText });
    });
  };

  const proposalBar = activeProposal && (
    <div className={`proposal-bar proposal-${activeProposal.state}`} role="status">
      {activeProposal.state === "generating" && <LoaderCircle className="proposal-spinner" size={15} />}
      {activeProposal.state === "ready" && <Sparkles size={15} />}
      {activeProposal.state === "stale" && <RotateCcw size={15} />}
      <span>
        {activeProposal.state === "ready"
          ? `${activeProposal.summary} · Enter accepts into the buffer; ⌘S saves to disk.`
          : activeProposal.state === "generating"
            ? activeProposal.summary
            : activeProposal.state === "stale"
              ? "The buffer changed. Regenerate this proposal before accepting it."
              : proposalMessage ?? activeProposal.summary}
      </span>
      {activeProposal.state === "generating" && (
        <button type="button" onClick={() => onProposalCancelled(activeProposal.proposalId)}>Cancel</button>
      )}
      {activeProposal.state === "ready" && (
        <>
          <button type="button" onClick={() => void applyProposal()}><Check size={13} /> Accept</button>
          <button type="button" onClick={() => onProposalRejected(activeProposal.proposalId)}>Reject</button>
        </>
      )}
      {activeProposal.state === "stale" && (
        <>
          <button type="button" onClick={onRegenerate}>Regenerate</button>
          <button type="button" onClick={() => onProposalRejected(activeProposal.proposalId)}>Reject</button>
        </>
      )}
    </div>
  );

  return (
    <section className={`editor-pane${proposalBar ? " editor-pane-with-proposal" : ""}`} aria-label="Code editor">
      <div className="editor-tabs" role="tablist" aria-label="Open files">
        {documents.map((document) => (
          <button
            className={`editor-tab${document.relativePath === activePath ? " editor-tab-active" : ""}`}
            key={document.relativePath}
            onClick={() => onActivate(document.relativePath)}
            type="button"
            role="tab"
            aria-selected={document.relativePath === activePath}
          >
            <span>{document.relativePath.split("/").at(-1)}</span>
            {document.dirty && <span className="dirty-dot" aria-label="Unsaved" />}
            <span
              className="tab-close"
              role="button"
              tabIndex={0}
              aria-label={`Close ${document.relativePath}`}
              onClick={(event) => {
                event.stopPropagation();
                onClose(document.relativePath);
              }}
              onKeyDown={(event) => {
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault();
                  event.stopPropagation();
                  onClose(document.relativePath);
                }
              }}
            >
              <X size={13} strokeWidth={1.7} aria-hidden="true" />
            </span>
          </button>
        ))}
      </div>

      {proposalBar}

      <div className="editor-canvas" ref={editorElementRef}>
        {activeDocument ? (
          <Editor
            key={activeDocument.relativePath}
            path={activeDocument.relativePath}
            language={activeDocument.relativePath.endsWith(".py") ? "python" : "plaintext"}
            value={activeDocument.content}
            onChange={(value) => {
              if (!applyingRef.current) onChange(value ?? "");
            }}
            onMount={handleMount}
            theme={theme === "dark" ? "vs-dark" : "vs"}
            options={{
              automaticLayout: true,
              minimap: { enabled: false },
              fontFamily: "SFMono-Regular, Menlo, Monaco, Consolas, monospace",
              fontSize: 13,
              lineHeight: 21,
              padding: { top: 14 },
              roundedSelection: false,
              scrollBeyondLastLine: false,
              renderLineHighlight: "gutter",
              overviewRulerBorder: false,
              wordWrap: "off",
              readOnly: activeDocument.readonly
            }}
          />
        ) : (
          <div className="empty-editor">Open a file to start coding.</div>
        )}

        {selectionMenu && activeDocument?.relativePath.endsWith(".py") && !activeDocument.readonly && (
          <div className="selection-actions" style={{ left: selectionMenu.left, top: selectionMenu.top }}>
            <button
              className="selection-trigger selection-edit-trigger"
              type="button"
              onClick={() => onEditSelection(selectionMenu.range, selectionMenu.selectedText)}
            >
              Edit with Codex
            </button>
            <button
              className="selection-trigger"
              type="button"
              onClick={() => onMoreDetails(selectionMenu.range, selectionMenu.selectedText)}
            >
              More details
            </button>
          </div>
        )}
      </div>
    </section>
  );
}

import { useEffect, useRef, useState } from "react";
import Editor, { type OnMount } from "@monaco-editor/react";
import { X } from "lucide-react";
import type { Diagnostic, DocumentViewState, SelectionRange } from "../types/inner-host";
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
  onAddToChat: (range: SelectionRange, selectedText: string) => void;
  onMoreDetails: (range: SelectionRange, selectedText: string) => void;
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
  onAddToChat,
  onMoreDetails
}: EditorPaneProps) {
  const activeDocument = documents.find((document) => document.relativePath === activePath) ?? null;
  const [selectionMenu, setSelectionMenu] = useState<SelectionMenu | null>(null);
  const editorElementRef = useRef<HTMLDivElement>(null);
  const editorRef = useRef<Parameters<OnMount>[0] | null>(null);

  useEffect(() => {
    if (!revealDiagnostic || revealDiagnostic.relativePath !== activePath) return;
    editorRef.current?.revealLineInCenter(revealDiagnostic.line);
    editorRef.current?.setPosition({ lineNumber: revealDiagnostic.line, column: revealDiagnostic.column });
    editorRef.current?.focus();
  }, [activePath, revealDiagnostic]);

  const handleMount: OnMount = (editor) => {
    editorRef.current = editor;
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
    editor.focus();
    editor.onDidChangeCursorSelection(({ selection }) => {
      if (selection.isEmpty()) {
        setSelectionMenu(null);
        return;
      }

      const model = editor.getModel();
      const visiblePosition = editor.getScrolledVisiblePosition(selection.getEndPosition());
      if (!model || !visiblePosition || !editorElementRef.current) {
        return;
      }

      const container = editorElementRef.current.getBoundingClientRect();
      const left = Math.min(Math.max(16, visiblePosition.left + 54), Math.max(16, container.width - 240));
      const top = Math.min(visiblePosition.top + visiblePosition.height + 10, Math.max(16, container.height - 160));
      setSelectionMenu({
        left,
        top,
        range: {
          startLine: selection.startLineNumber,
          startColumn: selection.startColumn,
          endLine: selection.endLineNumber,
          endColumn: selection.endColumn
        },
        selectedText: model.getValueInRange(selection)
      });
    });
  };

  return (
    <section className="editor-pane" aria-label="Code editor">
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

      <div className="editor-canvas" ref={editorElementRef}>
        {activeDocument ? (
          <Editor
            key={activeDocument.relativePath}
            path={activeDocument.relativePath}
            language={activeDocument.relativePath.endsWith(".py") ? "python" : "plaintext"}
            value={activeDocument.content}
            onChange={(value) => onChange(value ?? "")}
            onMount={handleMount}
            theme="vs"
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

        {selectionMenu && activeDocument?.relativePath.endsWith(".py") && (
          <div
            className="selection-actions"
            style={{ left: selectionMenu.left, top: selectionMenu.top }}
          >
            <button
              className="selection-trigger"
              type="button"
              onClick={() => onAddToChat(selectionMenu.range, selectionMenu.selectedText)}
            >
              Add to chat
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

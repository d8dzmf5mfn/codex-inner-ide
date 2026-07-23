import { ChevronDown, ChevronUp, CircleCheck, CircleX, Square } from "lucide-react";
import type { Diagnostic } from "../types/inner-host";

type OutputPanelProps = {
  languageLabel: string;
  open: boolean;
  running: boolean;
  exitCode: number | null;
  output: string;
  diagnostics: Diagnostic[];
  onToggle: () => void;
  onStop: () => void;
  onOpenDiagnostic: (diagnostic: Diagnostic) => void;
};

export function OutputPanel({
  languageLabel,
  open,
  running,
  exitCode,
  output,
  diagnostics,
  onToggle,
  onStop,
  onOpenDiagnostic
}: OutputPanelProps) {
  return (
    <section className={`output-panel${open ? " output-panel-open" : ""}`} aria-label={`${languageLabel} output`}>
      <div className="output-heading">
        <button className="output-toggle" onClick={onToggle} type="button">
          <span>Output</span>
          {diagnostics.length > 0 && <span className="problem-count">Problems {diagnostics.length}</span>}
        </button>
        <span className="output-status">
          {running ? (
            <button className="stop-button" type="button" onClick={onStop}><Square size={11} fill="currentColor" /> Stop</button>
          ) : exitCode === null ? null : exitCode === 0 ? (
            <><CircleCheck size={14} /> Exit 0</>
          ) : (
            <><CircleX size={14} /> Exit {exitCode}</>
          )}
          <button className="panel-chevron" onClick={onToggle} type="button" aria-label={open ? "Collapse output" : "Expand output"}>
            {open ? <ChevronDown size={14} /> : <ChevronUp size={14} />}
          </button>
        </span>
      </div>
      {open && (
        <div className="output-content">
          <pre>{output || `Run, preview, or validate the active ${languageLabel} file to see output.`}</pre>
          <div className="diagnostics" aria-label="Problems">
            {diagnostics.length === 0 ? (
              <div className="no-problems">No problems.</div>
            ) : diagnostics.map((diagnostic, index) => (
              <button
                className="diagnostic-row"
                key={`${diagnostic.relativePath}:${diagnostic.line}:${index}`}
                type="button"
                onClick={() => onOpenDiagnostic(diagnostic)}
              >
                <CircleX size={14} aria-hidden="true" />
                <span>{diagnostic.relativePath}:{diagnostic.line}:{diagnostic.column}</span>
                <span>{diagnostic.message}</span>
              </button>
            ))}
          </div>
        </div>
      )}
    </section>
  );
}

import { ExternalLink, X } from "lucide-react";
import type { PreviewDescriptor } from "../types/inner-host";

type PreviewPaneProps = {
  preview: PreviewDescriptor;
  onClose: () => void;
  onOpenExternal: () => void;
};

export function PreviewPane({ preview, onClose, onOpenExternal }: PreviewPaneProps) {
  return (
    <section className="preview-pane" aria-label={`${preview.languageId} preview`}>
      <div className="preview-heading">
        <span>Preview · {preview.entryRelativePath ?? preview.relativePath}</span>
        <span>
          {preview.url && (
            <button type="button" onClick={onOpenExternal} aria-label="Open preview in default browser">
              <ExternalLink size={14} />
            </button>
          )}
          <button type="button" onClick={onClose} aria-label="Close preview"><X size={14} /></button>
        </span>
      </div>
      {preview.url ? (
        <iframe
          className="web-preview-frame"
          src={preview.url}
          title={`${preview.entryRelativePath ?? preview.relativePath} preview`}
          sandbox="allow-forms allow-modals allow-scripts"
        />
      ) : (
        <div className="markdown-preview">{renderMarkdown(preview.content ?? "")}</div>
      )}
    </section>
  );
}

function renderMarkdown(source: string) {
  const lines = source.replace(/\r\n/g, "\n").split("\n");
  const blocks: React.ReactNode[] = [];
  let inCode = false;
  let code: string[] = [];
  let paragraph: string[] = [];

  const flushParagraph = () => {
    if (paragraph.length === 0) return;
    blocks.push(<p key={`p-${blocks.length}`}>{paragraph.join(" ")}</p>);
    paragraph = [];
  };
  const flushCode = () => {
    blocks.push(<pre key={`code-${blocks.length}`}><code>{code.join("\n")}</code></pre>);
    code = [];
  };

  for (const line of lines) {
    if (line.startsWith("```")) {
      flushParagraph();
      if (inCode) flushCode();
      inCode = !inCode;
      continue;
    }
    if (inCode) {
      code.push(line);
      continue;
    }
    const heading = /^(#{1,6})\s+(.+)$/.exec(line);
    if (heading) {
      flushParagraph();
      const level = heading[1].length;
      if (level === 1) blocks.push(<h1 key={`h-${blocks.length}`}>{heading[2]}</h1>);
      else if (level === 2) blocks.push(<h2 key={`h-${blocks.length}`}>{heading[2]}</h2>);
      else blocks.push(<h3 key={`h-${blocks.length}`}>{heading[2]}</h3>);
      continue;
    }
    if (/^[-*]\s+/.test(line)) {
      flushParagraph();
      blocks.push(<div className="markdown-list-item" key={`li-${blocks.length}`}>• {line.replace(/^[-*]\s+/, "")}</div>);
      continue;
    }
    if (!line.trim()) flushParagraph();
    else paragraph.push(line.trim());
  }
  flushParagraph();
  if (inCode || code.length > 0) flushCode();
  return blocks;
}

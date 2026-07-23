import { useState } from "react";
import { Plus, Trash2, X } from "lucide-react";
import { LANGUAGE_DEFINITIONS, type LanguageId } from "../core/languages";
import type { UserCompletionSnippet } from "../types/inner-host";

type CompletionSnippetDialogProps = {
  snippets: UserCompletionSnippet[];
  onChange: (snippets: UserCompletionSnippet[]) => Promise<void>;
  onClose: () => void;
};

export function CompletionSnippetDialog({ snippets, onChange, onClose }: CompletionSnippetDialogProps) {
  const [languageId, setLanguageId] = useState<LanguageId>("python");
  const [triggerPrefix, setTriggerPrefix] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [description, setDescription] = useState("");
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const add = async () => {
    const prefix = triggerPrefix.trim();
    const name = displayName.trim();
    if (!prefix || /\s/.test(prefix) || !name || !body.trim()) {
      setError("Prefix must be one word; display name and insertion body are required.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await onChange([...snippets, {
        id: randomId(),
        languageId,
        triggerPrefix: prefix,
        displayName: name,
        description: description.trim(),
        body
      }]);
      setTriggerPrefix("");
      setDisplayName("");
      setDescription("");
      setBody("");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Unable to save the snippet.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="modal-backdrop" role="presentation" onMouseDown={(event) => {
      if (event.currentTarget === event.target) onClose();
    }}>
      <section className="snippet-dialog" role="dialog" aria-modal="true" aria-labelledby="snippet-dialog-title">
        <header>
          <div>
            <h2 id="snippet-dialog-title">Completion snippets</h2>
            <p>Global snippets appear after file, Workspace, and language suggestions.</p>
          </div>
          <button type="button" onClick={onClose} aria-label="Close completion snippets"><X size={16} /></button>
        </header>

        <div className="snippet-list" aria-label="Saved completion snippets">
          {snippets.length === 0 && <p className="snippet-empty">No custom snippets yet.</p>}
          {snippets.map((snippet) => (
            <div className="snippet-item" key={snippet.id}>
              <span className="snippet-prefix">{snippet.triggerPrefix}</span>
              <span><strong>{snippet.displayName}</strong><small>{snippet.languageId} · {snippet.description || "No description"}</small></span>
              <button
                type="button"
                aria-label={`Delete ${snippet.displayName}`}
                onClick={() => void onChange(snippets.filter((value) => value.id !== snippet.id))}
              ><Trash2 size={14} /></button>
            </div>
          ))}
        </div>

        <div className="snippet-form">
          <label>Language
            <select value={languageId} onChange={(event) => setLanguageId(event.target.value as LanguageId)}>
              {LANGUAGE_DEFINITIONS.map((language) => (
                <option key={language.id} value={language.id}>{language.label}</option>
              ))}
            </select>
          </label>
          <label>Trigger prefix
            <input value={triggerPrefix} onChange={(event) => setTriggerPrefix(event.target.value)} placeholder="pr" maxLength={64} />
          </label>
          <label>Display name
            <input value={displayName} onChange={(event) => setDisplayName(event.target.value)} placeholder="Print debug value" maxLength={120} />
          </label>
          <label>Description
            <input value={description} onChange={(event) => setDescription(event.target.value)} placeholder="Optional details" maxLength={500} />
          </label>
          <label className="snippet-body-field">Insertion body
            <textarea value={body} onChange={(event) => setBody(event.target.value)} placeholder={'print("${1:value}")'} maxLength={20_000} />
          </label>
          {error && <p className="snippet-error" role="alert">{error}</p>}
          <button className="snippet-add" type="button" onClick={() => void add()} disabled={saving}>
            <Plus size={14} /> {saving ? "Saving…" : "Add snippet"}
          </button>
        </div>
      </section>
    </div>
  );
}

function randomId() {
  return typeof crypto.randomUUID === "function"
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

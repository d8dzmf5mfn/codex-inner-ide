import type { FileSnapshot } from "../types/inner-host";

export type OpenDocument = FileSnapshot & {
  savedContent: string;
  dirty: boolean;
};

export function openDocument(snapshot: FileSnapshot): OpenDocument {
  return {
    ...snapshot,
    savedContent: snapshot.content,
    dirty: false
  };
}

export function editDocument(document: OpenDocument, content: string): OpenDocument {
  return {
    ...document,
    content,
    dirty: content !== document.savedContent
  };
}

export function markDocumentSaved(
  document: OpenDocument,
  snapshot: FileSnapshot
): OpenDocument {
  return {
    ...document,
    ...snapshot,
    savedContent: snapshot.content,
    dirty: false
  };
}

export function replaceCleanDocument(
  document: OpenDocument,
  snapshot: FileSnapshot
): OpenDocument {
  return document.dirty ? document : openDocument(snapshot);
}

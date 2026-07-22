import { describe, expect, it } from "vitest";
import {
  editDocument,
  markDocumentSaved,
  openDocument,
  replaceCleanDocument
} from "../src/core/documents";

const snapshot = {
  relativePath: "main.py",
  content: "print('one')\n",
  digest: "digest-one",
  readonly: false
};

describe("document state", () => {
  it("tracks dirty state against the last saved content", () => {
    const opened = openDocument(snapshot);
    expect(opened.dirty).toBe(false);
    expect(editDocument(opened, "print('two')\n").dirty).toBe(true);
    expect(editDocument(opened, snapshot.content).dirty).toBe(false);
  });

  it("adopts a successful versioned save", () => {
    const edited = editDocument(openDocument(snapshot), "print('two')\n");
    const saved = markDocumentSaved(edited, {
      ...snapshot,
      content: "print('two')\n",
      digest: "digest-two"
    });
    expect(saved.dirty).toBe(false);
    expect(saved.digest).toBe("digest-two");
  });

  it("does not overwrite a dirty editor with an external snapshot", () => {
    const edited = editDocument(openDocument(snapshot), "print('editor')\n");
    const external = { ...snapshot, content: "print('disk')\n", digest: "digest-disk" };
    expect(replaceCleanDocument(edited, external)).toEqual(edited);
    expect(replaceCleanDocument(openDocument(snapshot), external).content).toBe("print('disk')\n");
  });
});

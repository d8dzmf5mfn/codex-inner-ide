import { afterEach, describe, expect, it, vi } from "vitest";
import { digestText, previewLines, textInRange } from "../src/core/edits";

describe("Codex edit proposal helpers", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("uses Monaco UTF-16 columns for selections", () => {
    expect(textInRange("value = \"😀\"\n", {
      startLine: 1,
      startColumn: 10,
      endLine: 1,
      endColumn: 12
    })).toBe("😀");
  });

  it("computes a stable SHA-256 buffer digest", async () => {
    await expect(digestText("print('one')\n")).resolves.toBe(
      "046076f59b3d9fe61bc5261e95b7e9e371634206007c3a1143f9eb6f3c8c0f85"
    );
  });

  it("computes SHA-256 when WKWebView does not expose crypto.subtle", async () => {
    vi.stubGlobal("crypto", {});
    await expect(digestText("print('one')\n")).resolves.toBe(
      "046076f59b3d9fe61bc5261e95b7e9e371634206007c3a1143f9eb6f3c8c0f85"
    );
  });

  it("reduces a whole-file proposal to the changed line preview", () => {
    const preview = previewLines("one\ntwo\nthree\n", {
      proposalId: "proposal",
      workspaceId: "workspace",
      relativePath: "main.py",
      scope: "file",
      baseBufferDigest: "digest",
      summary: "Change the middle line",
      replacementText: "one\nchanged\nthree\n",
      state: "ready"
    });
    expect(preview).toEqual({ startLine: 2, endLine: 2, replacement: "changed" });
  });
});

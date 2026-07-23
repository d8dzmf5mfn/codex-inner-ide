import { describe, expect, it } from "vitest";
import { createMockInnerHost } from "../src/bridge/inner-host.mock";

describe("development Inner IDE host", () => {
  it("enforces expectedDigest writes", async () => {
    const host = createMockInnerHost();
    const before = await host.files.read("main.py");
    const after = await host.files.write({
      relativePath: "main.py",
      content: `${before.content}\nprint('saved')\n`,
      expectedDigest: before.digest
    });
    expect(after.digest).not.toBe(before.digest);

    await expect(host.files.write({
      relativePath: "main.py",
      content: "print('stale')\n",
      expectedDigest: before.digest
    })).rejects.toMatchObject({ name: "FileChangedError" });
  });

  it("runs a Python file through the host contract", async () => {
    const host = createMockInnerHost();
    const [interpreter] = await host.python.discover();
    const events: string[] = [];
    host.python.subscribe((event) => {
      if (event.text) events.push(event.text);
    });
    const result = await host.python.run("main.py", interpreter.id);
    expect(result.runId).toBeTruthy();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(events.join("")).toContain("Codex Inner IDE is ready");
  });

  it("exposes run, validate, and preview actions through the shared runtime contract", async () => {
    const host = createMockInnerHost();
    const [java] = await host.runtime.discover("java");
    const events: string[] = [];
    host.runtime.subscribe((event) => {
      if (event.text) events.push(event.text);
    });

    await host.runtime.execute({ relativePath: "Main.java", languageId: "java", runtimeId: java.id });
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(events.join("")).toContain("Ran Main.java");
    await expect(host.runtime.check({
      relativePath: "data.json",
      languageId: "json",
      runtimeId: "mock-json"
    })).resolves.toEqual([]);
    await expect(host.preview.open({
      relativePath: "README.md",
      languageId: "markdown"
    })).resolves.toMatchObject({ content: expect.stringContaining("Python example") });
  });

  it("routes More details to ChatGPT without submitting", async () => {
    const host = createMockInnerHost();
    const context = {
      workspaceId: "mock-workspace",
      relativePath: "main.py",
      language: "python" as const,
      range: { startLine: 1, startColumn: 1, endLine: 1, endColumn: 6 },
      selectedText: "print",
      surroundingText: "print('hello')",
      dirty: false
    };
    await expect(host.chatgpt.moreDetails(context)).resolves.toMatchObject({
      destination: "chatgpt",
      submitted: false
    });
  });

  it("persists the per-workspace pin state", async () => {
    const host = createMockInnerHost();
    await host.window.saveState({
      openPaths: ["main.py"],
      activePath: "main.py",
      bottomPanelOpen: true,
      expandedDirectories: [],
      pinned: true
    });
    await expect(host.window.loadState()).resolves.toMatchObject({ pinned: true });
  });

  it("switches only through authorized recent workspace ids", async () => {
    const host = createMockInnerHost();
    await expect(host.workspace.recent()).resolves.toEqual(expect.arrayContaining([
      expect.objectContaining({ id: "mock-workspace", available: true }),
      expect.objectContaining({ id: "mock-missing", available: false })
    ]));
    await expect(host.workspace.openRecent("untrusted-id")).rejects.toThrow("Unknown recent workspace");
    await expect(host.workspace.openRecent("mock-missing")).rejects.toThrow("no longer available");
    await expect(host.workspace.openRecent("mock-secondary")).resolves.toMatchObject({ id: "mock-secondary" });
  });

  it("restores window state independently for each workspace", async () => {
    const host = createMockInnerHost();
    await host.window.saveState({
      openPaths: ["main.py"],
      activePath: "main.py",
      bottomPanelOpen: true,
      expandedDirectories: ["tests"]
    });
    await host.workspace.openRecent("mock-secondary");
    await expect(host.window.loadState()).resolves.toBeNull();
    await host.window.saveState({
      openPaths: ["index.html"],
      activePath: "index.html",
      bottomPanelOpen: false,
      expandedDirectories: []
    });
    await host.workspace.openRecent("mock-workspace");
    await expect(host.window.loadState()).resolves.toMatchObject({
      activePath: "main.py",
      expandedDirectories: ["tests"]
    });
  });

  it("persists global completion snippets through the preferences contract", async () => {
    const host = createMockInnerHost();
    await host.preferences.save({
      themeMode: "auto",
      completionSnippets: [{
        id: "print-debug",
        languageId: "python",
        triggerPrefix: "pr",
        displayName: "Print debug value",
        description: "Debug helper",
        body: "print(${1:value})"
      }]
    });
    await expect(host.preferences.load()).resolves.toMatchObject({
      completionSnippets: [{ triggerPrefix: "pr", languageId: "python" }]
    });
  });

  it("emits a read-only Python proposal without writing the mock file", async () => {
    const host = createMockInnerHost();
    const before = await host.files.read("main.py");
    const proposals: string[] = [];
    host.edits.subscribe((event) => proposals.push(event.proposal.state));

    const started = await host.edits.request({ instruction: "Add a comment", scope: "file" });
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(started.state).toBe("generating");
    expect(proposals).toContain("ready");
    await expect(host.files.read("main.py")).resolves.toMatchObject({
      content: before.content,
      digest: before.digest
    });
  });
});

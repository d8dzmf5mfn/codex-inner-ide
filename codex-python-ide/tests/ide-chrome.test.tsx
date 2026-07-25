import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { IdeTitleBar } from "../src/components/IdeChrome";

const baseProps = {
  workspace: { id: "workspace", name: "Workspace", rootLabel: "/Workspace" },
  themeMode: "auto" as const,
  runtimes: [],
  selectedRuntimeId: "",
  activeDocument: null,
  running: false,
  pinned: false,
  sidebarCollapsed: false,
  onSelectRuntime: vi.fn(),
  onRecheckRuntime: vi.fn(),
  onCopySetupCommand: vi.fn(),
  onOpenSetupDownload: vi.fn(),
  onCreateVenv: vi.fn(),
  onSave: vi.fn(),
  onManageSnippets: vi.fn(),
  onThemeModeChange: vi.fn(),
  onToggleSidebar: vi.fn(),
  onEditCurrentFile: vi.fn(),
  onRun: vi.fn(),
  onTogglePin: vi.fn(),
  onClose: vi.fn()
};

describe("IDE title bar host modes", () => {
  it("hides native Pin controls in Browser mode", () => {
    const markup = renderToStaticMarkup(<IdeTitleBar {...baseProps} hostMode="browser" />);
    expect(markup).not.toContain('aria-label="Pin IDE window on top"');
  });

  it("retains Pin controls in native mode", () => {
    const markup = renderToStaticMarkup(<IdeTitleBar {...baseProps} hostMode="native" />);
    expect(markup).toContain('aria-label="Pin IDE window on top"');
  });

  it("clearly labels the development host as non-executing", () => {
    const markup = renderToStaticMarkup(<IdeTitleBar {...baseProps} hostMode="mock" />);
    expect(markup).toContain("Demo host · no real execution");
  });

  it("shows structured Setup guidance only for an unavailable runtime", () => {
    const markup = renderToStaticMarkup(<IdeTitleBar
      {...baseProps}
      hostMode="browser"
      selectedRuntimeId="java-unavailable"
      runtimes={[{
        id: "java-unavailable",
        languageId: "java",
        label: "Java JDK required",
        version: "javac not found",
        source: "missing",
        action: "run",
        available: false,
        unavailableReason: "Install a JDK that includes javac",
        setupOptions: [{
          id: "java-homebrew",
          label: "Install a Java JDK with Homebrew",
          command: "brew install openjdk",
          scope: "system",
          description: "Installs javac and java."
        }]
      }]}
    />);
    expect(markup).toContain("<summary>Setup</summary>");
    expect(markup).toContain("brew install openjdk");
    expect(markup).toContain("Recheck");
  });
});

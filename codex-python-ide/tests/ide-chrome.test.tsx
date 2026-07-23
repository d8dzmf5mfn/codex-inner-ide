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
});

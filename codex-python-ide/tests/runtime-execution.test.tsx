import { act, useEffect } from "react";
import { createRoot } from "react-dom/client";
import { describe, expect, it } from "vitest";
import { createMockInnerHost } from "../src/bridge/inner-host.mock";
import { useRuntimeExecution } from "../src/hooks/useRuntimeExecution";

function renderRuntimeHook() {
  const host = createMockInnerHost();
  let current: ReturnType<typeof useRuntimeExecution> | null = null;
  const container = document.createElement("div");
  const root = createRoot(container);

  function HookHarness() {
    const value = useRuntimeExecution(host);
    useEffect(() => { current = value; });
    current = value;
    return null;
  }

  act(() => root.render(<HookHarness />));
  return {
    get current() {
      if (!current) throw new Error("Runtime hook did not render");
      return current;
    },
    unmount() {
      act(() => root.unmount());
    }
  };
}

describe("runtime execution state", () => {
  it("shows the demo-host failure instead of a false successful run", async () => {
    const result = renderRuntimeHook();

    await act(async () => {
      await result.current.execute({
        relativePath: "main.py",
        languageId: "python",
        runtimeId: "mock-python"
      });
      await new Promise((resolve) => setTimeout(resolve, 0));
    });

    expect(result.current.output).toContain("Demo host did not execute main.py");
    expect(result.current.exitCode).toBe(2);
    expect(result.current.running).toBe(false);
    result.unmount();
  });

  it("reports preview completion in the shared Output state", () => {
    const result = renderRuntimeHook();

    act(() => result.current.report("Preview ready: index.html\n"));

    expect(result.current.output).toBe("Preview ready: index.html\n");
    expect(result.current.exitCode).toBe(0);
    result.unmount();
  });
});

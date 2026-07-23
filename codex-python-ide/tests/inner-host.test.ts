import { afterEach, describe, expect, it } from "vitest";
import { createMockInnerHost } from "../src/bridge/inner-host.mock";
import { resolveInnerHost } from "../src/bridge/inner-host";

afterEach(() => {
  delete window.codexInnerIdeHost;
});

describe("Inner IDE host resolution", () => {
  it("prefers an injected Browser host over the development demo host", () => {
    const browserHost = { ...createMockInnerHost(), hostMode: "browser" as const };
    window.codexInnerIdeHost = { v1: browserHost };

    expect(resolveInnerHost()).toBe(browserHost);
    expect(resolveInnerHost()?.hostMode).toBe("browser");
  });
});

import { describe, expect, it } from "vitest";
import { resolveTheme } from "../src/core/theme";

describe("theme mode", () => {
  it("follows the macOS appearance in automatic mode", () => {
    expect(resolveTheme("auto", false)).toBe("light");
    expect(resolveTheme("auto", true)).toBe("dark");
  });

  it("keeps explicit light and dark modes fixed", () => {
    expect(resolveTheme("light", true)).toBe("light");
    expect(resolveTheme("dark", false)).toBe("dark");
  });
});

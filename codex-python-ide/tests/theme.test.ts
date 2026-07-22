import { describe, expect, it } from "vitest";
import { themeForHour } from "../src/core/theme";

describe("time-adaptive theme", () => {
  it("uses light colors from 07:00 through 18:59", () => {
    expect(themeForHour(7)).toBe("light");
    expect(themeForHour(18)).toBe("light");
  });

  it("uses dark colors overnight", () => {
    expect(themeForHour(19)).toBe("dark");
    expect(themeForHour(0)).toBe("dark");
    expect(themeForHour(6)).toBe("dark");
  });
});

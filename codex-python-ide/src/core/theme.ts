import type { ThemeMode } from "../types/inner-host";

export type ResolvedTheme = "light" | "dark";

export function resolveTheme(mode: ThemeMode, systemDark: boolean): ResolvedTheme {
  if (mode === "dark") return "dark";
  if (mode === "light") return "light";
  return systemDark ? "dark" : "light";
}

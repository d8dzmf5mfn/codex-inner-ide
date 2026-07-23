import { useEffect, useState } from "react";
import { resolveTheme, type ResolvedTheme } from "../core/theme";
import type { ThemeMode } from "../types/inner-host";

const mediaQuery = "(prefers-color-scheme: dark)";

export function useTheme(mode: ThemeMode): ResolvedTheme {
  const [systemDark, setSystemDark] = useState(() => window.matchMedia(mediaQuery).matches);
  const theme = resolveTheme(mode, systemDark);

  useEffect(() => {
    const media = window.matchMedia(mediaQuery);
    const refresh = (event: MediaQueryListEvent | MediaQueryList) => setSystemDark(event.matches);
    refresh(media);
    media.addEventListener("change", refresh);
    return () => media.removeEventListener("change", refresh);
  }, []);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    document.documentElement.style.colorScheme = theme;
  }, [theme]);

  return theme;
}

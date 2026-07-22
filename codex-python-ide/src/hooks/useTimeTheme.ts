import { useEffect, useState } from "react";
import { currentTimeTheme } from "../core/theme";

export function useTimeTheme() {
  const [theme, setTheme] = useState<"light" | "dark">(currentTimeTheme);

  useEffect(() => {
    const refresh = () => setTheme(currentTimeTheme());
    refresh();
    const timer = window.setInterval(refresh, 60_000);
    window.addEventListener("focus", refresh);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener("focus", refresh);
    };
  }, []);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);

  return theme;
}

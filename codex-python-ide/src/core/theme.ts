export type TimeTheme = "light" | "dark";

export function themeForHour(hour: number): TimeTheme {
  return hour >= 7 && hour < 19 ? "light" : "dark";
}

export function currentTimeTheme(): TimeTheme {
  return themeForHour(new Date().getHours());
}

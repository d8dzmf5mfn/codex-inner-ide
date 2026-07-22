import { createMockInnerHost } from "./inner-host.mock";
import type { CodexInnerIdeHostV1 } from "../types/inner-host";

let mockHost: CodexInnerIdeHostV1 | null = null;

export function resolveInnerHost(): CodexInnerIdeHostV1 | null {
  const nativeHost = window.codexInnerIdeHost?.v1;
  if (nativeHost?.apiVersion === "1") return nativeHost;

  const mockEnabled = import.meta.env.DEV || import.meta.env.VITE_USE_MOCK_INNER_HOST === "true";
  if (!mockEnabled) return null;

  mockHost ??= createMockInnerHost();
  return mockHost;
}

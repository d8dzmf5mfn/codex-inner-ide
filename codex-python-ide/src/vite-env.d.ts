/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_USE_MOCK_INNER_HOST?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}

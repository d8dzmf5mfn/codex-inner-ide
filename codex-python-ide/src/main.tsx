import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./monaco";
import "./styles.css";
import { App } from "./App";

const rootElement = document.getElementById("root");
if (!rootElement) throw new Error("Codex Inner IDE mount point is missing");

const reactRoot = createRoot(rootElement);
window.__codexInnerIdeReactRoot = reactRoot;
reactRoot.render(
  <StrictMode>
    <App />
  </StrictMode>
);

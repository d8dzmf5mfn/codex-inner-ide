import { useCallback, useEffect, useState } from "react";
import type { CodexInnerIdeHostV1, Diagnostic } from "../types/inner-host";

export function usePythonExecution(host: CodexInnerIdeHostV1) {
  const [running, setRunning] = useState(false);
  const [runId, setRunId] = useState<string | null>(null);
  const [exitCode, setExitCode] = useState<number | null>(null);
  const [output, setOutput] = useState("");
  const [diagnostics, setDiagnostics] = useState<Diagnostic[]>([]);

  useEffect(() => host.python.subscribe((event) => {
    if (event.kind === "started") {
      setRunId(event.runId);
      setRunning(true);
    } else if (event.kind === "output" && event.text) {
      setOutput((value) => value + event.text);
    } else if (event.kind === "exited" || event.kind === "failed") {
      if (event.text) setOutput((value) => value + `${event.text}\n`);
      setRunId(null);
      setRunning(false);
      setExitCode(event.exitCode ?? -1);
      if (event.diagnostics) setDiagnostics(event.diagnostics);
    }
  }), [host]);

  const run = useCallback(async (relativePath: string, interpreterId: string) => {
    setRunning(true);
    setOutput("");
    setDiagnostics([]);
    setExitCode(null);
    try {
      const started = await host.python.run(relativePath, interpreterId);
      setRunId(started.runId);
      return true;
    } catch (reason) {
      setRunning(false);
      setExitCode(-1);
      setOutput(`${message(reason, "Python execution failed")}\n`);
      return false;
    }
  }, [host]);

  const checkSyntax = useCallback(async (relativePath: string, interpreterId: string) => {
    const next = await host.python.checkSyntax(relativePath, interpreterId);
    setDiagnostics(next);
    return next;
  }, [host]);

  const stop = useCallback(() => {
    if (runId) void host.python.terminate(runId);
  }, [host, runId]);

  return {
    running,
    exitCode,
    output,
    diagnostics,
    run,
    stop,
    checkSyntax
  };
}

function message(reason: unknown, fallback: string) {
  return reason instanceof Error ? reason.message : fallback;
}

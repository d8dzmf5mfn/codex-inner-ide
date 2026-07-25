import { useCallback, useEffect, useState } from "react";
import type {
  CodexInnerIdeHostV1,
  Diagnostic,
  RuntimeCheckRequest,
  RuntimeExecuteRequest
} from "../types/inner-host";

export function useRuntimeExecution(host: CodexInnerIdeHostV1) {
  const [running, setRunning] = useState(false);
  const [runId, setRunId] = useState<string | null>(null);
  const [languageId, setLanguageId] = useState<string | null>(null);
  const [exitCode, setExitCode] = useState<number | null>(null);
  const [output, setOutput] = useState("");
  const [diagnostics, setDiagnostics] = useState<Diagnostic[]>([]);

  useEffect(() => host.runtime.subscribe((event) => {
    if (event.kind === "started") {
      setRunId(event.runId);
      setLanguageId(event.languageId);
      setRunning(true);
    } else if (event.kind === "output" && event.text) {
      setOutput((value) => value + event.text);
    } else if (event.kind === "exited" || event.kind === "failed") {
      if (event.text) setOutput((value) => value + `${event.text}\n`);
      setRunId(null);
      setRunning(false);
      setExitCode(event.exitCode ?? -1);
      setDiagnostics(event.diagnostics ?? []);
    }
  }), [host]);

  const execute = useCallback(async (request: RuntimeExecuteRequest) => {
    setRunning(true);
    setLanguageId(request.languageId);
    setOutput("");
    setDiagnostics([]);
    setExitCode(null);
    try {
      const started = await host.runtime.execute(request);
      setRunId(started.runId);
      return true;
    } catch (reason) {
      setRunning(false);
      setExitCode(-1);
      setOutput(`${message(reason, "Execution failed")}\n`);
      return false;
    }
  }, [host]);

  const check = useCallback(async (request: RuntimeCheckRequest) => {
    const next = await host.runtime.check(request);
    setDiagnostics(next);
    return next;
  }, [host]);

  const stop = useCallback(() => {
    if (runId) void host.runtime.terminate(runId);
  }, [host, runId]);

  const clear = useCallback(() => {
    setOutput("");
    setDiagnostics([]);
    setExitCode(null);
  }, []);

  const report = useCallback((
    text: string,
    nextExitCode = 0,
    nextDiagnostics: Diagnostic[] = []
  ) => {
    setRunning(false);
    setRunId(null);
    setOutput(text);
    setDiagnostics(nextDiagnostics);
    setExitCode(nextExitCode);
  }, []);

  const reset = useCallback(() => {
    setRunning(false);
    setRunId(null);
    setLanguageId(null);
    setOutput("");
    setDiagnostics([]);
    setExitCode(null);
  }, []);

  return {
    running,
    runId,
    languageId,
    exitCode,
    output,
    diagnostics,
    execute,
    stop,
    check,
    clear,
    report,
    reset
  };
}

function message(reason: unknown, fallback: string) {
  return reason instanceof Error ? reason.message : fallback;
}

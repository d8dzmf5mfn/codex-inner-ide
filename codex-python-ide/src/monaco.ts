import { loader } from "@monaco-editor/react";
import * as monaco from "monaco-editor/editor/editor.api.js";
import "monaco-editor/languages/definitions/python/register.js";
import "monaco-editor/languages/definitions/java/register.js";
import "monaco-editor/languages/definitions/html/register.js";
import "monaco-editor/languages/definitions/typescript/register.js";
import "monaco-editor/languages/definitions/javascript/register.js";
import "monaco-editor/languages/definitions/css/register.js";
import "monaco-editor/languages/definitions/markdown/register.js";
import EditorWorker from "monaco-editor/editor/editor.worker.js?worker&inline";

monaco.languages.register({
  id: "json",
  extensions: [".json", ".jsonc"],
  aliases: ["JSON", "json"]
});
monaco.languages.setMonarchTokensProvider("json", {
  tokenPostfix: ".json",
  tokenizer: {
    root: [
      [/\{/, "delimiter.bracket"],
      [/\}/, "delimiter.bracket"],
      [/\[/, "delimiter.array"],
      [/\]/, "delimiter.array"],
      [/[,:]/, "delimiter"],
      [/"(?:\\.|[^"\\])*"(?=\s*:)/, "string.key"],
      [/"(?:\\.|[^"\\])*"/, "string.value"],
      [/-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/, "number"],
      [/\b(?:true|false|null)\b/, "keyword"],
      [/\/\/.*$/, "comment"],
      [/\/\*/, "comment", "@comment"]
    ],
    comment: [
      [/[^/*]+/, "comment"],
      [/\*\//, "comment", "@pop"],
      [/[/*]/, "comment"]
    ]
  }
});

self.MonacoEnvironment = {
  getWorker() {
    return new EditorWorker();
  }
};

loader.config({ monaco });

export { monaco };

import { describe, expect, it } from "vitest";
import { filterTreeEntries } from "../src/components/FileTree";
import type { FileEntry } from "../src/types/inner-host";

const entry = (name: string, relativePath: string, kind: FileEntry["kind"]): FileEntry => ({
  name,
  relativePath,
  kind
});

describe("file tree filtering", () => {
  const children: Record<string, FileEntry[]> = {
    "": [
      entry("src", "src", "directory"),
      entry("tests", "tests", "directory"),
      entry("README.md", "README.md", "file")
    ],
    src: [entry("main.ts", "src/main.ts", "file")],
    tests: [entry("test_main.py", "tests/test_main.py", "file")]
  };

  it("keeps parent directories for matching descendants", () => {
    expect(filterTreeEntries(children, "main").map((value) => [value.entry.relativePath, value.depth])).toEqual([
      ["src", 0],
      ["src/main.ts", 1],
      ["tests", 0],
      ["tests/test_main.py", 1]
    ]);
  });

  it("matches case-insensitively and returns an empty result cleanly", () => {
    expect(filterTreeEntries(children, "README").map((value) => value.entry.relativePath)).toEqual(["README.md"]);
    expect(filterTreeEntries(children, "missing")).toEqual([]);
  });
});

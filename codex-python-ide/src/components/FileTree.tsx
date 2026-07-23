import { type FormEvent, useEffect, useMemo, useState } from "react";
import {
  Braces,
  ChevronDown,
  ChevronRight,
  FileCode2,
  FilePlus2,
  FileText,
  Folder,
  FolderOpen,
  FolderPlus,
  Pencil,
  Search,
  Trash2,
  X
} from "lucide-react";
import {
  LANGUAGE_DEFINITIONS,
  languageForId,
  languageForPath,
  registeredLanguageForPath,
  resolveNewFileName,
  type LanguageId
} from "../core/languages";
import { shouldSkipIndexedDirectory } from "../core/completions";
import type { FileEntry, FileKind } from "../types/inner-host";
import type { RecentWorkspace, WorkspaceBinding } from "../types/inner-host";
import { WorkspaceSwitcher } from "./WorkspaceSwitcher";

type FileTreeProps = {
  workspace: WorkspaceBinding;
  recentWorkspaces: RecentWorkspace[];
  workspaceSwitching: boolean;
  rootEntries: FileEntry[];
  activePath: string | null;
  initialExpanded: string[];
  revision: number;
  onExpandedChange: (paths: string[]) => void;
  onLoadDirectory: (relativePath: string) => Promise<FileEntry[]>;
  onOpenFile: (relativePath: string) => void;
  onCreate: (relativePath: string, kind: FileKind) => Promise<void>;
  onRename: (from: string, to: string) => Promise<void>;
  onTrash: (relativePath: string) => Promise<void>;
  onError: (reason: unknown) => void;
  onChooseWorkspace: () => Promise<void>;
  onOpenRecentWorkspace: (id: string) => Promise<void>;
  onRemoveRecentWorkspace: (id: string) => Promise<void>;
  onRelocateRecentWorkspace: (id: string) => Promise<void>;
};

export function FileTree({
  workspace,
  recentWorkspaces,
  workspaceSwitching,
  rootEntries,
  activePath,
  initialExpanded,
  revision,
  onExpandedChange,
  onLoadDirectory,
  onOpenFile,
  onCreate,
  onRename,
  onTrash,
  onError,
  onChooseWorkspace,
  onOpenRecentWorkspace,
  onRemoveRecentWorkspace,
  onRelocateRecentWorkspace
}: FileTreeProps) {
  const [children, setChildren] = useState<Record<string, FileEntry[]>>({ "": rootEntries });
  const [expanded, setExpanded] = useState(() => new Set(initialExpanded));
  const [selectedDirectory, setSelectedDirectory] = useState("");
  const [createKind, setCreateKind] = useState<FileKind | null>(null);
  const [createName, setCreateName] = useState("");
  const [createLanguageId, setCreateLanguageId] = useState<LanguageId>("python");
  const [filter, setFilter] = useState("");
  const normalizedFilter = filter.trim().toLocaleLowerCase();

  useEffect(() => {
    setChildren((current) => ({ ...current, "": rootEntries }));
  }, [rootEntries]);

  useEffect(() => {
    void Promise.all([...expanded].map(async (path) => [path, await onLoadDirectory(path)] as const))
      .then((loaded) => setChildren((current) => ({ ...current, ...Object.fromEntries(loaded) })));
  }, [revision]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!normalizedFilter) return;
    let cancelled = false;
    const timer = window.setTimeout(() => {
      void (async () => {
        const queue = rootEntries
          .filter((entry) => entry.kind === "directory" && !shouldSkipIndexedDirectory(entry.relativePath))
          .map((entry) => entry.relativePath);
        const visited = new Set<string>();
        let scanned = 0;
        while (!cancelled && queue.length > 0 && scanned < 400) {
          const batch = queue.splice(0, 8).filter((path) => !visited.has(path));
          batch.forEach((path) => visited.add(path));
          const results = await Promise.allSettled(batch.map(async (path) => [path, await onLoadDirectory(path)] as const));
          const loaded = results
            .filter((result): result is PromiseFulfilledResult<readonly [string, FileEntry[]]> => result.status === "fulfilled")
            .map((result) => result.value);
          if (loaded.length > 0) {
            setChildren((current) => ({ ...current, ...Object.fromEntries(loaded) }));
          }
          for (const [, entries] of loaded) {
            for (const entry of entries) {
              if (entry.kind === "directory" && !shouldSkipIndexedDirectory(entry.relativePath)) {
                queue.push(entry.relativePath);
              }
            }
          }
          scanned += batch.length;
        }
      })();
    }, 120);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [normalizedFilter, revision]); // eslint-disable-line react-hooks/exhaustive-deps

  const flattened = useMemo(
    () => normalizedFilter ? filterTreeEntries(children, normalizedFilter) : flatten(children, expanded),
    [children, expanded, normalizedFilter]
  );

  const toggle = async (entry: FileEntry) => {
    setSelectedDirectory(entry.relativePath);
    const next = new Set(expanded);
    if (next.has(entry.relativePath)) {
      next.delete(entry.relativePath);
    } else {
      next.add(entry.relativePath);
      const loaded = await onLoadDirectory(entry.relativePath);
      setChildren((current) => ({ ...current, [entry.relativePath]: loaded }));
    }
    setExpanded(next);
    onExpandedChange([...next]);
  };

  const beginCreate = (kind: FileKind) => {
    setCreateKind(kind);
    setCreateName("");
    if (kind === "file") {
      setCreateLanguageId(activePath ? languageForPath(activePath).id : "python");
    }
  };

  const cancelCreate = () => {
    setCreateKind(null);
    setCreateName("");
  };

  const create = async (event: FormEvent) => {
    event.preventDefault();
    if (!createKind) return;
    const name = createName.trim();
    if (!name || name.includes("/") || name === "." || name === ".." || name.endsWith(".")) {
      onError(new Error("Enter a valid name without path separators."));
      return;
    }
    const resolved = createKind === "file"
      ? resolveNewFileName(name, createLanguageId)
      : { fileName: name, appendedDefaultExtension: false };
    if (resolved.appendedDefaultExtension) {
      const language = languageForId(createLanguageId);
      const confirmed = window.confirm(
        `"${name}" has no extension. Create "${resolved.fileName}" as ${language.label}?`
      );
      if (!confirmed) return;
    }
    const path = selectedDirectory
      ? `${selectedDirectory}/${resolved.fileName}`
      : resolved.fileName;
    try {
      await onCreate(path, createKind);
      cancelCreate();
    } catch (reason) {
      onError(reason);
    }
  };

  return (
    <aside className="file-tree" aria-label="Project files">
      <div className="file-tree-top">
        <label className="file-filter">
          <Search size={16} strokeWidth={1.7} aria-hidden="true" />
          <input
            type="search"
            aria-label="Filter files"
            placeholder="Filter files…"
            value={filter}
            onChange={(event) => setFilter(event.target.value)}
          />
          {filter && (
            <button type="button" aria-label="Clear file filter" onClick={() => setFilter("")}>
              <X size={13} />
            </button>
          )}
        </label>
        <div className="file-tree-heading">
          <WorkspaceSwitcher
            workspace={workspace}
            recent={recentWorkspaces}
            busy={workspaceSwitching}
            onChoose={onChooseWorkspace}
            onOpenRecent={onOpenRecentWorkspace}
            onRemoveRecent={onRemoveRecentWorkspace}
            onRelocateRecent={onRelocateRecentWorkspace}
          />
          <span className="tree-heading-actions">
            <button type="button" aria-label="New file" title="New file" onClick={() => beginCreate("file")}>
              <FilePlus2 size={15} />
            </button>
            <button type="button" aria-label="New folder" title="New folder" onClick={() => beginCreate("directory")}>
              <FolderPlus size={15} />
            </button>
          </span>
        </div>
      </div>
      {createKind && (
        <form className="tree-create-form" aria-label={createKind === "file" ? "Create file" : "Create folder"} onSubmit={(event) => void create(event)}>
          <label htmlFor="tree-create-name">{createKind === "file" ? "File name" : "Folder name"}</label>
          <input
            id="tree-create-name"
            aria-label={createKind === "file" ? "File name" : "Folder name"}
            autoFocus
            value={createName}
            onChange={(event) => {
              const next = event.target.value;
              setCreateName(next);
              const detected = registeredLanguageForPath(next);
              if (detected) setCreateLanguageId(detected.id);
            }}
            onKeyDown={(event) => { if (event.key === "Escape") cancelCreate(); }}
            placeholder={createKind === "file"
              ? `example${languageForId(createLanguageId).defaultExtension}`
              : "folder-name"}
          />
          {createKind === "file" && (
            <>
              <label htmlFor="tree-create-language">Language</label>
              <select
                id="tree-create-language"
                aria-label="File language"
                value={createLanguageId}
                onChange={(event) => setCreateLanguageId(event.target.value as LanguageId)}
              >
                {LANGUAGE_DEFINITIONS.map((language) => (
                  <option key={language.id} value={language.id}>{language.label}</option>
                ))}
              </select>
            </>
          )}
          <div className="tree-create-actions">
            <button type="submit">Create</button>
            <button type="button" onClick={cancelCreate}>Cancel</button>
          </div>
        </form>
      )}
      <div className="tree-entries" role="tree">
        {flattened.map(({ entry, depth }) => {
          const isDirectory = entry.kind === "directory";
          const isExpanded = normalizedFilter ? true : expanded.has(entry.relativePath);
          const isActive = !isDirectory && activePath === entry.relativePath;
          const iconKind = languageForPath(entry.relativePath).iconKind;
          const Icon = isDirectory
            ? (isExpanded ? FolderOpen : Folder)
            : iconKind === "code" || iconKind === "markup"
              ? FileCode2
              : iconKind === "data" ? Braces : FileText;
          return (
            <div
              className={`tree-row-wrap${isActive ? " tree-row-active" : ""}`}
              key={`${entry.kind}:${entry.relativePath}`}
              role="treeitem"
              data-depth={depth}
              data-language={isDirectory ? undefined : languageForPath(entry.relativePath).id}
              aria-expanded={isDirectory ? isExpanded : undefined}
              aria-selected={isActive}
            >
              {depth > 0 && <span className="tree-guides" style={{ width: `${depth * 17}px` }} aria-hidden="true" />}
              <button
                className="tree-row"
                onClick={() => isDirectory ? void toggle(entry) : onOpenFile(entry.relativePath)}
                style={{ paddingLeft: `${10 + depth * 17}px` }}
                type="button"
              >
                {isDirectory
                  ? isExpanded ? <ChevronDown size={12} /> : <ChevronRight size={12} />
                  : <span className="tree-indent" />}
                <Icon size={15} strokeWidth={1.6} aria-hidden="true" />
                <span>{entry.name}</span>
              </button>
              <span className="tree-row-actions">
                <button
                  type="button"
                  aria-label={`Rename ${entry.name}`}
                  onClick={() => {
                    const name = window.prompt("New name", entry.name)?.trim();
                    if (!name || name.includes("/")) return;
                    const parent = entry.relativePath.split("/").slice(0, -1).join("/");
                    void onRename(entry.relativePath, parent ? `${parent}/${name}` : name).catch(onError);
                  }}
                ><Pencil size={12} /></button>
                <button
                  type="button"
                  aria-label={`Move ${entry.name} to Trash`}
                  onClick={() => window.confirm(`Move ${entry.relativePath} to Trash?`) && void onTrash(entry.relativePath).catch(onError)}
                ><Trash2 size={12} /></button>
              </span>
            </div>
          );
        })}
        {normalizedFilter && flattened.length === 0 && (
          <div className="tree-empty">No matching files</div>
        )}
      </div>
    </aside>
  );
}

export function filterTreeEntries(children: Record<string, FileEntry[]>, query: string) {
  const normalizedQuery = query.toLocaleLowerCase();
  const visit = (directory: string, depth: number): Array<{ entry: FileEntry; depth: number }> => {
    const result: Array<{ entry: FileEntry; depth: number }> = [];
    for (const entry of children[directory] ?? []) {
      const matches = entry.name.toLocaleLowerCase().includes(normalizedQuery);
      if (entry.kind === "directory") {
        const descendants = visit(entry.relativePath, depth + 1);
        if (matches || descendants.length > 0) {
          result.push({ entry, depth }, ...descendants);
        }
      } else if (matches) {
        result.push({ entry, depth });
      }
    }
    return result;
  };
  return visit("", 0);
}

function flatten(children: Record<string, FileEntry[]>, expanded: Set<string>) {
  const result: Array<{ entry: FileEntry; depth: number }> = [];
  const visit = (directory: string, depth: number) => {
    for (const entry of children[directory] ?? []) {
      result.push({ entry, depth });
      if (entry.kind === "directory" && expanded.has(entry.relativePath)) {
        visit(entry.relativePath, depth + 1);
      }
    }
  };
  visit("", 0);
  return result;
}

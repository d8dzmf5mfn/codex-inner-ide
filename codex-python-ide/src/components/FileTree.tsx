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
  Trash2
} from "lucide-react";
import {
  LANGUAGE_DEFINITIONS,
  languageForId,
  languageForPath,
  registeredLanguageForPath,
  resolveNewFileName,
  type LanguageId
} from "../core/languages";
import type { FileEntry, FileKind } from "../types/inner-host";

type FileTreeProps = {
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
};

export function FileTree({
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
  onError
}: FileTreeProps) {
  const [children, setChildren] = useState<Record<string, FileEntry[]>>({ "": rootEntries });
  const [expanded, setExpanded] = useState(() => new Set(initialExpanded));
  const [rootExpanded, setRootExpanded] = useState(true);
  const [selectedDirectory, setSelectedDirectory] = useState("");
  const [createKind, setCreateKind] = useState<FileKind | null>(null);
  const [createName, setCreateName] = useState("");
  const [createLanguageId, setCreateLanguageId] = useState<LanguageId>("python");

  useEffect(() => {
    setChildren((current) => ({ ...current, "": rootEntries }));
  }, [rootEntries]);

  useEffect(() => {
    void Promise.all([...expanded].map(async (path) => [path, await onLoadDirectory(path)] as const))
      .then((loaded) => setChildren((current) => ({ ...current, ...Object.fromEntries(loaded) })));
  }, [revision]); // eslint-disable-line react-hooks/exhaustive-deps

  const flattened = useMemo(
    () => rootExpanded ? flatten(children, expanded) : [],
    [children, expanded, rootExpanded]
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
      <div className="panel-heading file-tree-heading">
        <span>Explorer</span>
        <span className="tree-heading-actions">
          <button type="button" aria-label="New file" title="New file" onClick={() => beginCreate("file")}>
            <FilePlus2 size={14} />
          </button>
          <button type="button" aria-label="New folder" title="New folder" onClick={() => beginCreate("directory")}>
            <FolderPlus size={14} />
          </button>
        </span>
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
      <button
        className="tree-root"
        type="button"
        aria-expanded={rootExpanded}
        onClick={() => {
          setSelectedDirectory("");
          setRootExpanded((value) => !value);
        }}
      >
        {rootExpanded
          ? <ChevronDown size={14} strokeWidth={1.7} aria-hidden="true" />
          : <ChevronRight size={14} strokeWidth={1.7} aria-hidden="true" />}
        <span>Workspace</span>
      </button>
      <div className="tree-entries" role="tree">
        {flattened.map(({ entry, depth }) => {
          const isDirectory = entry.kind === "directory";
          const isExpanded = expanded.has(entry.relativePath);
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
              aria-expanded={isDirectory ? isExpanded : undefined}
              aria-selected={isActive}
            >
              <button
                className="tree-row"
                onClick={() => isDirectory ? void toggle(entry) : onOpenFile(entry.relativePath)}
                style={{ paddingLeft: `${9 + depth * 15}px` }}
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
      </div>
    </aside>
  );
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

import { useState } from "react";
import { Check, ChevronsUpDown, FolderOpen, LocateFixed, Plus, X } from "lucide-react";
import type { RecentWorkspace, WorkspaceBinding } from "../types/inner-host";

type WorkspaceSwitcherProps = {
  workspace: WorkspaceBinding;
  recent: RecentWorkspace[];
  busy: boolean;
  onChoose: () => Promise<void>;
  onOpenRecent: (id: string) => Promise<void>;
  onRemoveRecent: (id: string) => Promise<void>;
  onRelocateRecent: (id: string) => Promise<void>;
};

export function WorkspaceSwitcher({
  workspace,
  recent,
  busy,
  onChoose,
  onOpenRecent,
  onRemoveRecent,
  onRelocateRecent
}: WorkspaceSwitcherProps) {
  const [open, setOpen] = useState(false);
  const finish = async (operation: () => Promise<void>) => {
    await operation();
    setOpen(false);
  };

  return (
    <div className="workspace-switcher">
      <button
        className="workspace-switcher-trigger"
        type="button"
        aria-expanded={open}
        aria-haspopup="menu"
        onClick={() => setOpen((value) => !value)}
        disabled={busy}
      >
        <FolderOpen size={14} aria-hidden="true" />
        <span>
          <strong>{workspace.name}</strong>
          <small>{workspace.rootLabel}</small>
        </span>
        <ChevronsUpDown size={13} aria-hidden="true" />
      </button>
      {open && (
        <div className="workspace-menu" role="menu" aria-label="Recent workspaces">
          <span className="workspace-menu-label">Recent Workspaces</span>
          {recent.map((item) => (
            <div className={`workspace-menu-row${item.available ? "" : " workspace-menu-row-unavailable"}`} key={item.id}>
              <button
                className="workspace-menu-open"
                type="button"
                role="menuitem"
                disabled={!item.available || busy}
                onClick={() => void finish(() => onOpenRecent(item.id))}
              >
                <span>{item.name}<small>{item.rootLabel}</small></span>
                {item.id === workspace.id && <Check size={13} aria-label="Current workspace" />}
              </button>
              {!item.available && (
                <button
                  type="button"
                  title={`Locate ${item.name}`}
                  aria-label={`Locate ${item.name}`}
                  disabled={busy}
                  onClick={() => void finish(() => onRelocateRecent(item.id))}
                ><LocateFixed size={13} /></button>
              )}
              <button
                type="button"
                title={`Remove ${item.name} from recent workspaces`}
                aria-label={`Remove ${item.name} from recent workspaces`}
                disabled={item.id === workspace.id || busy}
                onClick={() => void onRemoveRecent(item.id)}
              ><X size={13} /></button>
            </div>
          ))}
          <button
            className="workspace-menu-choose"
            type="button"
            role="menuitem"
            disabled={busy}
            onClick={() => void finish(onChoose)}
          >
            <Plus size={13} aria-hidden="true" /> Choose Folder…
          </button>
        </div>
      )}
    </div>
  );
}

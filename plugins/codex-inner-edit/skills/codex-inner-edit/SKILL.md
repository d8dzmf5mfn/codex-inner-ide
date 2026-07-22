---
name: codex-inner-edit
description: Route explicit requests to edit the active Python document or selection in Codex Inner IDE through a read-only proposal that the user accepts with Enter. Use when the user asks to change, fix, optimize, or refactor the Python code currently open in Codex Inner IDE.
---

# Codex Inner Edit

Use `get_inner_ide_status` before starting an edit when the active IDE state is uncertain.

For an explicit request to change the current Python document:

1. Call `propose_python_edit` with the user's instruction.
2. Use `scope: "auto"` unless the user explicitly asks for the whole file or current selection.
3. Do not call native file-write, patch, or shell tools for the same requested edit.
4. Do not reproduce the source file or replacement code in the task.
5. After the tool starts, tell the user that the proposal will appear in Codex Inner IDE and must be accepted with Enter. Enter changes only the editor buffer; `⌘S` saves it.

If the tool reports that the IDE is closed, no editable Python file is active, or another proposal is pending, give the exact recovery action and stop. Use `cancel_python_edit` only when the user asks to cancel the named proposal.

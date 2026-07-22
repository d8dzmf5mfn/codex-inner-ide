import Foundation

public enum InjectionScripts {
    public static let mainBindingName = "codexInnerIdeMainBridge"

    public static func sidePanelEntry(sessionToken: String) -> String {
        let token = javaScriptLiteral(sessionToken)
        let binding = javaScriptLiteral(mainBindingName)
        return """
        (() => {
          const marker = 'data-codex-inner-ide-entry';
          const bindingName = \(binding);
          const sessionToken = \(token);
          const randomId = () => {
            if (typeof globalThis.crypto?.randomUUID === 'function') return globalThis.crypto.randomUUID();
            const bytes = new Uint8Array(16);
            if (typeof globalThis.crypto?.getRandomValues === 'function') globalThis.crypto.getRandomValues(bytes);
            else for (let index = 0; index < bytes.length; index += 1) bytes[index] = Math.floor(Math.random() * 256);
            bytes[6] = (bytes[6] & 15) | 64;
            bytes[8] = (bytes[8] & 63) | 128;
            const hex = [...bytes].map((value) => value.toString(16).padStart(2, '0')).join('');
            return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
          };
          const visible = (element) => {
            const style = getComputedStyle(element);
            return style.display !== 'none' && style.visibility !== 'hidden' && element.getClientRects().length > 0;
          };
          const findFilesRow = () => {
            const candidates = [...document.querySelectorAll('button,[role="button"],a,div')];
            return candidates.find((element) => {
              if (!visible(element)) return false;
              const text = (element.textContent || '').trim();
              const label = (element.getAttribute('aria-label') || '').trim();
              if (!/^Files(?:\\s|⌘|$)/.test(text) && label !== 'Files') return false;
              const rect = element.getBoundingClientRect();
              return rect.width >= 80 && rect.height >= 22 && rect.height <= 64;
            });
          };
          const install = () => {
            if (document.querySelector(`[${marker}]`)) return true;
            const files = findFilesRow();
            if (!files || !files.parentElement) return false;
            const row = document.createElement('button');
            row.type = 'button';
            row.setAttribute(marker, 'true');
            row.setAttribute('aria-label', 'IDE');
            row.className = files.className;
            row.style.cssText = files.getAttribute('style') || '';
            row.style.width = row.style.width || '100%';
            row.innerHTML = '<span aria-hidden="true" style="font-family:ui-monospace,monospace;width:22px;display:inline-flex;justify-content:center">&lt;/&gt;</span><span>IDE</span>';
            row.addEventListener('click', () => {
              const call = window[bindingName];
              if (typeof call !== 'function') return;
              call(JSON.stringify({
                version: 1,
                requestId: randomId(),
                sessionToken,
                method: 'window.openIde',
                params: { taskKey: location.href }
              }));
            });
            files.insertAdjacentElement('afterend', row);
            return true;
          };
          install();
          window.__codexInnerIdeSidepanelObserver?.disconnect?.();
          const observer = new MutationObserver(() => install());
          observer.observe(document.documentElement, { childList: true, subtree: true });
          window.__codexInnerIdeSidepanelObserver = observer;
          return install();
        })()
        """
    }

    public static func probeWorkspace() -> String {
        """
        (() => {
          const pathPattern = /\\/(?:Users|Volumes)\\/[^\\n\\r\\t"']+/g;
          const values = new Set();
          for (const element of document.querySelectorAll('[title],[aria-label],[data-path]')) {
            for (const value of [element.title, element.getAttribute('aria-label'), element.getAttribute('data-path')]) {
              if (typeof value !== 'string') continue;
              for (const match of value.match(pathPattern) || []) values.add(match.trim());
            }
          }
          return { taskKey: location.href, candidates: [...values].slice(0, 12) };
        })()
        """
    }

    public static func navigateToTask(_ taskKey: String) -> String {
        let task = javaScriptLiteral(taskKey)
        return """
        (() => {
          const raw = \(task);
          if (!raw) return { ok: true, navigated: false };
          let target;
          try { target = new URL(raw); } catch { return { ok: false, reason: 'invalid_task_url' }; }
          if (target.protocol !== 'app:' || target.host !== location.host) {
            return { ok: false, reason: 'rejected_task_url' };
          }
          if (target.href === location.href) return { ok: true, navigated: false };
          location.assign(target.href);
          return { ok: true, navigated: true };
        })()
        """
    }

    public static func composerHandoff(prompt: String) -> String {
        composerInsertion(prompt: prompt, requireQuickChat: false)
    }

    public static func quickChatComposerHandoff(prompt: String) -> String {
        composerInsertion(prompt: prompt, requireQuickChat: true)
    }

    public static func quickChatStatus() -> String {
        """
        (() => {
          const visible = (element) => !!element && element.getClientRects().length > 0
            && getComputedStyle(element).visibility !== 'hidden';
          const exactHeading = [...document.querySelectorAll('h1,h2,h3,[role="heading"]')]
            .find((element) => visible(element) && /^Quick chat$/i.test((element.textContent || '').trim()));
          const explicit = [...document.querySelectorAll('[data-testid*="quick-chat" i],[data-route*="quick-chat" i],[aria-label*="Quick chat" i]')]
            .find(visible);
          const routeMatch = /(?:quick[-_/ ]?chat|chatgpt)/i.test(location.pathname + location.search + location.hash);
          const marker = exactHeading || explicit;
          const container = marker?.closest('[role="dialog"],main,[data-testid]') || (routeMatch ? document.body : null);
          if (!container || !visible(container)) return { ok: false, reason: 'quick_chat_not_visible' };
          const composer = container.querySelector('.composer-surface-chrome [contenteditable="true"]')
            || container.querySelector('[data-testid*="composer"] [contenteditable="true"]')
            || container.querySelector('[role="textbox"][contenteditable="true"]')
            || container.querySelector('textarea');
          return { ok: !!composer && visible(composer), reason: composer ? null : 'quick_chat_composer_not_found' };
        })()
        """
    }

    public static func activateQuickChatSignal() -> String {
        """
        (async () => {
          const visible = (element) => !!element && element.getClientRects().length > 0
            && getComputedStyle(element).visibility !== 'hidden';
          const candidates = () => [...document.querySelectorAll('button,[role="button"],[role="menuitem"],[cmdk-item]')]
            .filter(visible);
          const quickChat = () => candidates().find((element) => {
            const label = [element.getAttribute('aria-label'), element.getAttribute('title'), element.textContent]
              .filter(Boolean).join(' ').trim();
            return /(^|\\b)Quick chat(\\b|$)/i.test(label);
          });
          const activate = (element) => {
            element.focus?.();
            const rect = element.getBoundingClientRect();
            const init = { bubbles: true, cancelable: true, clientX: rect.left + rect.width / 2, clientY: rect.top + rect.height / 2 };
            if (typeof PointerEvent === 'function') {
              element.dispatchEvent(new PointerEvent('pointerdown', { ...init, pointerId: 1, pointerType: 'mouse', isPrimary: true }));
              element.dispatchEvent(new PointerEvent('pointerup', { ...init, pointerId: 1, pointerType: 'mouse', isPrimary: true }));
            }
            element.dispatchEvent(new MouseEvent('mousedown', init));
            element.dispatchEvent(new MouseEvent('mouseup', init));
            element.click();
          };
          let action = quickChat();
          if (!action) {
            const newChat = candidates().find((element) => {
              const label = [element.getAttribute('aria-label'), element.getAttribute('title'), element.textContent]
                .filter(Boolean).join(' ').trim();
              return /^New chat$/i.test(label);
            });
            if (newChat) {
              activate(newChat);
              await new Promise((resolve) => setTimeout(resolve, 250));
              action = quickChat();
            }
          }
          if (!action) return { ok: false, reason: 'quick_chat_action_not_found' };
          activate(action);
          return { ok: true };
        })()
        """
    }

    public static func webViewBridgeBootstrap(sessionToken: String) -> String {
        let token = javaScriptLiteral(sessionToken)
        return """
        (() => {
          const sessionToken = \(token);
          const pending = new Map();
          const listeners = new Map();
          const randomId = () => {
            if (typeof globalThis.crypto?.randomUUID === 'function') return globalThis.crypto.randomUUID();
            const bytes = new Uint8Array(16);
            if (typeof globalThis.crypto?.getRandomValues === 'function') globalThis.crypto.getRandomValues(bytes);
            else for (let index = 0; index < bytes.length; index += 1) bytes[index] = Math.floor(Math.random() * 256);
            bytes[6] = (bytes[6] & 15) | 64;
            bytes[8] = (bytes[8] & 63) | 128;
            const hex = [...bytes].map((value) => value.toString(16).padStart(2, '0')).join('');
            return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
          };
          const call = (method, params = {}) => new Promise((resolve, reject) => {
            const requestId = randomId();
            const timer = setTimeout(() => {
              pending.delete(requestId);
              reject(new Error(`Bridge request timed out: ${method}`));
            }, 120000);
            pending.set(requestId, { resolve, reject, timer });
            const bridge = window.webkit?.messageHandlers?.codexInnerIdeBridge;
            if (!bridge) {
              pending.delete(requestId);
              clearTimeout(timer);
              reject(new Error('Codex Inner IDE bridge is disconnected'));
              return;
            }
            bridge.postMessage({ version: 1, requestId, sessionToken, method, params });
          });
          window.__codexInnerIdeResolve = (response) => {
            const value = typeof response === 'string' ? JSON.parse(response) : response;
            const waiter = pending.get(value.requestId);
            if (!waiter) return;
            pending.delete(value.requestId);
            clearTimeout(waiter.timer);
            if (value.ok) waiter.resolve(value.data);
            else {
              const error = new Error(value.error?.message || 'Bridge request failed');
              error.name = value.error?.code === 'file_changed' ? 'FileChangedError' : 'InnerIDEBridgeError';
              error.code = value.error?.code;
              waiter.reject(error);
            }
          };
          window.__codexInnerIdeEmit = (event) => {
            const value = typeof event === 'string' ? JSON.parse(event) : event;
            for (const listener of listeners.get(value.type) || []) listener(value.payload);
          };
          const subscribe = (type, listener) => {
            const values = listeners.get(type) || new Set();
            values.add(listener);
            listeners.set(type, values);
            return () => values.delete(listener);
          };
          window.codexInnerIdeHost = { v1: {
            apiVersion: '1',
            workspace: {
              current: () => call('workspace.current'),
              choose: () => call('workspace.choose')
            },
            files: {
              list: (path = '') => call('files.list', { relativePath: path }),
              read: (path) => call('files.read', { relativePath: path }),
              write: (request) => call('files.write', request),
              create: (request) => call('files.create', request),
              rename: (request) => call('files.rename', request),
              trash: (path) => call('files.trash', { relativePath: path }),
              watch: (listener) => subscribe('files.changed', listener)
            },
            python: {
              discover: () => call('python.discover'),
              createVenv: () => call('python.createVenv'),
              run: (path, interpreterId) => call('python.run', { relativePath: path, interpreterId }),
              checkSyntax: (path, interpreterId) => call('python.checkSyntax', { relativePath: path, interpreterId }),
              terminate: (runId) => call('python.terminate', { runId }),
              subscribe: (listener) => subscribe('python.event', listener)
            },
            codex: {
              addToChat: (context) => call('codex.addToChat', context)
            },
            chatgpt: {
              moreDetails: (context) => call('chatgpt.moreDetails', context)
            },
            edits: {
              request: async (request) => {
                const getContext = window.__codexInnerIdeGetActiveEditContext;
                if (typeof getContext !== 'function') throw new Error('The editor context is not ready');
                const context = await getContext(request.instruction, request.scope || 'auto');
                if (!context) throw new Error('Open an editable Python file before requesting a proposal');
                return call('edits.request', { instruction: request.instruction, scope: context.scope, context });
              },
              cancel: (proposalId) => call('edits.cancel', { proposalId }),
              decide: (proposalId, decision) => call('edits.decide', { proposalId, decision }),
              subscribe: (listener) => subscribe('edits.event', listener)
            },
            window: {
              setDirty: (dirty) => { void call('window.setDirty', { dirty }); },
              loadState: () => call('window.loadState'),
              saveState: (state) => call('window.saveState', state),
              closeIde: () => call('window.closeIde')
            }
          }};
          return true;
        })()
        """
    }

    public static func javaScriptLiteral(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private static func composerInsertion(prompt: String, requireQuickChat: Bool) -> String {
        let promptLiteral = javaScriptLiteral(prompt)
        let quickChatRequirement = requireQuickChat ? "true" : "false"
        return """
        (() => {
          const prompt = \(promptLiteral);
          const requireQuickChat = \(quickChatRequirement);
          const visible = (element) => !!element && element.getClientRects().length > 0
            && getComputedStyle(element).visibility !== 'hidden';
          let composer = null;
          if (requireQuickChat) {
            const routeMatch = /(?:quick[-_/ ]?chat|chatgpt)/i.test(location.pathname + location.search + location.hash);
            const quickChatCandidates = [...document.querySelectorAll(
              'form[data-thread-find-composer="true"] .composer-surface-chrome [contenteditable="true"][aria-label="Message ChatGPT"]'
            )].filter((element) => visible(element) && !element.hasAttribute('data-codex-composer'));
            const focused = document.activeElement;
            composer = quickChatCandidates.includes(focused)
              ? focused
              : routeMatch && quickChatCandidates.length === 1
                ? quickChatCandidates[0]
                : null;
            if (!composer) return { ok: false, reason: 'quick_chat_composer_not_focused' };
          } else {
            composer = document.querySelector('.composer-surface-chrome [contenteditable="true"][data-codex-composer="true"]')
              || document.querySelector('[data-testid*="composer"] [contenteditable="true"]')
              || document.querySelector('[role="textbox"][contenteditable="true"]')
              || document.querySelector('textarea');
          }
          if (!composer || !visible(composer)) return { ok: false, reason: 'composer_not_found' };
          const existing = composer instanceof HTMLTextAreaElement ? composer.value : (composer.innerText || '');
          const requestLabel = requireQuickChat ? 'My request for ChatGPT' : 'My request for Codex';
          const value = existing.trim() ? `${prompt}\n\n## ${requestLabel}:\n${existing}` : prompt;
          composer.focus();
          if (composer instanceof HTMLTextAreaElement) {
            const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')?.set;
            setter?.call(composer, value);
          } else {
            const selection = getSelection();
            const range = document.createRange();
            range.selectNodeContents(composer);
            selection?.removeAllRanges();
            selection?.addRange(range);
            if (!document.execCommand('insertText', false, value)) composer.textContent = value;
          }
          composer.dispatchEvent(new InputEvent('beforeinput', { bubbles: true, inputType: 'insertText', data: value }));
          composer.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: value }));
          return { ok: true };
        })()
        """
    }
}

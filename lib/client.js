window.__ModuleLoader__.load({
	id: "dsh-undo",
	factory: (require) => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
		let react = require("react");
		let react_jsx_runtime = require("react/jsx-runtime");
		//#region dsh-undo styles
		const css = ".u_actions{display:flex;align-items:center;gap:4px;padding:0 2px}.u_btn{cursor:pointer;border:1px solid var(--dsw-alias-border-l1, rgba(128,128,128,.35));background:var(--dsw-specific-tip, transparent);color:var(--dsw-alias-label-secondary, inherit);border-radius:8px;height:24px;padding:0 9px;font-size:12px;line-height:22px;display:inline-flex;align-items:center;gap:3px;white-space:nowrap}.u_btn:hover{background:var(--dsw-alias-interactive-bg-hover, rgba(128,128,128,.15));color:var(--dsw-alias-label-primary, inherit)}.u_btn:disabled{opacity:.4;cursor:default}.u_undo{color:#e5484d;border-color:rgba(229,72,77,.45)}.u_undo:hover{background:rgba(229,72,77,.12);color:#e5484d}.u_redo{color:#30a46c;border-color:rgba(48,164,108,.45)}.u_redo:hover{background:rgba(48,164,108,.12);color:#30a46c}.u_msg{max-width:min(280px,40vw);font-size:12px;line-height:18px;white-space:nowrap;text-overflow:ellipsis;overflow:hidden;padding:0 6px}.u_ok{color:var(--dsw-alias-label-tertiary, #888)}.u_err{color:var(--dsw-state-error-primary, #d9534f)}.u_row{display:flex;align-items:center;gap:8px;flex-wrap:wrap;width:100%;padding:10px 16px;box-sizing:border-box}.u_keyLabel{color:var(--dsw-alias-label-primary, inherit);font-size:13px;flex:none}.u_keyInput{width:110px;height:28px;border:1px solid var(--dsw-alias-border-l2, rgba(128,128,128,.4));background:var(--dsw-alias-bg-base, transparent);color:var(--dsw-alias-label-primary, inherit);border-radius:6px;outline:none;padding:0 8px;font-size:12px;box-sizing:border-box}.u_keyInput:focus{border-color:var(--dsw-state-business-primary, #4a90d9)}.u_hint{color:var(--dsw-alias-label-tertiary, #888);font-size:12px;flex:none}";
		const tagId = "dsh-undo/undo.module.css";
		if (typeof document !== "undefined" && document.querySelector("style[data-plugin-css=" + JSON.stringify(tagId) + "]") === null) {
			const tag = document.createElement("style");
			tag.dataset.plugin = "dsh-undo";
			tag.dataset.pluginCss = tagId;
			tag.textContent = css;
			document.head.appendChild(tag);
		}
		var styles = { actions: "u_actions", btn: "u_btn", undo: "u_undo", redo: "u_redo", msg: "u_msg", ok: "u_ok", err: "u_err", row: "u_row", keyLabel: "u_keyLabel", keyInput: "u_keyInput", hint: "u_hint" };
		//#endregion
		//#region locales
		const NS = "undo";
		const zh = {
			"undo": "撤销",
			"redo": "恢复",
			"undo.aria": "撤销上一步(回退最近一次配置变更)",
			"redo.aria": "恢复(重做上一次撤销)",
			"ok.undo": "已撤销 → {id}",
			"ok.redo": "已恢复",
			"ok.snapshot": "已存档 {id}",
			"err": "失败:{msg}",
			"busy": "处理中…",
			"keys.undo": "撤销快捷键",
			"keys.redo": "恢复快捷键",
			"keys.none": "(未设置)",
			"keys.press": "请按组合键…",
			"keys.hint": "点击输入框后按下组合键;Backspace 清除;默认 Ctrl+Alt+Z / Ctrl+Alt+Y"
		};
		const en = {
			"undo": "Undo",
			"redo": "Redo",
			"undo.aria": "Undo the last config change",
			"redo.aria": "Redo the last undone change",
			"ok.undo": "Undone → {id}",
			"ok.redo": "Redone",
			"ok.snapshot": "Snapshot {id}",
			"err": "Failed: {msg}",
			"busy": "Working…",
			"keys.undo": "Undo shortcut",
			"keys.redo": "Redo shortcut",
			"keys.none": "(unset)",
			"keys.press": "Press keys…",
			"keys.hint": "Click the box then press a combo; Backspace clears; defaults Ctrl+Alt+Z / Ctrl+Alt+Y"
		};
		//#endregion
		//#region keyboard config (localStorage; shared with the settings row)
		const KEY_STORAGE = "dsh-undo-keys";
		const DEFAULT_KEYS = {
			undo: { ctrl: true, alt: true, shift: false, key: "z" },
			redo: { ctrl: true, alt: true, shift: false, key: "y" }
		};
		function loadKeys() {
			try {
				const raw = localStorage.getItem(KEY_STORAGE);
				if (raw) {
					const j = JSON.parse(raw);
					return {
						undo: j && j.undo ? j.undo : DEFAULT_KEYS.undo,
						redo: j && j.redo ? j.redo : DEFAULT_KEYS.redo
					};
				}
			} catch (e) { /* fall through */ }
			return { undo: DEFAULT_KEYS.undo, redo: DEFAULT_KEYS.redo };
		}
		function saveKeys(keys) {
			try { localStorage.setItem(KEY_STORAGE, JSON.stringify(keys)); } catch (e) { /* ignore */ }
		}
		function formatKey(k) {
			if (!k || !k.key) return "";
			return [k.ctrl ? "Ctrl" : null, k.alt ? "Alt" : null, k.shift ? "Shift" : null, String(k.key).toUpperCase()].filter(Boolean).join("+");
		}
		function keyEventMatches(e, k) {
			if (!k || !k.key) return false;
			return !!e.ctrlKey === !!k.ctrl && !!e.altKey === !!k.alt && !!e.shiftKey === !!k.shift
				&& e.key.toLowerCase() === String(k.key).toLowerCase();
		}
		function fire(path) {
			return fetch(path, { method: "POST" }).then((r) => r.json()).catch((e) => ({ ok: false, error: { message: String(e && e.message || e) } }));
		}
		const RESULT_EVENT = "dsh-undo-result";
		function publishResult(r, label) {
			let text = "";
			if (r && r.ok) {
				const id = r.targetId || (r.snapshot && r.snapshot.id) || "";
				text = label === "undo" ? (id ? "已撤销 → " + id : "已撤销") : "已恢复";
			} else {
				text = "失败:" + ((r && (r.error && (r.error.message || r.error) || r)) || "unknown");
			}
			try { window.dispatchEvent(new CustomEvent(RESULT_EVENT, { detail: { ok: !!(r && r.ok), text } })); } catch (e) { /* noop */ }
		}
		//#endregion
		//#region UndoHeader (session header actions)
		/**
		 * Undo/redo buttons in the conversation header (conversation.session.header.actions).
		 * Also surfaces results triggered by global keyboard shortcuts.
		 */
		function UndoHeader({ t }) {
			const [busy, setBusy] = (0, react.useState)(false);
			const [msg, setMsg] = (0, react.useState)(null);
			const [msgOk, setMsgOk] = (0, react.useState)(true);
			const timer = (0, react.useRef)(null);
			const keys = loadKeys();
			const flash = (ok, text) => {
				setMsg(text);
				setMsgOk(ok);
				if (timer.current) clearTimeout(timer.current);
				timer.current = setTimeout(() => setMsg(null), 6000);
			};
			const run = async (label, path) => {
				if (busy) return;
				setBusy(true);
				try {
					const r = await fire(path);
					publishResult(r, label);
					flash(!!(r && r.ok), (r && r.ok) ? (label === "undo" ? t("ok.undo", { id: r.targetId || "" }) : t("ok.redo")) : t("err", { msg: (r && (r.error && (r.error.message || r.error))) || "unknown" }));
				} finally {
					setBusy(false);
				}
			};
			(0, react.useEffect)(() => {
				const onResult = (ev) => {
					const d = ev && ev.detail;
					if (!d) return;
					flash(d.ok, d.text);
				};
				window.addEventListener(RESULT_EVENT, onResult);
				return () => {
					window.removeEventListener(RESULT_EVENT, onResult);
					if (timer.current) clearTimeout(timer.current);
				};
			}, []);
			return (0, react_jsx_runtime.jsx)("div", {
				className: styles.actions,
				"data-undo-header": true,
				children: [
					(0, react_jsx_runtime.jsx)("button", {
						type: "button",
						className: styles.btn + " " + styles.undo,
						disabled: busy,
						title: t("undo.aria") + (keys.undo ? " (" + formatKey(keys.undo) + ")" : ""),
						"aria-label": t("undo.aria"),
						onClick: () => { run("undo", "/api/undo/undo"); },
						children: t("undo")
					}),
					(0, react_jsx_runtime.jsx)("button", {
						type: "button",
						className: styles.btn + " " + styles.redo,
						disabled: busy,
						title: t("redo.aria") + (keys.redo ? " (" + formatKey(keys.redo) + ")" : ""),
						"aria-label": t("redo.aria"),
						onClick: () => { run("redo", "/api/undo/redo"); },
						children: t("redo")
					}),
					msg !== null && (0, react_jsx_runtime.jsx)("span", {
						className: styles.msg + " " + (msgOk ? styles.ok : styles.err),
						children: msg
					})
				]
			});
		}
		//#endregion
		//#region KeyBindRow (settings.general.item)
		/**
		 * Custom shortcut settings row: capture combos for undo/redo.
		 * Persisted in localStorage so it works without touching host config.
		 */
		function KeyBindRow({ t }) {
			const [keys, setKeysState] = (0, react.useState)(loadKeys);
			const [capturing, setCapturing] = (0, react.useState)(null);
			const capture = (which) => (e) => {
				e.preventDefault();
				e.stopPropagation();
				if (e.key === "Backspace" || e.key === "Delete") {
					const next = { ...keys, [which]: null };
					setKeysState(next);
					saveKeys(next);
					setCapturing(null);
					return;
				}
				if (["Control", "Alt", "Shift", "Meta", "Escape", "Tab", "CapsLock"].indexOf(e.key) >= 0) return;
				const next = { ...keys, [which]: { ctrl: !!e.ctrlKey, alt: !!e.altKey, shift: !!e.shiftKey, key: e.key } };
				setKeysState(next);
				saveKeys(next);
				setCapturing(null);
			};
			const bind = (which) => {
				const cur = keys[which];
				return (0, react_jsx_runtime.jsx)("input", {
					type: "text",
					readOnly: true,
					className: styles.keyInput,
					"data-undo-key-input": "1",
					placeholder: cur ? formatKey(cur) : t("keys.none"),
					value: capturing === which ? t("keys.press") : (cur ? formatKey(cur) : ""),
					onFocus: () => { setCapturing(which); },
					onBlur: () => { setCapturing(null); },
					onKeyDown: capture(which),
					"aria-label": t(which === "undo" ? "keys.undo" : "keys.redo")
				});
			};
			return (0, react_jsx_runtime.jsx)("div", {
				className: styles.row,
				"data-undo-keys": true,
				children: [
					(0, react_jsx_runtime.jsx)("span", { className: styles.keyLabel, children: t("keys.undo") }),
					bind("undo"),
					(0, react_jsx_runtime.jsx)("span", { className: styles.keyLabel, children: t("keys.redo") }),
					bind("redo"),
					(0, react_jsx_runtime.jsx)("span", { className: styles.hint, children: t("keys.hint") })
				]
			});
		}
		//#endregion
		//#region client entry
		const inject = ["slots", "locale"];
		function apply(ctx) {
			ctx.effect(() => ctx.locale.register(NS, { zh, en }), "dsh-undo: dictionaries");
			// Undo/redo buttons in the conversation header
			ctx.slots.inject("conversation.session.header.actions", () => ctx.slots.register({
				name: "conversation.session.header.actions",
				id: "undo-buttons",
				order: 10,
				locale: NS
			}, UndoHeader));
			// Custom shortcut settings row (General settings)
			ctx.slots.inject("settings.general.item", () => ctx.slots.register({
				name: "settings.general.item",
				id: "undo-keys",
				order: 30,
				locale: NS
			}, KeyBindRow));
			// Global keyboard shortcuts
			ctx.effect(() => {
				const onKeyDown = (e) => {
					if (e.defaultPrevented || e.repeat) return;
					const target = e.target;
					if (target && target.dataset && target.dataset.undoKeyInput === "1") return; // the settings inputs themselves
					const keys = loadKeys();
					if (keys.undo && keyEventMatches(e, keys.undo)) {
						e.preventDefault();
						fire("/api/undo/undo").then((r) => publishResult(r, "undo"));
						return;
					}
					if (keys.redo && keyEventMatches(e, keys.redo)) {
						e.preventDefault();
						fire("/api/undo/redo").then((r) => publishResult(r, "redo"));
					}
				};
				window.addEventListener("keydown", onKeyDown, true);
				return () => window.removeEventListener("keydown", onKeyDown, true);
			}, "dsh-undo: keyboard");
		}
		//#endregion
		exports.UndoHeader = UndoHeader;
		exports.KeyBindRow = KeyBindRow;
		exports.apply = apply;
		exports.inject = inject;
		return module.exports;
	}
});

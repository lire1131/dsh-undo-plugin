// 用途：dsh-undo-savepoint 插件 host 端最小零依赖多语言模块。
// 唯一词典源：lib/i18n/{zh,en}.json（与 WebUI/CLI 共用同一份数据，防双实现漂移）。
// 查找链（与规划文档一致）：active 词典 → en 兜底 → key 原样返回（缺失文案不空白）。
// 语言优先级：DSH_UNDO_LANG > 系统语言（中文系统→zh，其他→en）> en 兜底。
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const zh = JSON.parse(
  readFileSync(fileURLToPath(new URL('./i18n/zh.json', import.meta.url)), 'utf8'),
);
const en = JSON.parse(
  readFileSync(fileURLToPath(new URL('./i18n/en.json', import.meta.url)), 'utf8'),
);
const dicts = { zh, en };

// 把任意区域/语言标记归一化为插件支持的 'zh' | 'en'；其他一律作为未识别的原始值，
// 但 t() 里会用 en 兜底（规划要求：默认兜底 en，非中文母语用户不会被中文界面卡住）。
function normalize(lang) {
  const l = String(lang || '').trim().toLowerCase();
  if (l.startsWith('zh')) return 'zh';
  if (l.startsWith('en')) return 'en';
  return l || 'en';
}

// 探测当前宿主运行的语言：DSH_UNDO_LANG 强制覆盖 > 系统区域（Intl + 环境变量）> en 兜底。
export function currentLang() {
  if (process.env.DSH_UNDO_LANG) return normalize(process.env.DSH_UNDO_LANG);
  try {
    const loc = Intl.DateTimeFormat().resolvedOptions().locale || '';
    if (/^zh/i.test(loc)) return 'zh';
  } catch { /* 区域不可用时忽略，继续走环境变量 */ }
  const envLang = process.env.LC_ALL || process.env.LC_MESSAGES || process.env.LANG || '';
  if (/^zh/i.test(envLang)) return 'zh';
  return 'en';
}

// 零依赖翻译：t(key, vars?, lang?) -> string。
// vars 形如 { id: 'abc' }，会替换文案里的 {id} 占位符。
export function t(key, vars, lang) {
  const want = normalize(lang || currentLang());
  const dict = dicts[want] || dicts.en;
  let val = dict[key];
  if (val == null) val = en[key];
  if (val == null) val = key;
  if (vars) {
    for (const [k, v] of Object.entries(vars)) {
      val = val.replace(new RegExp(`\\{${k}\\}`, 'g'), String(v));
    }
  }
  return val;
}

export { zh, en, dicts };

/** 使用者設定：長輩/一般模式、語言、引擎。存在 localStorage，服務頁的 overlay 也會讀（同源） */
export type Mode = 'kid' | 'normal' | 'elder';
export type EngineKind = 'auto' | 'llm' | 'llm-phone' | 'cls' | 'embed' | 'tiny';

const K = {
  mode: 'tp_assistant_mode',
  lang: 'tp_assistant_lang',
  engine: 'tp_assistant_engine',
  llmUrl: 'tp_assistant_llm_url'
};

function get(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}
function set(key: string, v: string | null) {
  try {
    if (v === null) localStorage.removeItem(key);
    else localStorage.setItem(key, v);
  } catch {
    /* ignore */
  }
}

export const settings = {
  get mode(): Mode | null {
    const v = get(K.mode);
    return v === 'elder' || v === 'normal' || v === 'kid' ? v : null;
  },
  set mode(v: Mode | null) {
    set(K.mode, v);
    applyMode(v ?? 'normal');
  },
  get lang(): string {
    return new URLSearchParams(location.search).get('lang') || get(K.lang) || 'zh';
  },
  set lang(v: string) {
    set(K.lang, v);
  },
  get engine(): EngineKind {
    const q = new URLSearchParams(location.search).get('engine');
    const v = q || get(K.engine) || 'auto';
    return (['auto', 'llm', 'llm-phone', 'cls', 'embed', 'tiny'].includes(v) ? v : 'auto') as EngineKind;
  },
  set engine(v: EngineKind) {
    set(K.engine, v);
  },
  /** LLM 網址：?llm=... > localStorage > VITE_LLM_URL > /llm */
  get llmUrl(): string {
    // 網址參數 / 存著的值只接受本機、區網或同源路徑：不讓一條連結把之後的查詢導到外部伺服器
    const q = new URLSearchParams(location.search).get('llm');
    const okQ = q && isLocalLlmUrl(q) ? q : '';
    if (okQ) set(K.llmUrl, okQ);
    const stored = get(K.llmUrl);
    return okQ || (stored && isLocalLlmUrl(stored) ? stored : '') || (window as any).__TP_LLM_URL__ || (import.meta as any).env?.VITE_LLM_URL || '/llm';
  },
  set llmUrl(v: string) {
    if (isLocalLlmUrl(v)) set(K.llmUrl, v);
  }
};

export function applyMode(mode: Mode) {
  document.documentElement.dataset.mode = mode;
}

/** 本機（localhost / 127.x / ::1）、區網私有位址（10.x、172.16–31.x、192.168.x、*.local）或同源路徑（/llm） */
export function isLocalLlmUrl(u: string): boolean {
  // 空白、控制字元、反斜線一律不收：URL 解析會吃掉它們（例如 "/\t/evil.com" 會變成 "//evil.com"）
  if (!u || /[\s\\\u0000-\u001f\u007f]/.test(u)) return false;
  if (u.startsWith('/')) {
    // 同源路徑：解析後主機必須沒變（擋掉 //evil.com 這類協定相對網址）
    try {
      return new URL(u, 'http://same-origin.invalid/').hostname === 'same-origin.invalid';
    } catch {
      return false;
    }
  }
  let h = '';
  try {
    const url = new URL(u);
    if (!/^https?:$/.test(url.protocol)) return false;
    h = url.hostname.replace(/^\[|\]$/g, '');
  } catch {
    return false;
  }
  if (h === 'localhost' || h === '::1' || /\.local$/.test(h)) return true;
  const m = h.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (!m) return false;
  const [a, b] = [Number(m[1]), Number(m[2])];
  return a === 127 || a === 10 || (a === 192 && b === 168) || (a === 172 && b >= 16 && b <= 31);
}

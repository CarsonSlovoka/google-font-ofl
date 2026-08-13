/**
 * Google Fonts OFL upstream GitHub browser
 * - data.json
 * - search / language / recent activity / workflows filters
 * - sort / pagination
 * - pin cards + workflow / issue-template links
 */

(function () {
  "use strict";

  const STATS_BASE = "https://github-readme-stats-fast.vercel.app/api/pin";
  const THEME_LIGHT = "default";
  const THEME_DARK = "dark";

  const state = {
    items: [],
    filtered: [],
    page: 1,
    perPage: 24,
    sort: "pushed-desc",
    query: "",
    language: "",
    recentDays: 0,
    onlyWorkflows: false,
    onlyIssueTemplates: false,
    meta: { success: 0, fail: 0, generated_at: "" },
  };

  const $ = (sel) => document.querySelector(sel);
  const grid = $("#grid");
  const searchEl = $("#search");
  const sortEl = $("#sort");
  const perPageEl = $("#per-page");
  const languageEl = $("#language");
  const recentEl = $("#recent");
  const hasWfEl = $("#has-workflows");
  const hasItEl = $("#has-issue-templates");
  const resultCount = $("#result-count");
  const pagination = $("#pagination");

  function prefersDark() {
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  }

  function pinUrl(item) {
    const theme = prefersDark() ? THEME_DARK : THEME_LIGHT;
    const params = new URLSearchParams({
      username: item.username,
      repo: item.repo_name,
      theme,
      show_owner: "true",
      hide_border: "true",
    });
    return `${STATS_BASE}?${params.toString()}`;
  }

  function normalize(s) {
    return (s || "").toString().toLowerCase();
  }

  function parseDate(iso) {
    if (!iso) return 0;
    const t = Date.parse(iso);
    return Number.isFinite(t) ? t : 0;
  }

  function relativeTime(iso) {
    const t = parseDate(iso);
    if (!t) return "—";
    const diff = Date.now() - t;
    const sec = Math.floor(diff / 1000);
    if (sec < 60) return "剛剛";
    const min = Math.floor(sec / 60);
    if (min < 60) return `${min} 分鐘前`;
    const hr = Math.floor(min / 60);
    if (hr < 48) return `${hr} 小時前`;
    const day = Math.floor(hr / 24);
    if (day < 60) return `${day} 天前`;
    const mon = Math.floor(day / 30);
    if (mon < 24) return `${mon} 個月前`;
    return `${Math.floor(day / 365)} 年前`;
  }

  function applyFilterAndSort() {
    const q = normalize(state.query);
    const lang = state.language;
    const recentMs = state.recentDays > 0 ? state.recentDays * 86400000 : 0;
    const now = Date.now();

    let list = state.items.slice();

    if (q) {
      list = list.filter((it) => {
        return (
          normalize(it.dirname).includes(q) ||
          normalize(it.username).includes(q) ||
          normalize(it.repo_name).includes(q) ||
          normalize(it.url).includes(q) ||
          normalize(it.description).includes(q)
        );
      });
    }

    if (lang) {
      list = list.filter((it) => (it.language || "") === lang);
    }

    if (recentMs > 0) {
      list = list.filter((it) => {
        const t = parseDate(it.pushed_at);
        return t > 0 && now - t <= recentMs;
      });
    }

    if (state.onlyWorkflows) {
      list = list.filter((it) => Array.isArray(it.workflows) && it.workflows.length > 0);
    }

    if (state.onlyIssueTemplates) {
      list = list.filter(
        (it) => Array.isArray(it.issue_templates) && it.issue_templates.length > 0
      );
    }

    const [key, dir] = state.sort.split("-");
    list.sort((a, b) => {
      let av, bv;
      if (key === "name") {
        av = normalize(a.dirname);
        bv = normalize(b.dirname);
      } else if (key === "repo") {
        av = normalize(a.repo_name);
        bv = normalize(b.repo_name);
      } else if (key === "stars") {
        av = a.stars ?? -1;
        bv = b.stars ?? -1;
      } else if (key === "forks") {
        av = a.forks ?? -1;
        bv = b.forks ?? -1;
      } else if (key === "pushed") {
        av = parseDate(a.pushed_at);
        bv = parseDate(b.pushed_at);
      } else {
        av = normalize(a.dirname);
        bv = normalize(b.dirname);
      }
      if (av < bv) return dir === "asc" ? -1 : 1;
      if (av > bv) return dir === "asc" ? 1 : -1;
      return normalize(a.dirname).localeCompare(normalize(b.dirname));
    });

    state.filtered = list;
    state.page = 1;
    render();
  }

  function pageSlice() {
    if (state.perPage === 0) return state.filtered;
    const start = (state.page - 1) * state.perPage;
    return state.filtered.slice(start, start + state.perPage);
  }

  function totalPages() {
    if (state.perPage === 0) return 1;
    return Math.max(1, Math.ceil(state.filtered.length / state.perPage));
  }

  function formatNum(n) {
    if (n == null || n < 0) return "—";
    if (n >= 1000) return (n / 1000).toFixed(n >= 10000 ? 0 : 1).replace(/\.0$/, "") + "k";
    return String(n);
  }

  function renderFileLinks(files, label) {
    if (!files || !files.length) return "";
    const max = 4;
    const shown = files.slice(0, max);
    const more = files.length - shown.length;
    const links = shown
      .map(
        (f) =>
          `<a class="file-link" href="${escapeAttr(f.url)}" target="_blank" rel="noopener noreferrer" title="${escapeAttr(f.path)}">${escapeHtml(f.name)}</a>`
      )
      .join("");
    const extra = more > 0 ? `<span class="file-more">+${more}</span>` : "";
    return `<div class="file-row"><span class="file-label">${label}</span>${links}${extra}</div>`;
  }

  function renderCard(item) {
    const card = document.createElement("article");
    card.className = "card";

    const title = document.createElement("div");
    title.className = "card-header";
    title.innerHTML = `
      <h2 class="card-title">
        <a href="${escapeAttr(item.url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(item.dirname)}</a>
      </h2>
      <p class="card-sub">
        <a href="${escapeAttr(item.url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(item.username)}/${escapeHtml(item.repo_name)}</a>
      </p>
    `;

    const stats = document.createElement("div");
    stats.className = "card-stats";
    const img = document.createElement("img");
    img.src = pinUrl(item);
    img.alt = `${item.username}/${item.repo_name} stats`;
    img.loading = "lazy";
    img.decoding = "async";
    img.width = 400;
    img.height = 120;
    img.onerror = () => {
      img.replaceWith(
        Object.assign(document.createElement("div"), {
          className: "pill",
          textContent: "stats 載入失敗",
        })
      );
    };
    stats.appendChild(img);

    const meta = document.createElement("div");
    meta.className = "card-meta-row";
    const parts = [];
    if (item.stars != null && item.stars >= 0) {
      parts.push(`<span title="Stars">⭐ ${formatNum(item.stars)}</span>`);
      parts.push(`<span title="Forks">🍴 ${formatNum(item.forks)}</span>`);
    }
    if (item.language) {
      parts.push(`<span class="pill">${escapeHtml(item.language)}</span>`);
    }
    if (item.pushed_at) {
      parts.push(
        `<span title="Last push: ${escapeAttr(item.pushed_at)}">🕐 ${relativeTime(item.pushed_at)}</span>`
      );
    }
    meta.innerHTML = parts.join("") || `<span class="pill">點卡片看 GitHub 統計</span>`;

    const filesBlock = document.createElement("div");
    filesBlock.className = "card-files";
    filesBlock.innerHTML =
      renderFileLinks(item.workflows, "Actions") +
      renderFileLinks(item.issue_templates, "Issue templates");

    card.appendChild(title);
    card.appendChild(stats);
    card.appendChild(meta);
    if (filesBlock.innerHTML.trim()) card.appendChild(filesBlock);
    return card;
  }

  function renderPagination() {
    pagination.innerHTML = "";
    const pages = totalPages();
    if (pages <= 1 || state.perPage === 0) return;

    const addBtn = (label, page, disabled, active) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = label;
      btn.disabled = disabled;
      if (active) btn.classList.add("active");
      btn.addEventListener("click", () => {
        state.page = page;
        render();
        window.scrollTo({ top: 0, behavior: "smooth" });
      });
      pagination.appendChild(btn);
    };

    addBtn("«", Math.max(1, state.page - 1), state.page === 1, false);

    const windowSize = 5;
    let start = Math.max(1, state.page - Math.floor(windowSize / 2));
    let end = Math.min(pages, start + windowSize - 1);
    start = Math.max(1, end - windowSize + 1);

    if (start > 1) {
      addBtn("1", 1, false, false);
      if (start > 2) {
        const dots = document.createElement("span");
        dots.textContent = "…";
        dots.style.padding = "0 0.25rem";
        pagination.appendChild(dots);
      }
    }
    for (let p = start; p <= end; p++) {
      addBtn(String(p), p, false, p === state.page);
    }
    if (end < pages) {
      if (end < pages - 1) {
        const dots = document.createElement("span");
        dots.textContent = "…";
        dots.style.padding = "0 0.25rem";
        pagination.appendChild(dots);
      }
      addBtn(String(pages), pages, false, false);
    }

    addBtn("»", Math.min(pages, state.page + 1), state.page === pages, false);
  }

  function render() {
    const slice = pageSlice();
    grid.innerHTML = "";

    if (slice.length === 0) {
      grid.innerHTML = `<div class="empty-state">沒有符合條件的項目</div>`;
    } else {
      const frag = document.createDocumentFragment();
      for (const item of slice) {
        frag.appendChild(renderCard(item));
      }
      grid.appendChild(frag);
    }

    const total = state.filtered.length;
    const from = total === 0 ? 0 : (state.page - 1) * (state.perPage || total) + 1;
    const to = state.perPage === 0 ? total : Math.min(total, state.page * state.perPage);
    resultCount.textContent = total
      ? `顯示 ${from}–${to} / 共 ${total} 筆（全部 ${state.items.length}）`
      : `共 0 筆（全部 ${state.items.length}）`;

    renderPagination();
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function escapeAttr(s) {
    return escapeHtml(s).replace(/'/g, "&#39;");
  }

  function updateBadges() {
    $("#badge-ok").textContent = `成功：${state.meta.success}`;
    $("#badge-fail").textContent = `找不到：${state.meta.fail}`;
    $("#badge-time").textContent = `產生時間：${state.meta.generated_at || "—"}`;
  }

  function fillLanguageOptions(items) {
    const counts = new Map();
    for (const it of items) {
      const lang = it.language || "";
      if (!lang) continue;
      counts.set(lang, (counts.get(lang) || 0) + 1);
    }
    const langs = [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
    languageEl.innerHTML = `<option value="">全部語言</option>`;
    for (const [lang, n] of langs) {
      const opt = document.createElement("option");
      opt.value = lang;
      opt.textContent = `${lang} (${n})`;
      languageEl.appendChild(opt);
    }
  }

  async function loadData() {
    try {
      const res = await fetch("data.json", { cache: "no-cache" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();

      state.items = Array.isArray(data.items) ? data.items : [];
      for (const it of state.items) {
        if (typeof it.stars !== "number") it.stars = -1;
        if (typeof it.forks !== "number") it.forks = -1;
        if (!Array.isArray(it.workflows)) it.workflows = [];
        if (!Array.isArray(it.issue_templates)) it.issue_templates = [];
      }
      state.meta = {
        success: data.success_count ?? state.items.length,
        fail: data.fail_count ?? 0,
        generated_at: data.generated_at || "",
      };
      updateBadges();
      fillLanguageOptions(state.items);
      applyFilterAndSort();
    } catch (err) {
      console.error(err);
      grid.innerHTML = `<div class="empty-state">無法載入 data.json：${escapeHtml(err.message)}</div>`;
      resultCount.textContent = "載入失敗";
    }

    try {
      const r = await fetch("no_found.md", { cache: "no-cache" });
      if (r.ok) {
        const text = await r.text();
        if (text.trim()) {
          $("#missing-section").hidden = false;
          $("#missing-list").textContent = text;
        }
      }
    } catch (_) {
      /* ignore */
    }
  }

  let searchTimer;
  searchEl.addEventListener("input", () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => {
      state.query = searchEl.value.trim();
      applyFilterAndSort();
    }, 180);
  });

  sortEl.addEventListener("change", () => {
    state.sort = sortEl.value;
    applyFilterAndSort();
  });

  perPageEl.addEventListener("change", () => {
    state.perPage = Number(perPageEl.value);
    state.page = 1;
    render();
  });

  languageEl.addEventListener("change", () => {
    state.language = languageEl.value;
    applyFilterAndSort();
  });

  recentEl.addEventListener("change", () => {
    state.recentDays = Number(recentEl.value) || 0;
    applyFilterAndSort();
  });

  hasWfEl.addEventListener("change", () => {
    state.onlyWorkflows = hasWfEl.checked;
    applyFilterAndSort();
  });

  hasItEl.addEventListener("change", () => {
    state.onlyIssueTemplates = hasItEl.checked;
    applyFilterAndSort();
  });

  if (window.matchMedia) {
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
      render();
    });
  }

  loadData();
})();

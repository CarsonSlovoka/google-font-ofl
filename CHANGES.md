# CHANGES

## 2026-08-17 — v2 Tree enrich + sources/*.glyphs 篩選

### 目標

在不改動原有 `enrich_github_data.py` 與 v1 頁面行為的前提下，支援偵測 upstream 是否有：

- `sources/*.glyphs`（檔案）
- `sources/*.glyphspackage`（目錄）

### 新增

1. **`scripts/enrich_github_data_tree.py`**（v2 enricher）
   - 優先使用 Git Trees API（`recursive=1`）一次取得 workflows / issue templates / sources
   - 若 tree `truncated` 或失敗 → Contents API fallback
   - 新欄位：`has_glyphs` / `has_glyphspackage` / `glyphs_sources` / `glyphspackage_sources` / `tree_method`
   - 原版 `enrich_github_data.py` **完全保留、不修改**

2. **`site/v2/` 頁面**
   - 獨立前端，不影響 v1
   - 新增篩選：
     - 僅顯示有 `sources/*.glyphs`
     - 僅顯示有 `sources/*.glyphspackage`
     - 有 Glyphs source（兩者任一）
   - 卡片顯示 source badge 與檔名連結

3. **文件**
   - README 補上 v2 用法與 API 成本
   - v1 `index.html` 加上連到 v2 的入口

### API 成本（約 1,279 unique）

| 路徑 | 每 repo | 總計（約） |
|------|---------|------------|
| Tree 成功 | 2 | ~2,558 |
| truncated → fallback | 2 + 最多 3 Contents | 少數 repo 較高 |

仍低於 GitHub authenticated 5,000/hr 主上限

### 不相容說明

v2 data 多了新欄位；v1 前端不認識這些欄位也無妨（會忽略）。
為避免混用，v2 使用獨立頁面與 `site/v2/data.json`。

---

## 2026-08-13 — 篩選強化 + Python 抽離 + 近期異動 + Actions 連結

### 需求

1. **py 腳本從 Action 抽離**
   - 新增 `scripts/enrich_github_data.py`
   - Workflow 改為：`python3 scripts/enrich_github_data.py data.json --with-workflows`
   - 可本機獨立執行、方便維護與測試

2. **Language 篩選**
   - 前端下拉選單列出所有出現過的 language（附數量）
   - 依 `item.language` 過濾

3. **近期異動**
   - Enrich 時一併寫入 GitHub API 的 `pushed_at` / `updated_at` / `created_at`
   - 預設排序改為「🕐 最近 push」
   - 篩選：最近 7 / 30 / 90 / 365 天有 push
   - 卡片顯示相對時間（例如「12 天前」）

4. **顯示 GitHub Actions / Issue Template**
   - `--with-workflows` 會對每個 unique repo 查：
     - `.github/workflows/*.yml`
     - `.github/ISSUE_TEMPLATE/*.{yml,yaml}`
   - 卡片底部以連結列出檔名（最多顯示 4 個 +N）
   - 可勾選「僅顯示有 GitHub Actions」「僅顯示有 Issue Template」
   - 沒有的 repo 不顯示該區塊（多數專案確實沒有）

### API 成本說明

- 每個 unique repo：1 次 repo metadata +（可選）2 次 contents
- 使用 `GITHUB_TOKEN`，rate limit 約 5000/hr，一般 OFL unique repos 數量可接受
- 若 CI 過久，可拿掉 workflow 裡的 `--with-workflows`

### 其他

- sample `site/data.json` 更新欄位方便本機預覽


## 2026-08-12 — GitHub Pages 重構

### 問題

- `generate-github-pages.yml` 把整段 HTML 寫死在 workflow 裡，難以維護
- 頁面只是把 markdown dump 進 `<pre>`，連結無法點、外觀簡陋
- 沒有搜尋 / 排序 / 分頁
- 無法直接看到各 upstream repo 的 stars / forks / language

### 修改

1. **樣板外移**
   - 新增 `site/index.html`
   - 新增 `site/css/style.css`
   - 新增 `site/js/app.js`
   - Workflow 只負責 `cp -a site/. _site/`，不再內嵌 HTML

2. **掃描器**
   - `scripts/find_github_page.lua` 除了寫 `list.md`，也輸出結構化 `data.json`

3. **CI 豐富資料**
   - 用 `GITHUB_TOKEN` 呼叫 GitHub API，為每個 unique repo 補上 `stars` / `forks` / `language`
   - 前端因此可以依 ⭐ 排序

4. **前端**
   - 每個 card 標題與 repo 都是真實 `<a href="https://github.com/...">`
   - 嵌入 `https://github-readme-stats-fast.vercel.app/api/pin?...` pin card
   - 搜尋、排序（名稱 / stars / forks）、分頁（12/24/48/96/全部）
   - 支援 light / dark（prefers-color-scheme）

5. **文件**
   - README 更新為新架構說明
   - `.gitignore` 加入 `data.json`、`_site/`

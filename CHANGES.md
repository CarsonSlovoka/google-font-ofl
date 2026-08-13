# CHANGES

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

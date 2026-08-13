# google font ofl

搜集所有google font ofl的資訊

使得能夠找到所有上架到google font它們的github主頁

## 功能

- 掃描 `google/fonts` 的 `ofl/**/{upstream_info.md,METADATA.pb,OFL.txt}`
- 抽出每個 family 的 GitHub `username/repo`
- 產生互動式頁面：
  - 每個項目都是真實可點的連結
  - 嵌入 [github-readme-stats-fast](https://github.com/pranesh-2005/github-readme-stats-fast) 的 **Repo Pin Card**（顯示 stars / forks / language 等）
  - 搜尋（family / username / repo）
  - 排序（名稱、⭐ stars、🍴 forks）
  - 分頁（12 / 24 / 48 / 96 / 全部）
- HTML / CSS / JS **樣板與 workflow 分離**，方便維護

## 目錄結構

```
.
├── .github/workflows/generate-github-pages.yml   # CI：掃描 → 豐富資料 → 部署 Pages
├── scripts/find_github_page.lua                  # 掃描器（輸出 list.md + data.json）
├── lua/utils.lua
├── site/                                         # ★ GitHub Pages 樣板（可獨立編輯）
│   ├── index.html
│   ├── css/style.css
│   └── js/app.js
├── ofl/                                          # 本機可放 sample；CI 會重新 sparse-checkout
└── pack.sh
```

## ofl目錄中的資料怎麼取得

大部份的專案從這幾個文件中，可以找到它們主頁的連結(其它的可能是連結非完整的http網址或者完全沒有提供)

- `upstream_info.md`
- `METADATA.pb`
- `OFL.txt`


```sh
# --shallow-since="2026-08-01"
git clone \
  --depth 1 \
  --no-checkout \
  --branch main \
  --single-branch \
  --filter=blob:none \
  --sparse \
  https://github.com/google/fonts.git ~/google-font-ofl

(
  cd ~/google-font-ofl
  git sparse-checkout set --no-cone \
      '/ofl/**/upstream_info.md' \
      '/ofl/**/METADATA.pb' \
      '/ofl/**/OFL.txt'
  git checkout
)

# 如果要資料有更新，可以考慮同步
# rsync -avn  ~/new/ofl/  ./ofl  # dry run
# rsync -a    ~/new/ofl/  ./ofl
```


## 本機用法 (Usage)

```sh
# 需要：fd (或 fdfind)、Neovim 0.9+
nvim -l scripts/find_github_page.lua 1>list.md 2>no_found.md
# 成功時會同時寫出 data.json
```

預覽頁面（需先有 data.json）：

```sh
# 簡單靜態伺服
python3 -m http.server 8080 --directory site
# 然後把 data.json / list.md / no_found.md 複製進 site/ 再開啟
```

# google font ofl

搜集所有google font ofl的資訊

使得能夠找到所有上架到google font它們的github主頁

## Demo

請參考:[github page](https://carsonslovoka.github.io/google-font-ofl/)

## 功能

- 掃描 `google/fonts` 的 `ofl/**/{upstream_info.md,METADATA.pb,OFL.txt}`
- 抽出每個 family 的 GitHub `username/repo`
- 產生互動式頁面：
  - 每個項目都是真實可點的連結
  - 嵌入 [github-readme-stats-fast](https://github.com/pranesh-2005/github-readme-stats-fast) Repo Pin Card
  - 搜尋（family / username / repo）
  - 排序：最近 push、⭐ stars、forks、名稱
  - **Language 篩選**
  - **近期異動**：最近 7 / 30 / 90 / 365 天有 push
  - **僅顯示有 GitHub Actions / Issue Template**
  - 卡片上列出 `.github/workflows/*.yml` 與 `ISSUE_TEMPLATE` 連結（若有）
  - 分頁（12 / 24 / 48 / 96 / 全部）
- **v2 頁面**（可選）：篩選 `sources/*.glyphs` / `sources/*.glyphspackage`
- HTML / CSS / JS 樣板與 workflow **分離**
- 豐富資料的 Python 腳本**獨立維護**（不寫在 YAML 裡）

## 目錄結構

```sh
.
├── .github/workflows/generate-github-pages.yml
├── scripts/
│   ├── find_github_page.lua             # 掃描 → list.md + data.json
│   ├── enrich_github_data.py            # v1：stars / language / pushed_at / workflows（Contents API）
│   └── enrich_github_data_tree.py       # v2：Tree API + Contents fallback + sources/*.glyphs
├── lua/utils.lua
├── site/                                # GitHub Pages 樣板
│   ├── index.html                       # v1 頁面
│   ├── css/style.css
│   ├── js/app.js
│   └── v2/                              # v2 頁面（sources 篩選）
│       ├── index.html
│       ├── js/app.js
│       └── data.json                    # tree enrich 產出
├── ofl/                                 # sample；CI 會重新 sparse-checkout
└── pack.sh
```

## 本機用法

```sh
# 1. 掃描（需要 fd + Neovim 0.9+）
nvim -l scripts/find_github_page.lua 1>list.md 2>no_found.md
# → 產生 data.json

# 2a. 豐富資料 v1（建議設 GH_TOKEN）
export GH_TOKEN=ghp_...   # 或 GITHUB_TOKEN: https://github.com/settings/personal-access-tokens
python3 scripts/enrich_github_data.py data.json --with-workflows
# python3 scripts/enrich_github_data.py data.json # 若不抓workflows可用這個指令

# 2b. 豐富資料 v2（Tree + fallback，含 sources/*.glyphs / *.glyphspackage）
python3 scripts/enrich_github_data_tree.py data.json -o data.v2.json
# 只要 metadata、不要 tree/files：
# python3 scripts/enrich_github_data_tree.py data.json --no-files -o data.v2.json

# 3. 預覽
cp data.json list.md no_found.md site/
cp data.v2.json site/v2/data.json   # 若有跑 v2 enrich
python3 -m http.server 8080 --directory site
open http://localhost:8080/index.html      # v1
open http://localhost:8080/v2/index.html   # v2
```

> [!NOTE] GH_TOKEN 可從[personal-access-tokens](https://github.com/settings/personal-access-tokens)得到
>
> 如果不申請，用匿名的大概抓50筆，就會需要等待30分才能再繼續

### v1 `--with-workflows`

會多抓每個 unique repo 的：

- `.github/workflows/*.yml`
- `.github/ISSUE_TEMPLATE/*.{yml,yaml}`

沒有的 repo 會是空陣列，前端自動隱藏

### v2 Tree enrich（`enrich_github_data_tree.py`）

每個 unique repo 約：

1. `GET /repos/{owner}/{repo}`（metadata + default_branch）
2. `GET /repos/.../git/trees/{default_branch}?recursive=1`
   - 若 `truncated: true` 或失敗 → fallback 打 Contents：
     - `sources/`
     - `.github/workflows`
     - `.github/ISSUE_TEMPLATE`

新增欄位：

| 欄位 | 說明 |
|------|------|
| `has_glyphs` | `sources/` 下是否有 `*.glyphs` 檔案 |
| `has_glyphspackage` | `sources/` 下是否有 `*.glyphspackage` 目錄 |
| `glyphs_sources[]` | `{name, path, url}` |
| `glyphspackage_sources[]` | `{name, path, url}` |
| `tree_method` | `tree` / `contents_fallback` / `none` |

約 1,279 unique repos 時，正常路徑約 **2,558** 次 API（遠低於 5,000/hr）。

### query/filter

可以透過[cli/github-info-filter](cli/github-info-filter/main.lua)來查詢生成的[data.json](site/data.json)

使用方式可以直接參考其[README.md](cli/github-info-filter/README.md)

## ofl 資料來源

```sh
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

## 維護


| 想改什麼                  | 改哪個檔                                                                                   |
|---------------------------|--------------------------------------------------------------------------------------------|
| 頁面結構 / 文案（v1）     | [site/index.html](site/index.html)                                                         |
| 頁面結構 / 文案（v2）     | [site/v2/index.html](site/v2/index.html)                                                   |
| 樣式                      | [site/css/style.css](site/css/style.css)                                                   |
| 搜尋、排序、篩選邏輯（v1）| [site/js/app.js](site/js/app.js)                                                           |
| 搜尋、排序、篩選邏輯（v2）| [site/v2/js/app.js](site/v2/js/app.js)                                                     |
| GitHub API 豐富欄位（v1） | [scripts/enrich_github_data.py](scripts/enrich_github_data.py)                             |
| GitHub API Tree + sources | [scripts/enrich_github_data_tree.py](scripts/enrich_github_data_tree.py)                   |
| CI 流程                   | [.github/workflows/generate-github-pages.yml](.github/workflows/generate-github-pages.yml) |


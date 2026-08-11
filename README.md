# google font ofl

搜集所有google font ofl的資訊

使得能夠找到所有上架到google font它們的github主頁

## ofl目錄中的: `ARTICLE.en_us.html` 怎麼取得的


```sh
git clone \
  --no-checkout \
  --branch main \
  --single-branch \
  --shallow-since="2026-08-01" \
  --filter=blob:none \
  --sparse \
  https://github.com/google/fonts.git ~/google-font

(
  cd ~/github/google-font
  git sparse-checkout set --no-cone '/ofl/**/ARTICLE.en_us.html'
  git checkout
)
```


## usage

```sh
nvim -l scripts/find_github_page.lua 1>list.md 2>no_found.md
```

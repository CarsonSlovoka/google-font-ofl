# google font ofl

搜集所有google font ofl的資訊

使得能夠找到所有上架到google font它們的github主頁

## ofl目錄中的: `upstream_info.md` 怎麼取得的


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
  git sparse-checkout set --no-cone '/ofl/**/upstream_info.md'
  git sparse-checkout set --no-cone '/ofl/**/METADATA.pb'
  git sparse-checkout set --no-cone '/ofl/**/OFL.txt'
  git checkout
)

# 如果要資料有更新，可以考慮同步
# rsync -avn  ~/new/ofl/  ./ofl  # dry run
# rsync -a    ~/new/ofl/  ./ofl
```


## usage

```sh
nvim -l scripts/find_github_page.lua 1>list.md 2>no_found.md
```


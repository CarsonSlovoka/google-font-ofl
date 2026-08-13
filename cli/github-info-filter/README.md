## 安裝

```sh
chmod u+x main.lua
sudo ln -siv "$(realpath main.lua)" /usr/local/bin/github-info-filter

# 測試
github-info-filter -h
```


## 使用
```sh
# 如果想要透過呼叫-l的方式直接跑lua也是行
nvim -l main.lua "$(git rev-parse --show-toplevel)/site/data.json" "pushed_at>=2026-08-01T00:00:00+08:00" "stars>=1000" | jq .


# 如果已經建立了連結和給+x的權限，即可這樣做
data_json_path="$(git rev-parse --show-toplevel)/site/data.json"

github-info-filter "$data_json_path" \
    "pushed_at>=2026-08-01T00:00:00+08:00" \
    "stars>=1000" \
    | jq .

# 輸出到文件
# 出來都是寫到stdout, stderr, 如果有需要可以自己再導出到文件, 如下
github-info-filter "$data_json_path" \
  "pushed_at>=2026-08-01T00:00:00+08:00" \
  "workflows nonempty" \
  | jq . > /tmp/workflog_noempty.json
```


> [!NOTE] 多條件目前只支援AND, 都是用AND串接


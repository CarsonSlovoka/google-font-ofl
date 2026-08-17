#!/usr/bin/env python3
"""
Enrich data.json (from find_github_page.lua) with GitHub repo metadata.

Adds per item:
  stars, forks, language, description,
  pushed_at, updated_at, created_at,
  workflows[] , issue_templates[]   (optional)

Usage:
  python3 scripts/enrich_github_data.py data.json
  python3 scripts/enrich_github_data.py data.json --with-workflows
  GH_TOKEN=... python3 scripts/enrich_github_data.py data.json -o data.json

Env:
  GH_TOKEN / GITHUB_TOKEN  – optional but recommended (higher rate limit)
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

API = "https://api.github.com"
"""
API使用片段: `git show -p adcd2a38:scripts/enrich_github_data.py | bat -l python -P -r 75:77 -r 89:96 -r 129:134`


GET /repos/{username}/{repo}

以下開啟 --with-workflows 時，會額外再使用這幾個API
GET /repos/{username}/{repo}/contents/.github/workflows
GET /repos/{username}/{repo}/contents/.github/ISSUE_TEMPLATE
"""


DEFAULT_WORKERS = 8
CONTENTS_WORKERS = 6


def _headers(token: str | None) -> dict[str, str]:
    h = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "google-fonts-ofl-pages-enricher",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        h["Authorization"] = f"Bearer {token}"
    return h


def _get_json(url: str, headers: dict[str, str], timeout: int = 25) -> Any | None:
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        # rate limit / secondary rate limit
        if e.code in (403, 429):
            retry = e.headers.get("Retry-After")
            wait = int(retry) if retry and retry.isdigit() else 30
            print(f"  rate-limited ({e.code}), sleep {wait}s: {url}", file=sys.stderr)
            time.sleep(wait)
            try:
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    return json.loads(resp.read().decode())
            except Exception as e2:
                print(f"  retry failed: {e2}", file=sys.stderr)
                return None
        print(f"  HTTP {e.code}: {url}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"  error: {e} ({url})", file=sys.stderr)
        return None


def fetch_repo(username: str, repo: str, headers: dict[str, str]) -> dict[str, Any]:
    url = f"{API}/repos/{username}/{repo}"
    body = _get_json(url, headers)
    if not body:
        return {
            "stars": -1,
            "forks": -1,
            "language": "",
            "description": "",
            "pushed_at": "",
            "updated_at": "",
            "created_at": "",
        }
    return {
        "stars": body.get("stargazers_count", 0) or 0,
        "forks": body.get("forks_count", 0) or 0,
        "language": body.get("language") or "",
        "description": body.get("description") or "",
        "pushed_at": body.get("pushed_at") or "",
        "updated_at": body.get("updated_at") or "",
        "created_at": body.get("created_at") or "",
    }


def list_dir_files(
    username: str, repo: str, path: str, headers: dict[str, str]
) -> list[dict[str, str]]:
    """List files under path (e.g. .github/workflows). Returns [{name, path, url}, ...]."""
    url = f"{API}/repos/{username}/{repo}/contents/{path}"
    body = _get_json(url, headers)
    if not isinstance(body, list):
        return []
    out: list[dict[str, str]] = []
    for entry in body:
        if entry.get("type") != "file":
            continue
        name = entry.get("name") or ""
        # only yml/yaml for workflows & issue templates
        if not name.lower().endswith((".yml", ".yaml")):
            continue
        html_url = entry.get("html_url") or (
            f"https://github.com/{username}/{repo}/blob/HEAD/{entry.get('path', path + '/' + name)}"
        )
        out.append(
            {
                "name": name,
                "path": entry.get("path") or f"{path}/{name}",
                "url": html_url,
            }
        )
    out.sort(key=lambda x: x["name"].lower())
    return out


def fetch_github_files(
    username: str, repo: str, headers: dict[str, str]
) -> dict[str, list[dict[str, str]]]:
    workflows = list_dir_files(username, repo, ".github/workflows", headers)
    issue_templates = list_dir_files(username, repo, ".github/ISSUE_TEMPLATE", headers)
    return {"workflows": workflows, "issue_templates": issue_templates}


def enrich(
    data: dict[str, Any],
    *,
    token: str | None,
    with_workflows: bool,
    workers: int,
) -> dict[str, Any]:
    headers = _headers(token)
    items: list[dict[str, Any]] = data.get("items") or []

    # Tip: 某些專案在ofl頁面: `https://github.com/google/fonts/tree/8c379a2/ofl` 會有多個，例如: cascadiacode, cascadiamono 它們都屬於: https://github.com/microsoft/cascadia-code 中專案的一部份，所以這類的只要一個
    unique: dict[tuple[str, str], list[int]] = {}
    for i, it in enumerate(items):
        key = (it.get("username") or "", it.get("repo_name") or "")
        if key[0] and key[1]:
            unique.setdefault(key, []).append(i)

    # Items: 1937, unique repos: 1279 當前唯一的項目共有1279. 當使用: --with-workflows 時，共需要: 1279*(1+2)= 3837. 還在5000內
    print(f"Items: {len(items)}, unique repos: {len(unique)}", file=sys.stderr)

    # --- repo metadata ---
    results: dict[tuple[str, str], dict[str, Any]] = {}
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {
            ex.submit(fetch_repo, u, r, headers): (u, r) for (u, r) in unique.keys()
        }
        done = 0
        for fut in as_completed(futs):
            key = futs[fut]
            results[key] = fut.result()
            done += 1
            if done % 50 == 0 or done == len(futs):
                print(f"  repo meta {done}/{len(futs)}", file=sys.stderr)

    for (u, r), idxs in unique.items():
        info = results.get((u, r), {})
        for i in idxs:
            items[i].update(
                {
                    "stars": info.get("stars", -1),
                    "forks": info.get("forks", -1),
                    "language": info.get("language") or "",
                    "description": info.get("description") or "",
                    "pushed_at": info.get("pushed_at") or "",
                    "updated_at": info.get("updated_at") or "",
                    "created_at": info.get("created_at") or "",
                }
            )

    enriched_meta = sum(1 for it in items if (it.get("stars") or -1) >= 0)
    print(f"Enriched meta: {enriched_meta}/{len(items)}", file=sys.stderr)

    # --- workflows / issue templates (optional, extra API calls) ---
    if with_workflows:
        print("Fetching .github/workflows & ISSUE_TEMPLATE …", file=sys.stderr)
        gh_files: dict[tuple[str, str], dict[str, list]] = {}
        with ThreadPoolExecutor(max_workers=CONTENTS_WORKERS) as ex:
            futs = {
                ex.submit(fetch_github_files, u, r, headers): (u, r)
                for (u, r) in unique.keys()
            }
            done = 0
            for fut in as_completed(futs):
                key = futs[fut]
                gh_files[key] = fut.result()
                done += 1
                if done % 50 == 0 or done == len(futs):
                    print(f"  github files {done}/{len(futs)}", file=sys.stderr)

        has_wf = 0
        has_it = 0
        for (u, r), idxs in unique.items():
            files = gh_files.get((u, r), {"workflows": [], "issue_templates": []})
            for i in idxs:
                items[i]["workflows"] = files.get("workflows") or []
                items[i]["issue_templates"] = files.get("issue_templates") or []
            if files.get("workflows"):
                has_wf += 1
            if files.get("issue_templates"):
                has_it += 1
        print(
            f"Repos with workflows: {has_wf}, with issue templates: {has_it}",
            file=sys.stderr,
        )
    else:
        for it in items:
            it.setdefault("workflows", [])
            it.setdefault("issue_templates", [])

    data["items"] = items
    data["enriched_count"] = enriched_meta
    data["with_workflows"] = with_workflows
    return data


def main() -> int:
    p = argparse.ArgumentParser(
        description="Enrich OFL upstream data.json via GitHub API"
    )
    p.add_argument("input", help="path to data.json from Lua scanner")
    p.add_argument("-o", "--output", help="output path (default: overwrite input)")
    p.add_argument(
        "--with-workflows",
        action="store_true",
        help="also list .github/workflows/*.yml and ISSUE_TEMPLATE (extra API calls)",
    )
    p.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    args = p.parse_args()

    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""
    if not token:
        print(
            "WARN: no GH_TOKEN/GITHUB_TOKEN — unauthenticated rate limit is low",
            file=sys.stderr,
        )

    with open(args.input, encoding="utf-8") as f:
        data = json.load(f)

    data = enrich(
        data,
        token=token or None,
        with_workflows=args.with_workflows,
        workers=args.workers,
    )

    out = args.output or args.input
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"Wrote {out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

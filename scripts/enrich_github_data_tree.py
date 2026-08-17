#!/usr/bin/env python3
"""
Enrich data.json (from find_github_page.lua) via GitHub Git Trees API + Contents fallback.

This is the v2 enricher. The original scripts/enrich_github_data.py is left unchanged.

Per unique repo:
  1) GET /repos/{owner}/{repo}          — metadata + default_branch
  2) GET /repos/.../git/trees/{ref}?recursive=1
     - if truncated or failed → fallback to Contents API for:
         sources/
         .github/workflows
         .github/ISSUE_TEMPLATE

Adds (on top of v1 fields):
  has_glyphs            bool
  has_glyphspackage     bool
  glyphs_sources[]      [{name, path, url}, ...]   # sources/*.glyphs (file)
  glyphspackage_sources[] [{name, path, url}, ...] # sources/*.glyphspackage (dir)
  tree_method           "tree" | "contents_fallback" | "none"
  workflows[] / issue_templates[]  (same shape as v1)

Usage:
  GH_TOKEN=... python3 scripts/enrich_github_data_tree.py data.json            -o data.v2.json
  GH_TOKEN=... python3 scripts/enrich_github_data_tree.py data.json --no-files -o data.v2.json

Env:
  GH_TOKEN / GITHUB_TOKEN  – recommended (5000 req/hr authenticated)
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

API = "https://api.github.com"
DEFAULT_WORKERS = 6
TREE_TIMEOUT = 40


def _headers(token: str | None) -> dict[str, str]:
    h = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "google-fonts-ofl-pages-enricher-tree",
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


def _blob_url(username: str, repo: str, path: str, ref: str = "HEAD") -> str:
    return f"https://github.com/{username}/{repo}/blob/{ref}/{path}"


def _tree_url(username: str, repo: str, path: str, ref: str = "HEAD") -> str:
    return f"https://github.com/{username}/{repo}/tree/{ref}/{path}"


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
            "default_branch": "",
        }
    return {
        "stars": body.get("stargazers_count", 0) or 0,
        "forks": body.get("forks_count", 0) or 0,
        "language": body.get("language") or "",
        "description": body.get("description") or "",
        "pushed_at": body.get("pushed_at") or "",
        "updated_at": body.get("updated_at") or "",
        "created_at": body.get("created_at") or "",
        "default_branch": body.get("default_branch") or "main",
    }


def _empty_files() -> dict[str, Any]:
    return {
        "workflows": [],
        "issue_templates": [],
        "glyphs_sources": [],
        "glyphspackage_sources": [],
        "has_glyphs": False,
        "has_glyphspackage": False,
        "tree_method": "none",
    }


def list_dir_yaml_files(
    username: str, repo: str, path: str, headers: dict[str, str]
) -> list[dict[str, str]]:
    """Contents API: list .yml/.yaml files under path."""
    url = f"{API}/repos/{username}/{repo}/contents/{urllib.parse.quote(path)}"
    body = _get_json(url, headers)
    if not isinstance(body, list):
        return []
    out: list[dict[str, str]] = []
    for entry in body:
        if entry.get("type") != "file":
            continue
        name = entry.get("name") or ""
        if not name.lower().endswith((".yml", ".yaml")):
            continue
        p = entry.get("path") or f"{path}/{name}"
        html_url = entry.get("html_url") or _blob_url(username, repo, p)
        out.append({"name": name, "path": p, "url": html_url})
    out.sort(key=lambda x: x["name"].lower())
    return out


def list_sources_contents(
    username: str, repo: str, headers: dict[str, str]
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    """Contents API: sources/*.glyphs (file) and sources/*.glyphspackage (dir)."""
    url = f"{API}/repos/{username}/{repo}/contents/sources"
    body = _get_json(url, headers)
    if not isinstance(body, list):
        return [], []
    glyphs: list[dict[str, str]] = []
    packages: list[dict[str, str]] = []
    for entry in body:
        name = entry.get("name") or ""
        typ = entry.get("type")
        p = entry.get("path") or f"sources/{name}"
        if typ == "file" and name.lower().endswith(".glyphs"):
            html_url = entry.get("html_url") or _blob_url(username, repo, p)
            glyphs.append({"name": name, "path": p, "url": html_url})
        elif typ == "dir" and name.lower().endswith(".glyphspackage"):
            html_url = entry.get("html_url") or _tree_url(username, repo, p)
            packages.append({"name": name, "path": p, "url": html_url})
    glyphs.sort(key=lambda x: x["name"].lower())
    packages.sort(key=lambda x: x["name"].lower())
    return glyphs, packages


def fetch_via_contents_fallback(
    username: str, repo: str, headers: dict[str, str]
) -> dict[str, Any]:
    """
    如果 tree 太大，會回：
    JSON{
      "truncated": true,
      "tree": [ ...部分資料... ]
    }
    故寫 fallback: 用 Contents API 去查 sources/、.github/workflows
    就比tree就會消耗更多的用量，但是這種專案數量算少數
    """
    workflows = list_dir_yaml_files(username, repo, ".github/workflows", headers)
    issue_templates = list_dir_yaml_files(
        username, repo, ".github/ISSUE_TEMPLATE", headers
    )
    glyphs, packages = list_sources_contents(username, repo, headers)
    return {
        "workflows": workflows,
        "issue_templates": issue_templates,
        "glyphs_sources": glyphs,
        "glyphspackage_sources": packages,
        "has_glyphs": bool(glyphs),
        "has_glyphspackage": bool(packages),
        "tree_method": "contents_fallback",
    }


def parse_tree_entries(
    username: str, repo: str, tree: list[dict[str, Any]], ref: str
) -> dict[str, Any]:
    """Parse recursive tree for workflows, issue templates, and sources glyphs."""
    workflows: list[dict[str, str]] = []
    issue_templates: list[dict[str, str]] = []
    glyphs: list[dict[str, str]] = []
    packages: list[dict[str, str]] = []

    for entry in tree:
        path = entry.get("path") or ""
        typ = entry.get("type")  # blob | tree
        if not path:
            continue

        parts = path.split("/")

        # sources/*.glyphs (file, exactly one level under sources/)
        if (
            typ == "blob"
            and len(parts) == 2
            and parts[0] == "sources"
            and parts[1].lower().endswith(".glyphs")
        ):
            name = parts[1]
            glyphs.append(
                {
                    "name": name,
                    "path": path,
                    "url": _blob_url(username, repo, path, ref),
                }
            )

        # sources/*.glyphspackage (directory)
        elif (
            typ == "tree"
            and len(parts) == 2
            and parts[0] == "sources"
            and parts[1].lower().endswith(".glyphspackage")
        ):
            name = parts[1]
            packages.append(
                {
                    "name": name,
                    "path": path,
                    "url": _tree_url(username, repo, path, ref),
                }
            )

        # .github/workflows/*.yml
        elif (
            typ == "blob"
            and len(parts) == 3
            and parts[0] == ".github"
            and parts[1] == "workflows"
            and parts[2].lower().endswith((".yml", ".yaml"))
        ):
            name = parts[2]
            workflows.append(
                {
                    "name": name,
                    "path": path,
                    "url": _blob_url(username, repo, path, ref),
                }
            )

        # .github/ISSUE_TEMPLATE/*.yml
        elif (
            typ == "blob"
            and len(parts) == 3
            and parts[0] == ".github"
            and parts[1] == "ISSUE_TEMPLATE"
            and parts[2].lower().endswith((".yml", ".yaml"))
        ):
            name = parts[2]
            issue_templates.append(
                {
                    "name": name,
                    "path": path,
                    "url": _blob_url(username, repo, path, ref),
                }
            )

    workflows.sort(key=lambda x: x["name"].lower())
    issue_templates.sort(key=lambda x: x["name"].lower())
    glyphs.sort(key=lambda x: x["name"].lower())
    packages.sort(key=lambda x: x["name"].lower())

    return {
        "workflows": workflows,
        "issue_templates": issue_templates,
        "glyphs_sources": glyphs,
        "glyphspackage_sources": packages,
        "has_glyphs": bool(glyphs),
        "has_glyphspackage": bool(packages),
        "tree_method": "tree",
    }


def fetch_tree_or_fallback(
    username: str,
    repo: str,
    default_branch: str,
    headers: dict[str, str],
) -> dict[str, Any]:
    ref = default_branch or "main"
    # GitHub accepts branch name as tree_sha for this endpoint
    encoded_ref = urllib.parse.quote(ref, safe="")
    url = f"{API}/repos/{username}/{repo}/git/trees/{encoded_ref}?recursive=1" # Important: 通常此API在tree不大時，能全部列出來
    body = _get_json(url, headers, timeout=TREE_TIMEOUT)

    if not body or not isinstance(body, dict):
        return fetch_via_contents_fallback(username, repo, headers)

    if body.get("truncated"):
        print(
            f"  truncated tree → contents fallback: {username}/{repo}",
            file=sys.stderr,
        )
        return fetch_via_contents_fallback(username, repo, headers)

    tree = body.get("tree")
    if not isinstance(tree, list):
        return fetch_via_contents_fallback(username, repo, headers)

    return parse_tree_entries(username, repo, tree, ref)


def enrich_one(
    username: str,
    repo: str,
    headers: dict[str, str],
    *,
    with_files: bool,
) -> dict[str, Any]:
    meta = fetch_repo(username, repo, headers)
    if not with_files:
        files = _empty_files()
    else:
        if (meta.get("stars") or -1) < 0 and not meta.get("default_branch"):
            # repo fetch failed; skip files
            files = _empty_files()
        else:
            files = fetch_tree_or_fallback(
                username,
                repo,
                meta.get("default_branch") or "main",
                headers,
            )
    # do not expose default_branch to data.json (internal only)
    meta.pop("default_branch", None)
    return {**meta, **files}


def enrich(
    data: dict[str, Any],
    *,
    token: str | None,
    with_files: bool,
    workers: int,
) -> dict[str, Any]:
    headers = _headers(token)
    items: list[dict[str, Any]] = data.get("items") or []

    unique: dict[tuple[str, str], list[int]] = {}
    for i, it in enumerate(items):
        key = (it.get("username") or "", it.get("repo_name") or "")
        if key[0] and key[1]:
            unique.setdefault(key, []).append(i)

    print(
        f"[tree] Items: {len(items)}, unique repos: {len(unique)}, with_files={with_files}",
        file=sys.stderr,
    )

    results: dict[tuple[str, str], dict[str, Any]] = {}
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {
            ex.submit(enrich_one, u, r, headers, with_files=with_files): (u, r)
            for (u, r) in unique.keys()
        }
        done = 0
        for fut in as_completed(futs):
            key = futs[fut]
            try:
                results[key] = fut.result()
            except Exception as e:
                print(f"  enrich failed {key}: {e}", file=sys.stderr)
                results[key] = {
                    "stars": -1,
                    "forks": -1,
                    "language": "",
                    "description": "",
                    "pushed_at": "",
                    "updated_at": "",
                    "created_at": "",
                    **_empty_files(),
                }
            done += 1
            if done % 50 == 0 or done == len(futs):
                print(f"  enriched {done}/{len(futs)}", file=sys.stderr)

    method_counts = {"tree": 0, "contents_fallback": 0, "none": 0}
    has_glyphs_n = 0
    has_pkg_n = 0
    has_wf_n = 0
    has_it_n = 0

    for (u, r), idxs in unique.items():
        info = results.get((u, r), {})
        method = info.get("tree_method") or "none"
        method_counts[method] = method_counts.get(method, 0) + 1
        if info.get("has_glyphs"):
            has_glyphs_n += 1
        if info.get("has_glyphspackage"):
            has_pkg_n += 1
        if info.get("workflows"):
            has_wf_n += 1
        if info.get("issue_templates"):
            has_it_n += 1

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
                    "workflows": info.get("workflows") or [],
                    "issue_templates": info.get("issue_templates") or [],
                    "glyphs_sources": info.get("glyphs_sources") or [],
                    "glyphspackage_sources": info.get("glyphspackage_sources") or [],
                    "has_glyphs": bool(info.get("has_glyphs")),
                    "has_glyphspackage": bool(info.get("has_glyphspackage")),
                    "tree_method": method,
                }
            )

    # items without username/repo
    for it in items:
        it.setdefault("workflows", [])
        it.setdefault("issue_templates", [])
        it.setdefault("glyphs_sources", [])
        it.setdefault("glyphspackage_sources", [])
        it.setdefault("has_glyphs", False)
        it.setdefault("has_glyphspackage", False)
        it.setdefault("tree_method", "none")

    enriched_meta = sum(1 for it in items if (it.get("stars") or -1) >= 0)
    print(f"[tree] Enriched meta: {enriched_meta}/{len(items)}", file=sys.stderr)
    print(
        f"[tree] method counts: tree={method_counts.get('tree', 0)} "
        f"fallback={method_counts.get('contents_fallback', 0)} "
        f"none={method_counts.get('none', 0)}",
        file=sys.stderr,
    )
    print(
        f"[tree] has_glyphs={has_glyphs_n} has_glyphspackage={has_pkg_n} "
        f"workflows={has_wf_n} issue_templates={has_it_n}",
        file=sys.stderr,
    )

    data["items"] = items
    data["enriched_count"] = enriched_meta
    data["enrich_version"] = "tree-v1"
    data["with_files"] = with_files
    data["tree_method_counts"] = method_counts
    return data


def main() -> int:
    p = argparse.ArgumentParser(
        description="Enrich OFL upstream data.json via Git Trees API + Contents fallback"
    )
    p.add_argument("input", help="path to data.json from Lua scanner")
    p.add_argument("-o", "--output", help="output path (default: overwrite input)")
    p.add_argument(
        "--no-files",
        action="store_true",
        help="only fetch repo metadata (skip tree / workflows / sources)",
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
        with_files=not args.no_files,
        workers=args.workers,
    )

    out = args.output or args.input
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"[tree] Wrote {out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

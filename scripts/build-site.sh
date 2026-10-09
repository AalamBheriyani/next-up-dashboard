#!/usr/bin/env bash
# Builds the GitHub Pages site into $1: docs/ at the root, plus docs/ as it was at every version tag
# under v/<tag>/, a version.json in each, and v/index.html listing them all.
set -euo pipefail
out=${1:-_site}
rm -rf "$out"; mkdir -p "$out/v"
cur=$(git tag --points-at HEAD -l 'v0.*' 'v[2-9]*' --sort=-v:refname | head -1)
cp -r docs/. "$out/"
printf '{"version":"%s","date":"%s"}\n' "${cur:-dev}" "$(git log -1 --format=%cs)" > "$out/version.json"
rows=""
for t in $(git tag -l 'v0.*' 'v[2-9]*' --sort=-v:refname) $(git tag -l 'v1.*' --sort=-v:refname); do
  d=$(git log -1 --format=%cs "$t")
  mkdir -p "$out/v/$t"
  git archive "$t" docs | tar -x --strip-components=1 -C "$out/v/$t"
  printf '{"version":"%s","date":"%s"}\n' "$t" "$d" > "$out/v/$t/version.json"
  label=$t; [[ $t == v1.* ]] && label="$t (early build)"
  rows+="<li><a href=\"$t/\">$label</a> <span>$d</span> <a class=\"rel\" href=\"https://github.com/AalamBheriyani/next-up-dashboard/releases/tag/$t\">changes</a></li>"
done
cat > "$out/v/index.html" <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>Next Up versions</title>
<style>body{margin:0;background:#000;color:#fff;font:15px/1.6 system-ui,sans-serif;padding:24px 16px}main{max-width:640px;margin:0 auto}
a{color:#4d8dff}h1{font-size:28px;margin:0 0 4px}p{color:#9db8ff}ul{list-style:none;padding:0}li{display:flex;gap:14px;padding:8px 0;border-bottom:1px solid #1c1f26}
li span{color:#9db8ff;font-family:monospace}.rel{margin-left:auto;font-size:13px}</style></head>
<body><main><h1>Next Up versions</h1><p>Every version ever published. Open one to use the dashboard exactly as it was. <a href="../">Back to the latest</a></p>
<ul>${rows:-<li>No versions yet.</li>}</ul></main></body></html>
HTML
echo "built $(ls "$out/v" | grep -c '^v') versions"

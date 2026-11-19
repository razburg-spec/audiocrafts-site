#!/bin/sh
# Cloudflare Pages build: copy the static site into dist/, leaving out repo-only
# folders and any file over the 25 MiB per-file limit (those are served from
# GitHub by functions/files/[[path]].js).
set -e
rm -rf dist
mkdir dist
for f in * .[!.]*; do
  case "$f" in
    dist|functions|netlify|scripts|supabase|.git|.github|README.md) continue ;;
  esac
  [ -e "$f" ] && cp -R "$f" dist/
done
find dist -type f -size +25M -print -delete
echo "Build done."

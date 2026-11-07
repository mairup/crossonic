#!/usr/bin/env bash
# Crossonic fork release pipeline (g14, user systemd timer every 30 min).
#
# RULES (user-mandated, 2026-11-06):
# - Development happens on the dev branch; agents test on the DEV web deployment
#   https://crossonic.mairup.space (mai-ai crossonic-dev container, :4535).
# - main = production. A merge to main must be production-ready (gate + review +
#   verified on the dev deployment). Merging to main deploys the PROD web client
#   (https://music.mairup.space, crossonic container :4534) and bumps the version
#   tag: this script creates tag v<pubspec version> on the main merge and publishes
#   a Forgejo release with fork-signed APKs so phones auto-update.
#
# Jobs:
# - DEV WEB SYNC: origin/dev HEAD moved -> gate on dev, build web --wasm, deploy to
#   mai-ai ~/www/music-stack/crossonic-dev (crossonic.mairup.space), cache-busted.
# - PROD WEB SYNC: origin/main HEAD moved -> gate on main, deploy to ~/www/music-stack/
#   crossonic (music.mairup.space), cache-busted, README provenance updated.
# - APP RELEASE: tag v<pubspec version> missing on origin/main after a main merge ->
#   create+push it, then publish the Forgejo release with the 3 APKs + web zip.
#   Asset names Crossonic-<version>-android-<arch>.apk (arm64v8/arm32v7/x64) are
#   matched EXACTLY by the in-app updater; every APK must verify CN=Crossonic Fork.
# Fails safe: the gate blocks every deploy/release; failures notify Mai via Talk DM.
# Idempotent via state files under ~/.local/state/crossonic-release/, log release.log.
set -uo pipefail

REPO=/home/mai/Documents/Projects/crossonic
FLUTTER=/opt/flutter/bin/flutter
STATE="$HOME/.local/state/crossonic-release"
LOG="$STATE/release.log"
MAI_AI=mai-ai
DEPLOY=/home/mai/www/music-stack/crossonic
DEV_DEPLOY=/home/mai/www/music-stack/crossonic-dev
FORGEJO_ENV="$HOME/mind-core/.secrets/forgejo.env"

mkdir -p "$STATE"
exec > >(tee -a "$LOG") 2>&1
log() { echo "[$(date '+%F %T')] $*"; }

notify() { # best-effort Talk DM to Mai via nab9's Nextcloud; never fatal
  local msg="$1"
  ssh -n -o ConnectTimeout=8 nab9 "NC_PASS=\$(cat /home/mai/.mind-secrets-nc 2>/dev/null); [ -n \"\$NC_PASS\" ] && curl -s --max-time 8 -u hermes:\"\$NC_PASS\" -H 'OCS-APIRequest: true' --data-urlencode 'message=$msg' http://192.168.5.69:33080/ocs/v2.php/apps/spreed/api/v1/chat/mhahoo5k" >/dev/null 2>&1 || true
}

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

cd "$REPO" || { log "FATAL: no $REPO"; exit 1; }
if ! git diff --quiet || ! git diff --cached --quiet; then
  log "FATAL: dirty working tree — aborting"
  notify "⚠️ crossonic release pipeline aborted: dirty working tree in $REPO"
  exit 1
fi

git fetch origin --tags --quiet || { log "FATAL: fetch origin failed"; notify "⚠️ crossonic pipeline: git fetch failed"; exit 1; }
MAIN_SHA=$(git rev-parse origin/main)
DEV_SHA=$(git rev-parse origin/dev)
LAST_MAIN=$(cat "$STATE/last_main" 2>/dev/null || echo "")
LAST_DEV=$(cat "$STATE/last_dev" 2>/dev/null || echo "")
LAST_TAG=$(cat "$STATE/last_tag" 2>/dev/null || echo "")

NEED_DEV=0; NEED_WEB=0; NEED_APP=0
[ "$DEV_SHA" != "$LAST_DEV" ] && NEED_DEV=1
[ "$MAIN_SHA" != "$LAST_MAIN" ] && NEED_WEB=1
# a tag pushed by a previous run (or by hand) without a published app release
# still needs publish_app, so it must be part of the nothing-to-do check
NEWEST_TAG=$(git tag -l 'v*' --merged origin/main | sort -V | tail -1)
[ -n "$NEWEST_TAG" ] && [ "$NEWEST_TAG" != "$LAST_TAG" ] && NEED_APP=1

if [ "$NEED_DEV" -eq 0 ] && [ "$NEED_WEB" -eq 0 ] && [ "$NEED_APP" -eq 0 ]; then
  log "nothing to do (dev ${DEV_SHA:0:7}, main ${MAIN_SHA:0:7}, $LAST_TAG published)"
  exit 0
fi

gate() {
  log "gate: pub get + build_runner"
  if ! { $FLUTTER pub get >/dev/null && dart run build_runner build --delete-conflicting-outputs >/dev/null; }; then
    log "FATAL: gate prep failed"; notify "⚠️ crossonic pipeline: gate prep failed"; return 1
  fi
  log "gate: flutter analyze"
  if ! $FLUTTER analyze > "$STATE/analyze.log" 2>&1; then
    if grep -q "error •" "$STATE/analyze.log"; then
      log "FATAL: analyze has errors (see $STATE/analyze.log)"
      notify "⚠️ crossonic pipeline: analyze errors on origin/main — release blocked"
      return 1
    fi
  fi
  log "gate: flutter test"
  if ! $FLUTTER test 2>&1 | tee "$STATE/test.log" | grep -q "All tests passed!"; then
    log "FATAL: tests failed (see $STATE/test.log)"
    notify "⚠️ crossonic pipeline: tests failed on origin/main — release blocked"
    return 1
  fi
  log "gate passed"
}

build_web_zip() {
  $FLUTTER build web --wasm >/dev/null || { log "FATAL: web build failed"; notify "⚠️ crossonic pipeline: web build failed"; return 1; }
  ( cd build/web && python3 -m zipfile -c "$STATE/Crossonic-$VER-web.zip" . )
  # checksum lines must carry the bare filename: the file is verified with
  # sha256sum -c on mai-ai, where the local absolute path does not exist
  (cd "$STATE" && sha256sum "Crossonic-$VER-web.zip" > "Crossonic-$VER-SHA256SUMS.txt")
}

bust_bootstrap() { # $1 = remote dir, $2 = sha to bake in; quote-free sed (remote shell is fish)
  # -n is load-bearing: the service runs this script via `git show | bash`, so
  # the script itself is bash's stdin and an ssh without -n would consume the
  # rest of it, silently truncating the run after the first deploy
  ssh -n "$MAI_AI" "cd $1/web && sed -i -e 's|\?v=[a-zA-Z0-9]\{3,\}|?v=TMP|g' -e 's|main\.dart\.js\([^a-z]\)|main.dart.js?v=$2\1|g' -e 's|main\.dart\.mjs\([^a-z]\)|main.dart.mjs?v=$2\1|g' -e 's|main\.dart\.wasm\([^a-z]\)|main.dart.wasm?v=$2\1|g' -e 's|?v=TMP|?v=$2|g' flutter_bootstrap.js"
}

deploy_web_to() { # $1 = remote dir, $2 = sha, $3 = public check URL, $4 = state file, $5 = label
  local rdir=$1 sha=$2 url=$3 statef=$4 label=$5
  build_web_zip || return 1
  if [ "$DRY" -eq 1 ]; then log "DRY: $label web $VER built, not deployed"; return 0; fi
  scp -q "$STATE/Crossonic-$VER-web.zip" "$STATE/Crossonic-$VER-SHA256SUMS.txt" "$MAI_AI:$rdir/"
  # -n as in bust_bootstrap: keep ssh from eating the piped script on stdin
  if ! ssh -n "$MAI_AI" "cd $rdir && sha256sum -c 'Crossonic-$VER-SHA256SUMS.txt' && unzip -oq 'Crossonic-$VER-web.zip' -d web"; then
    log "FATAL: $label deploy to mai-ai failed"; notify "⚠️ crossonic pipeline: $label web deploy failed"; return 1
  fi
  if ! bust_bootstrap "$rdir" "$sha"; then
    log "WARN: $label cache-bust patch failed"; notify "⚠️ crossonic pipeline: $label cache-bust failed"
  else
    log "$label cache-busted entry files with v=$sha"
  fi
  curl -s -o /dev/null -w "$label web check: %{http_code}\n" "$url"
  echo "$sha" > "$STATE/$statef"
  log "$label web $VER deployed from $label ${sha:0:7}"
}

deploy_web() { # prod: music.mairup.space (crossonic container :4534)
  deploy_web_to "$DEPLOY" "$MAIN_SHA" "https://music.mairup.space/" last_main prod || return 1
  scp -q "$MAI_AI:$DEPLOY/README.md" "$STATE/README.md"
  python3 - "$STATE/README.md" "$VER" "$MAIN_SHA" "$(cut -d' ' -f1 "$STATE/Crossonic-$VER-SHA256SUMS.txt")" <<'PY'
import re, sys
path, ver, sha, zsha = sys.argv[1:5]
text = open(path).read()
new = ("- Deployed version: **v%s** — `Crossonic-%s-web.zip`, sha256\n  `%s` (`%s-SHA256SUMS.txt` kept alongside).\n"
       "  Built from the fork `git.mairup.space/mai/crossonic`, commit `%s`." %
       (ver, ver, zsha, ver, sha))
text, n = re.subn(r"- Deployed version:.*?(?=\n- )", new, text, count=1, flags=re.S)
if n == 0:
    sys.exit(1)
open(path, "w").write(text)
PY
  scp -q "$STATE/README.md" "$MAI_AI:$DEPLOY/README.md"
}

deploy_dev_web() { # dev: crossonic.mairup.space (crossonic-dev container :4535)
  git checkout -q dev && git reset -q --hard origin/dev || { log "FATAL: sync to origin/dev failed"; return 1; }
  gate || return 1
  VER=$(grep -m1 '^version:' pubspec.yaml | sed 's/version: //')
  deploy_web_to "$DEV_DEPLOY" "$DEV_SHA" "https://crossonic.mairup.space/" last_dev dev
}

publish_app() {
  local tag=$NEWEST_TAG
  local ver=${NEWEST_TAG#v}
  local out="$STATE/$tag"
  $FLUTTER build apk --split-per-abi >/dev/null || { log "FATAL: apk build failed"; notify "⚠️ crossonic pipeline: apk build failed"; return 1; }
  mkdir -p "$out"
  cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$out/Crossonic-$ver-android-arm64v8.apk"
  cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk "$out/Crossonic-$ver-android-arm32v7.apk"
  cp build/app/outputs/flutter-apk/app-x86_64-release.apk "$out/Crossonic-$ver-android-x64.apk"
  # signing provenance: every APK must carry the fork key, never strip/replace
  for a in "$out"/*.apk; do
    apksigner verify --print-certs "$a" 2>/dev/null | grep -q "CN=Crossonic Fork" || {
      log "FATAL: $a not signed by CN=Crossonic Fork — aborting release";
      notify "⚠️ crossonic pipeline: APK signing check failed for $tag"; return 1; }
  done

  log "building linux release bundle"
  $FLUTTER build linux --release >/dev/null || { log "FATAL: linux build failed"; notify "⚠️ crossonic pipeline: linux build failed"; return 1; }
  local libmpv_dir=/tmp/crossonic-libmpv
  mkdir -p "$libmpv_dir/licenses"
  cp -a /usr/lib/libmpv.so* "$libmpv_dir/" 2>/dev/null || true
  touch "$libmpv_dir/licenses/mpv.txt"
  ./scripts/appimage/build.sh "$ver" "$libmpv_dir"
  mv "Crossonic-$ver-linux-x86-64.AppImage" "$out/Crossonic-$ver-linux-x86-64.AppImage"

  local ver_base="${ver%%+*}"
  if [ "$ver_base" != "$ver" ]; then
    cp "$out/Crossonic-$ver-linux-x86-64.AppImage" "$out/Crossonic-$ver_base-linux-x86-64.AppImage"
    for a in "$out"/Crossonic-$ver-android-*.apk; do
      cp "$a" "${a/$ver/$ver_base}"
    done
  fi

  [ -f "$STATE/Crossonic-$VER-web.zip" ] || build_web_zip || return 1
  if [ "$DRY" -eq 1 ]; then log "DRY: release $tag not published"; return 0; fi
  source "$FORGEJO_ENV"
  local body="Release $tag from main $(git rev-parse --short origin/main)."$'\n\n'"$(git log --oneline "$LAST_TAG..origin/main" | sed 's/^/- /')"
  local id
  id=$(curl -s -X POST -H "Authorization: token $FORGEJO_TOKEN" -H "Content-Type: application/json" \
    -d "$(jq -n --arg tag "$tag" --arg body "$body" '{tag_name:$tag, name:$tag, body:$body, draft:false, prerelease:false}')" \
    "$FORGEJO_API_URL/api/v1/repos/mai/crossonic/releases" | jq '.id')
  if [ -z "$id" ] || [ "$id" = "null" ]; then
    log "FATAL: Forgejo release create failed"; notify "⚠️ crossonic pipeline: Forgejo release create failed for $tag"; return 1
  fi
  for a in "$out"/Crossonic-*-android-*.apk "$out"/Crossonic-*-linux-x86-64.AppImage "$STATE/Crossonic-$VER-web.zip"; do
    if [ -f "$a" ]; then
      if ! curl -s -X POST -H "Authorization: token $FORGEJO_TOKEN" \
          -F "attachment=@$a" -F "name=$(basename "$a")" \
          "$FORGEJO_API_URL/api/v1/repos/mai/crossonic/releases/$id/assets" | jq -e '.name' >/dev/null; then
        log "FATAL: asset upload failed for $a"; notify "⚠️ crossonic pipeline: asset upload failed for $tag"; return 1
      fi
    fi
  done
  echo "$tag" > "$STATE/last_tag"
  log "release $tag published (Forgejo id $id, $(git rev-parse --short "$tag"))"
}

[ "$NEED_DEV" -eq 1 ] && { deploy_dev_web || exit 1; }

git checkout -q main && git reset -q --hard origin/main || { log "FATAL: sync to origin/main failed"; exit 1; }
VER=$(grep -m1 '^version:' pubspec.yaml | sed 's/version: //')

if [ "$NEED_WEB" -eq 1 ]; then
  gate || exit 1
  deploy_web || exit 1
  # rule: a main merge bumps the version tag -> create v<pubspec version> on the
  # merge commit if missing, then publish the app release for it
  if ! git rev-parse -q --verify "refs/tags/v$VER" >/dev/null; then
    if [ "$DRY" -eq 1 ]; then
      log "DRY: would tag v$VER on ${MAIN_SHA:0:7}"
    else
      git tag -a "v$VER" -m "Crossonic fork release v$VER" "$MAIN_SHA" && git push -q origin "v$VER" \
        || { log "FATAL: could not push tag v$VER"; notify "⚠️ crossonic pipeline: tag push failed"; exit 1; }
      log "created tag v$VER on ${MAIN_SHA:0:7}"
    fi
  fi
fi

[ "$NEED_APP" -eq 1 ] && { publish_app || exit 1; }
log "run complete"

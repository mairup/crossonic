#!/usr/bin/env bash
# Crossonic fork release pipeline (g14, Hermes-operated, systemd timer every 30 min).
# Job A (web sync): if origin/main HEAD moved since last deploy: gate (analyze+test),
#   flutter build web --wasm, deploy to mai-ai ~/www/music-stack/crossonic (README
#   provenance updated, zip + SHA256SUMS kept for provenance).
# Job B (app release): if a new v<semver> tag is reachable from origin/main beyond the
#   last published release: gate, build split-ABI APKs, rename to the updater asset
#   names Crossonic-<version>-android-<arch>.apk (arm64v8/arm32v7/x64 — the in-app
#   updater matches these names EXACTLY), verify fork signing, publish a Forgejo
#   release with the 3 APKs + web zip.
# Fails safe: the gate blocks every deploy/release; any failure notifies Mai via
#   Talk DM (through nab9). Idempotent via state files under
#   ~/.local/state/crossonic-release/ (last_main, last_tag), logged to release.log.
set -uo pipefail

REPO=/home/mai/Documents/Projects/crossonic
FLUTTER=/opt/flutter/bin/flutter
STATE="$HOME/.local/state/crossonic-release"
LOG="$STATE/release.log"
MAI_AI=mai-ai
DEPLOY=/home/mai/www/music-stack/crossonic
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

git fetch origin --tags || { log "FATAL: fetch origin failed"; notify "⚠️ crossonic pipeline: git fetch failed"; exit 1; }
git checkout -q main && git reset -q --hard origin/main || { log "FATAL: sync to origin/main failed"; exit 1; }
MAIN_SHA=$(git rev-parse origin/main)
LAST_MAIN=$(cat "$STATE/last_main" 2>/dev/null || echo "")
LAST_TAG=$(cat "$STATE/last_tag" 2>/dev/null || echo "")
VER=$(grep -m1 '^version:' pubspec.yaml | sed 's/version: //')
NEWEST_TAG=$(git tag -l 'v*' --merged origin/main | sort -V | tail -1)

NEED_WEB=0; NEED_APP=0
[ "$MAIN_SHA" != "$LAST_MAIN" ] && NEED_WEB=1
[ -n "$NEWEST_TAG" ] && [ "$NEWEST_TAG" != "$LAST_TAG" ] && NEED_APP=1

if [ "$NEED_WEB" -eq 0 ] && [ "$NEED_APP" -eq 0 ]; then
  log "nothing to do (main ${MAIN_SHA:0:7} deployed, $LAST_TAG published)"
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
  sha256sum "$STATE/Crossonic-$VER-web.zip" > "$STATE/Crossonic-$VER-SHA256SUMS.txt"
}

deploy_web() {
  build_web_zip || return 1
  if [ "$DRY" -eq 1 ]; then log "DRY: web $VER built, not deployed"; return 0; fi
  scp -q "$STATE/Crossonic-$VER-web.zip" "$STATE/Crossonic-$VER-SHA256SUMS.txt" "$MAI_AI:$DEPLOY/"
  if ! ssh "$MAI_AI" "cd $DEPLOY && sha256sum -c 'Crossonic-$VER-SHA256SUMS.txt' && unzip -oq 'Crossonic-$VER-web.zip' -d web"; then
    log "FATAL: deploy to mai-ai failed"; notify "⚠️ crossonic pipeline: web deploy to mai-ai failed"; return 1
  fi
  # README provenance: replace the Deployed version bullet
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
  curl -s -o /dev/null -w 'web check: %{http_code}\n' https://crossonic.mairup.space/
  echo "$MAIN_SHA" > "$STATE/last_main"
  log "web $VER deployed from main ${MAIN_SHA:0:7}"
}

publish_app() {
  local tag=$NEWEST_TAG ver=${NEWEST_TAG#v} out="$STATE/$tag"
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
  for a in "$out"/Crossonic-$ver-android-*.apk "$STATE/Crossonic-$VER-web.zip"; do
    if ! curl -s -X POST -H "Authorization: token $FORGEJO_TOKEN" \
        -F "attachment=@$a" -F "name=$(basename "$a")" \
        "$FORGEJO_API_URL/api/v1/repos/mai/crossonic/releases/$id/assets" | jq -e '.name' >/dev/null; then
      log "FATAL: asset upload failed for $a"; notify "⚠️ crossonic pipeline: asset upload failed for $tag"; return 1
    fi
  done
  echo "$tag" > "$STATE/last_tag"
  log "release $tag published (Forgejo id $id, $(git rev-parse --short "$tag"))"
}

gate || exit 1
[ "$NEED_WEB" -eq 1 ] && { deploy_web || exit 1; }
[ "$NEED_APP" -eq 1 ] && { publish_app || exit 1; }
log "run complete"

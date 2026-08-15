#!/usr/bin/env bash
#
# migrate-gitea-to-forgejo.sh
#
# Coexistence migration: Gitea (source) on :6969, Forgejo (target) on :6970.
# Both instances must be running. Creates a matching empty repo in Forgejo for
# each source repo, then mirrors every ref (branches + tags) from Gitea.
#
# No LFS handling is required today (0 LFS repos); a guarded `git lfs push`
# covers the case where a repo has LFS objects.
#
# Usage:
#   GITEA_TOKEN=<gitea-admin-token> FORGEJO_TOKEN=<forgejo-admin-token> \
#     bash scripts/migrate-gitea-to-forgejo.sh
#
# Override with env if needed: SRC, DST, OWNER, LIMIT
#
set -euo pipefail

SRC="${SRC:-http://localhost:6969}"
DST="${DST:-http://localhost:6970}"
OWNER="${OWNER:-SteelPh0enix}"
LIMIT=50

: "${GITEA_TOKEN:?set GITEA_TOKEN (source Gitea admin token)}"
: "${FORGEJO_TOKEN:?set FORGEJO_TOKEN (target Forgejo admin token)}"
command -v jq  >/dev/null || { echo "error: jq required"  >&2; exit 1; }
command -v git >/dev/null || { echo "error: git required" >&2; exit 1; }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

# Fetch the source repo list once
curl -sf -H "Authorization: token $GITEA_TOKEN" \
  "$SRC/api/v1/user/repos?limit=$LIMIT" > "$W/repos.json"

mapfile -t REPOS < <(jq -r '.[] | "\(.name)\t\(.default_branch)"' "$W/repos.json")
total="${#REPOS[@]}"
echo "Found $total source repo(s) under $OWNER."
echo "  source: $SRC"
echo "  target: $DST"
echo

ok=0; fail=0; i=0
for r in "${REPOS[@]}"; do
  i=$((i+1))
  name="${r%%$'\t'*}"
  db="${r#*$'\t'}"
  printf '[%d/%d] %s  (default=%s)\n' "$i" "$total" "$name" "$db"

  # 1) create the empty target repo (ignore failure if it already exists)
  curl -sf -X POST -H "Authorization: token $FORGEJO_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg n "$name" --arg b "$db" '{name:$n, private:true, auto_init:false, default_branch:$b}')" \
    "$DST/api/v1/user/repos" >/dev/null 2>&1 \
    || echo "    (target repo already exists — continuing)"

  # 2) mirror every ref (branches + tags) from source to target
  git -c http.extraHeader="Authorization: token $GITEA_TOKEN" \
      clone --mirror "$SRC/$OWNER/$name.git" "$W/$name.git" >/dev/null
  git -C "$W/$name.git" \
      -c http.extraHeader="Authorization: token $FORGEJO_TOKEN" \
      push --mirror "$DST/$OWNER/$name.git" >/dev/null

  # 3) LFS (guarded no-op unless this repo actually has LFS objects)
  if git -C "$W/$name.git" lfs ls-files 2>/dev/null | grep -q .; then
    git -C "$W/$name.git" remote add dst "$DST/$OWNER/$name.git"
    git -C "$W/$name.git" \
      -c http.extraHeader="Authorization: token $FORGEJO_TOKEN" \
      lfs push --all dst
    echo "    (LFS objects pushed)"
  fi

  # 4) verify the target now has refs
  if git -c http.extraHeader="Authorization: token $FORGEJO_TOKEN" \
      ls-remote --exit-code "$DST/$OWNER/$name.git" >/dev/null 2>&1; then
    echo "    ok"; ok=$((ok+1))
  else
    echo "    FAILED"; fail=$((fail+1))
  fi
done

echo
echo "Done: $ok ok, $fail failed (of $total)."
echo "Verify in the Forgejo UI (target on port ${DST##*:}) as $OWNER."

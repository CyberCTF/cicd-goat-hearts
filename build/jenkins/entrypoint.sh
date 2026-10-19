#!/bin/bash
# Wonderland Jenkins entrypoint. Stages the per-player flag into the directory JCasC reads file
# secrets from ($SECRETS), so the prod-deploy credential's secret resolves at boot — WITHOUT the flag
# ever being an image layer, a spec value or a process environment variable. Because prod-deploy is
# System-scope, no pipeline can bind it; a privileged user must read it from the Script Console,
# which is the whole point of the challenge.
#
# Isoloom mounts the per-player input as a read-only file at /run/lab/secrets/hearts. When it is empty
# (an offline start — local, CI) the inert development placeholder is staged instead, so the lab
# still comes up and is solvable.
set -eu

DEV='hearts-dev-flag-not-a-real-secret-0000'
SRC_FLAG='/run/lab/secrets/hearts'
SECRETS_DIR="${SECRETS:-/run/lab/casc_secrets}"

stage() {  # $1 = destination directory
  mkdir -p "$1"
  if [ -s "$SRC_FLAG" ]; then
    tr -d '\r\n' < "$SRC_FLAG" > "$1/hearts"
  else
    printf '%s' "$DEV" > "$1/hearts"
  fi
  chmod 0400 "$1/hearts"
}

stage "$SECRETS_DIR"
# Fallback: JCasC's Docker secret source defaults to /run/secrets when $SECRETS is unset.
stage /run/secrets 2>/dev/null || true

exec /usr/bin/tini -- /usr/local/bin/jenkins.sh "$@"

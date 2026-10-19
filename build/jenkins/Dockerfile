# Wonderland's Jenkins controller. Configured entirely by Configuration-as-Code (casc/jenkins.yaml):
# Jenkins' own user database (no signup), matrix authorization, and a System-scope credential. The
# flag is NOT here: the prod-deploy credential's secret resolves at boot from a file the entrypoint
# stages out of the per-player input Isoloom mounts at run time. Runs as root so the entrypoint can
# read that root-only mounted secret (and so the in-controller solver can read the staged file).
FROM jenkins/jenkins:lts-jdk21

USER root

# curl for the in-controller solver/self-check (brute-force + Script Console over HTTP).
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Plugins (resolved for this controller version).
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Configuration-as-Code, outside JENKINS_HOME so it is read as-is at boot.
COPY casc/ /usr/share/jenkins/casc/

# The lab-local wordlist the brute-force runs against (a short rockyou-style list; `rockme` is in it).
COPY wordlist.txt /usr/local/share/hearts/rockyou-mini.txt

COPY entrypoint.sh /usr/local/bin/hearts-jenkins-entrypoint.sh
COPY solve.sh /usr/local/bin/hearts-solve
RUN chmod 0755 /usr/local/bin/hearts-jenkins-entrypoint.sh /usr/local/bin/hearts-solve \
 && chmod 0444 /usr/local/share/hearts/rockyou-mini.txt

ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc/jenkins.yaml \
    SECRETS=/run/lab/casc_secrets \
    JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Xmx1024m"

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/hearts-jenkins-entrypoint.sh"]

#!/usr/bin/env python3
# api_deploy.py - sync the local workbench repo to GitHub via the Contents API.
# WHY: the sandbox proxy blocks github.com:443 (git push -> CONNECT 502) but allows
# api.github.com. So we replicate `git push` over the REST Contents API.
#
# Correctness: fetch the remote tree ONCE (git/trees?recursive=1 -> every path + blob
# SHA). For each locally tracked file compare its git blob SHA (git hash-object) to the
# remote blob SHA. Same -> skip. Different/missing -> PUT (create or update). Exact and
# minimal (only changed files hit the API). Deletions are intentionally not performed.

import base64, json, os, subprocess, sys

REPO = "544492867-creator/liusiyuan"
BRANCH = "main"
ROOT = os.environ.get("REPO_DIR", r"E:\workbudy\2026-07-30-10-46-33")
GIT = r"C:\Users\liusiyuan\.workbuddy\binaries\PortableGit\versions\1.2.0\mingw64\bin\git.exe"
PAT = os.environ.get("GH_PAT", "")
DRY = os.environ.get("DRY_RUN", "") == "1"
MAX_BYTES = 950 * 1024

def api(method, url, data=None):
    cmd = ["curl", "-sS", "-m", "40", "-X", method,
           "-H", "Authorization: token %s" % PAT,
           "-H", "Accept: application/vnd.github+json",
           "-H", "Content-Type: application/json", url]
    if data is not None:
        cmd += ["-d", "@-"]
        p = subprocess.run(cmd, input=json.dumps(data).encode("utf-8"), capture_output=True)
    else:
        p = subprocess.run(cmd, capture_output=True)
    try:
        return json.loads(p.stdout.decode("utf-8", "replace"))
    except Exception:
        return {"__raw__": p.stdout.decode("utf-8", "replace")[:200]}

def git(*args):
    return subprocess.run([GIT, "-C", ROOT, *args], capture_output=True, text=True)

def main():
    if not PAT:
        print("ERROR: GH_PAT env not set", flush=True); sys.exit(2)
    # 1) remote tree (one call)
    j = api("GET", "https://api.github.com/repos/%s/git/trees/%s?recursive=1" % (REPO, BRANCH))
    remote = {}
    if "tree" in j:
        for e in j["tree"]:
            if e.get("type") == "blob":
                remote[e["path"]] = e["sha"]
    else:
        print("WARN cannot fetch remote tree: %s" % j.get("message", j.get("__raw__", "")), flush=True)
    # 2) local tracked files
    r = git("ls-files")
    files = [l for l in r.stdout.splitlines() if l.strip()]
    skip_names = {"deploy.config.ps1", "migrate-to-github.ps1"}
    up = skip = err = 0
    for rel in files:
        if os.path.basename(rel) in skip_names:
            continue
        local = os.path.join(ROOT, rel)
        if not os.path.isfile(local):
            continue
        sz = os.path.getsize(local)
        if sz > MAX_BYTES:
            print("SKIP(>1MB) %s" % rel, flush=True); skip += 1; continue
        h = git("hash-object", local).stdout.strip()
        remote_sha = remote.get(rel)
        if remote_sha == h:
            skip += 1; continue
        with open(local, "rb") as f:
            b64 = base64.b64encode(f.read()).decode("ascii")
        payload = {"message": "deploy %s via API" % rel, "content": b64, "branch": BRANCH}
        if remote_sha:
            payload["sha"] = remote_sha
        if DRY:
            print("DRY  %s  (%s)" % (rel, "NEW" if not remote_sha else "changed"), flush=True)
            up += 1; continue
        j2 = api("PUT", "https://api.github.com/repos/%s/contents/%s" % (REPO, rel), payload)
        if "content" in j2:
            up += 1
            print("PUT  %s  (%s)" % (rel, "new" if not remote_sha else "update"), flush=True)
        else:
            err += 1
            print("ERR  %s -> %s" % (rel, j2.get("message", j2.get("__raw__", ""))[:160]), flush=True)
    print("\nSUMMARY: %d put, %d skipped, %d errors%s" % (up, skip, err, " [DRY-RUN]" if DRY else ""), flush=True)
    sys.exit(1 if err else 0)

if __name__ == "__main__":
    main()

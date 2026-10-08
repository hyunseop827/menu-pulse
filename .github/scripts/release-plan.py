#!/usr/bin/env python3
"""Decides what the release job (.github/workflows/release.yml) does for the checked-out commit.

Reads the version from Packaging/Info.plist and the notes from .github/release-notes.md, compares them with the
version tags and GitHub releases, and writes the decision to $GITHUB_OUTPUT.

    python3 .github/scripts/release-plan.py           the release job's decision
    python3 .github/scripts/release-plan.py --check   validation only; CI runs it on every pull request and push, so
                                                      a missing version bump or notes header, a changed update key,
                                                      or an unfinished release shows up before the merge

Run it from the repository root after `git fetch --tags origin` (it needs gh) to see what CI would do with the
current commit; without GITHUB_OUTPUT it prints the decision instead of writing it.
"""
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

REPOSITORY = os.environ.get("GITHUB_REPOSITORY", "hyunseop827/menu-pulse")
IN_CI = os.environ.get("GITHUB_ACTIONS") == "true"
CHECK_ONLY = "--check" in sys.argv[1:]
INFO_PLIST = "Packaging/Info.plist"
NOTES = ".github/release-notes.md"
# Changing any of these after a release needs a new version (AGENTS.md, "This repository").
APP_INPUTS = ["Sources", "Packaging", "Makefile"]
SEMVER = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")
# An Ed25519 public key as Sparkle's generate_keys prints it: 32 bytes in base64.
UPDATE_KEY = re.compile(r"[A-Za-z0-9+/]{43}=")


def fail(message):
    print(f"::error::{message}")
    sys.exit(1)


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def version_tuple(value):
    return tuple(map(int, value.split(".")))


def update_key(plist_bytes):
    key = plistlib.loads(plist_bytes).get("SUPublicEDKey", "")
    return key if isinstance(key, str) and UPDATE_KEY.fullmatch(key) else ""


metadata = plistlib.loads(Path(INFO_PLIST).read_bytes())
version = metadata.get("CFBundleShortVersionString", "")
if not isinstance(version, str) or not SEMVER.fullmatch(version):
    fail(f"CFBundleShortVersionString in {INFO_PLIST} must be X.Y.Z (now {version!r}).")
# Sparkle compares CFBundleVersion; release builds replace it with the CI run number.
build = metadata.get("CFBundleVersion", "")
if not isinstance(build, str) or not re.fullmatch(r"[1-9][0-9]*", build):
    fail(f"CFBundleVersion in {INFO_PLIST} must be a positive integer string (now {build!r}).")
if metadata.get("CFBundleIdentifier") != "dev.hyunseop.MenuPulse":
    fail("Unexpected app bundle identifier.")
tag = f"v{version}"

notes = Path(NOTES).read_text().splitlines() if Path(NOTES).is_file() else []
if not notes or notes[0].strip() != f"# {tag}":
    fail(f"{NOTES} must begin with '# {tag}'.")
body = "\n".join(notes[1:]).strip()
if not body:
    fail(f"{NOTES} needs a description of the changes.")

head = git("rev-parse", "HEAD^{commit}")
if os.environ.get("GITHUB_SHA") and os.environ["GITHUB_SHA"] != head:
    fail("The checkout does not match the validated commit.")
if IN_CI and not CHECK_ONLY:
    git("fetch", "--no-tags", "origin", "+refs/heads/main:refs/remotes/origin/main")
    if subprocess.run(["git", "merge-base", "--is-ancestor", head, "refs/remotes/origin/main"]).returncode != 0:
        fail("Only commits on main are released.")

tags = git("tag", "--list", "v*").splitlines()
# Drafts carry their future tag name too; a failing API call stops here instead of reading as "no release".
pages = json.loads(subprocess.check_output(
    ["gh", "api", "--paginate", "--slurp", f"repos/{REPOSITORY}/releases?per_page=100"], text=True))
releases = [release for page in pages for release in page]

# Never release backwards.
for known in set(tags) | {release["tag_name"] for release in releases}:
    if known.startswith("v") and SEMVER.fullmatch(known[1:]) and version_tuple(known[1:]) > version_tuple(version):
        fail(f"{tag} is older than the existing {known}; raise the version in {INFO_PLIST}.")

# An unfinished release blocks everything else: once a newer tag exists it can no longer be finished (AGENTS.md,
# step 7). A tag is finished when a published release carries its name. Pull requests run with a token that sees no
# drafts, so for them a draft reads as "no release", which counts as unfinished too. This version's own tag is judged
# below, so a re-run of the commit that made it still finishes it.
finished = {release["tag_name"] for release in releases if not release["draft"]}
unfinished = sorted((known for known in tags if known != tag and SEMVER.fullmatch(known[1:]) and known not in finished),
                    key=lambda known: version_tuple(known[1:]))
if unfinished:
    fail(f"The release of {', '.join(unfinished)} is unfinished: no published release carries that tag (it is a draft, "
         "or there is none this token can see). Finish it first with 'Re-run failed jobs' on its commit's run "
         "(AGENTS.md, step 7); merge and release nothing until it is done.")

# In-app updates (Sparkle). An installed copy accepts an update only when its signature fits the SUPublicEDKey that
# copy carries; the app is ad-hoc signed, so there is no second way for it to trust one. A release with another key
# would pass every other check and then be refused by every installed copy. So this commit's key must be the key of
# every published release that shipped with one. Releases before Sparkle (1.7.0 and earlier) have no key, and neither
# has one that shipped with the placeholder.
current_key = update_key(Path(INFO_PLIST).read_bytes())
sparkle_release = ""  # the newest published release, other than this version, that shipped with a key
published = sorted((release for release in releases
                    if not release["draft"] and release["tag_name"] != tag
                    and release["tag_name"].startswith("v") and SEMVER.fullmatch(release["tag_name"][1:])),
                   key=lambda item: version_tuple(item["tag_name"][1:]), reverse=True)  # newest first
for release in published:
    name = release["tag_name"]
    if name not in tags:
        fail(f"Release {name} has no local tag, so its update key cannot be checked. Run `git fetch --tags origin`.")
    listed = subprocess.run(["git", "ls-tree", "--name-only", f"refs/tags/{name}", "--", INFO_PLIST],
                            capture_output=True, text=True)
    if listed.returncode != 0:
        fail(f"Could not read tag {name} to check its update key.")
    if not listed.stdout.strip():
        continue
    released_key = update_key(subprocess.check_output(["git", "show", f"refs/tags/{name}:{INFO_PLIST}"]))
    if not released_key:
        continue
    if released_key != current_key:
        fail(f"SUPublicEDKey in {INFO_PLIST} differs from the key {name} shipped with ({released_key}). Installed "
             "copies only accept updates signed with their own key, so releasing another key would strand every "
             "copy already installed. Only the owner changes this value.")
    sparkle_release = sparkle_release or name
if sparkle_release:
    print(f"OK  SUPublicEDKey is the key {sparkle_release} shipped with.")

# The notes become the release's text and Sparkle's update window. The same text as the latest release's usually
# means they were not written; a maintenance release may repeat them, so this only warns.
if published:
    latest = published[0]["tag_name"]
    shown = subprocess.run(["git", "show", f"refs/tags/{latest}:{NOTES}"], capture_output=True, text=True)
    if shown.returncode == 0 and "\n".join(shown.stdout.splitlines()[1:]).strip() == body:
        print(f"::warning::{NOTES} has the same text as the notes of {latest}. Say what users will notice since "
              f"{latest}, unless this maintenance release really repeats them.")

tag_sha = git("rev-parse", f"refs/tags/{tag}^{{commit}}") if tag in tags else ""
matching = [release for release in releases if release["tag_name"] == tag]
release_state = ("published" if any(not release["draft"] for release in matching)
                 else "draft" if matching else "none")

publish = True
verify = True
if release_state == "published":
    if not tag_sha:
        fail(f"Release {tag} is published, but its tag is missing; cannot check its build inputs.")
    changed = subprocess.run(["git", "diff", "--quiet", tag_sha, head, "--", *APP_INPUTS]).returncode
    if changed == 1:
        fail(f"App files changed after {tag}; raise the version and update {NOTES}.")
    if changed != 0:
        fail(f"Could not compare the app files with {tag}.")
    publish = False
    # A re-run of the commit that published it checks the download again.
    verify = tag_sha == head
    print(f"{tag} is already published and the app has not changed since; nothing to release.")
elif tag_sha and tag_sha != head:
    fail(f"Unpublished tag {tag} belongs to another commit ({tag_sha[:7]}); tags are never moved. Finish it with "
         "'Re-run failed jobs' on that commit's run, or raise the version.")
else:
    when = "once on main, " if CHECK_ONLY else ""
    print(f"{when}{tag} will be released (tag: {'yes' if tag_sha else 'no'}, release: {release_state}).")

if CHECK_ONLY:
    sys.exit(0)

outputs = {
    "version": version,
    "tag": tag,
    "publish": str(publish).lower(),
    "verify": str(verify).lower(),
    "tag_exists": str(bool(tag_sha)).lower(),
    "release_state": release_state,
    "sparkle_release": sparkle_release,
}
if os.environ.get("GITHUB_OUTPUT"):
    with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
        stream.writelines(f"{name}={value}\n" for name, value in outputs.items())
else:
    print(outputs)
if publish and os.environ.get("RUNNER_TEMP"):
    temp = Path(os.environ["RUNNER_TEMP"])
    notice = ("Apple Silicon arm64 build. Ad-hoc signed, not notarized; macOS Gatekeeper may show a warning on "
              "first launch.\n\nAlready using Menu Pulse 1.7.0 or later? Click Check for Updates… in Settings instead.")
    (temp / "menu-pulse-release-body.md").write_text(f"{body}\n\n{notice}\n")
    # Sparkle's update window shows the notes alone.
    (temp / "menu-pulse-appcast-notes.md").write_text(f"{body}\n")

"""Publish a locally signed update using the repository's Actions token."""

import base64
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def gh(*args, payload=None, allow_missing=False):
    command = ["gh", *args]
    if payload is not None:
        command.extend(["--input", "-"])
    result = subprocess.run(
        command, input=json.dumps(payload) if payload is not None else None,
        capture_output=True, text=True, check=False, timeout=180,
    )
    if result.returncode:
        if allow_missing and "HTTP 404" in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip() or "GitHub command failed")
    return json.loads(result.stdout) if result.stdout.strip() else None


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def find_release(api_root, tag):
    # Drafts do not necessarily have a Git tag yet and are absent from /releases/tags.
    matches = [release for release in gh("api", api_root + "/releases?per_page=100")
               if release["tag_name"] == tag]
    if len(matches) > 1:
        raise RuntimeError("Multiple releases use the requested tag")
    return matches[0] if matches else None


def main():
    meta = json.loads((ROOT / "release.json").read_text(encoding="utf-8"))
    repo = meta["repository"]
    if repo != "saintwork134/tg-updates":
        raise ValueError("Unexpected target repository")
    if os.environ.get("GITHUB_REPOSITORY", repo) != repo:
        raise ValueError("Workflow repository does not match release metadata")
    asset = ROOT / meta["asset_name"]
    manifest = ROOT / "remote_manifest.next.signed"
    if asset.stat().st_size != meta["asset_size"] or sha256(asset) != meta["asset_sha256"]:
        raise ValueError("Release ZIP checksum does not match")
    if sha256(manifest) != meta["manifest_sha256"]:
        raise ValueError("Signed manifest checksum does not match")
    if "--validate-only" in sys.argv:
        print("Local release files verified")
        return

    tag = "v" + meta["version"]
    api_root = "repos/" + repo
    current = gh("api", api_root + "/contents/remote_manifest.signed?ref=main")
    if current["sha"] != meta["base_manifest_sha"]:
        if base64.b64decode(current["content"]).strip() == manifest.read_bytes().strip():
            print("Release manifest already published")
            return
        raise RuntimeError("Main manifest changed; refresh and re-sign locally before publishing")

    release = find_release(api_root, tag)
    if release is None:
        subprocess.run([
            "gh", "release", "create", tag, str(asset), "--repo", repo,
            "--draft", "--target", "main", "--title", tag,
            "--notes-file", str(ROOT / "release_notes.txt"),
        ], check=True, timeout=300)
    else:
        matching = [item for item in release["assets"] if item["name"] == asset.name]
        if not matching:
            if not release["draft"]:
                raise RuntimeError("Existing published release is missing the expected asset")
            subprocess.run(["gh", "release", "upload", tag, str(asset), "--repo", repo],
                           check=True, timeout=300)

    release = find_release(api_root, tag)
    if release is None:
        raise RuntimeError("Release was not found after upload")
    matching = [item for item in release["assets"] if item["name"] == asset.name]
    if len(matching) != 1:
        raise RuntimeError("Expected exactly one update asset")
    uploaded = matching[0]
    if (uploaded["state"] != "uploaded" or uploaded["size"] != meta["asset_size"]
            or uploaded.get("digest") != "sha256:" + meta["asset_sha256"]):
        raise RuntimeError("Uploaded asset is incomplete or its checksum differs")

    subprocess.run(["gh", "release", "edit", tag, "--repo", repo,
                    "--draft=false", "--latest"], check=True, timeout=60)
    result = gh("api", api_root + "/contents/remote_manifest.signed", "--method", "PUT", payload={
        "message": "Update remote manifest to " + tag,
        "sha": meta["base_manifest_sha"],
        "branch": "main",
        "content": base64.b64encode(manifest.read_bytes()).decode("ascii"),
    })
    print("Published:", release["html_url"])
    print("Manifest commit:", result["commit"]["sha"])


if __name__ == "__main__":
    main()

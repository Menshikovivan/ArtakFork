#!/usr/bin/env python3
"""Verify pinned releases against latest, then preserve their public assets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.request


def fetch(url, authenticated=False):
    headers = {"User-Agent": "ArtakFork-release", "Accept": "application/vnd.github+json"}
    if authenticated and os.environ.get("GH_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["GH_TOKEN"]
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=180) as response:
        return response.read()


def api(path):
    return json.loads(fetch("https://api.github.com/repos/" + path, True))


def constant(text, name):
    matches = re.findall(r"^" + re.escape(name) + r"=['\"]?([0-9A-Za-z.+-]+)['\"]?\s*$", text, re.M)
    if len(matches) != 1:
        raise ValueError("Expected one literal installer constant: " + name)
    return matches[0]


def prepare(installer, output, check_only=False):
    text = installer.read_text(encoding="utf-8")
    forkop = constant(text, "BASE_VERSION")
    extended = constant(text, "ENGINE_VERSION")
    specifications = [
        ("ushan0v/forkop", forkop, [
            (f"{package}_{forkop}.apk", f"upstream-{package}_{forkop}.apk")
            for package in ("forkop", "luci-app-forkop", "luci-i18n-forkop-ru")
        ], "upstream-forkop-source.tar.gz"),
        ("shtorm-7/sing-box-extended", "v" + extended, [
            (f"sing-box-extended_{extended}_openwrt_aarch64_cortex-a53.apk",
             f"sing-box-extended_{extended}_openwrt_aarch64_cortex-a53.apk")
        ], "sing-box-extended-source.tar.gz"),
    ]
    provenance = {"schema": 1, "releases": []}
    for repo, tag, packages, source_name in specifications:
        release = api(repo + "/releases/latest")
        if release.get("tag_name") != tag or release.get("draft") or release.get("prerelease"):
            raise ValueError(f"{repo}: latest stable differs from installer pin {tag}; review and update pins")
        commit = api(repo + "/commits/" + tag)["sha"]
        if not re.fullmatch(r"[0-9a-f]{40}", commit):
            raise ValueError("Invalid source commit")
        record = {"repository": repo, "tag": tag, "commit": commit,
                  "source_url": f"https://github.com/{repo}/tree/{commit}", "assets": []}
        for original, filename in packages:
            matches = [a for a in release["assets"] if a["name"] == original]
            if len(matches) != 1:
                raise ValueError(f"Missing or ambiguous asset {repo}/{original}")
            asset = matches[0]
            digest = asset.get("digest", "")
            if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
                raise ValueError("GitHub asset SHA256 missing: " + original)
            url = asset["browser_download_url"]
            expected = f"https://github.com/{repo}/releases/download/{tag}/{original}"
            if url != expected:
                raise ValueError("Unexpected asset URL: " + url)
            record["assets"].append({"original_asset": original, "filename": filename,
                                     "url": url, "digest": digest, "bytes": asset["size"]})
            if not check_only:
                data = fetch(url)
                if len(data) != asset["size"] or hashlib.sha256(data).hexdigest() != digest[7:]:
                    raise ValueError("Asset size or SHA256 mismatch: " + original)
                (output / filename).write_bytes(data)
        source_url = f"https://codeload.github.com/{repo}/tar.gz/{commit}"
        if not check_only:
            source = fetch(source_url)
            (output / source_name).write_bytes(source)
            record["source_archive"] = {"filename": source_name, "url": source_url,
                "bytes": len(source), "digest": "sha256:" + hashlib.sha256(source).hexdigest()}
        provenance["releases"].append(record)
        print(f"Verified latest stable {repo} {tag} ({commit})")
    if not check_only:
        (output / "bootstrap-sources.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--installer", type=Path, default=Path("artak-install.sh"))
    parser.add_argument("--output", type=Path, default=Path("filtered-bin/artak-release"))
    parser.add_argument("--check-latest", action="store_true")
    args = parser.parse_args()
    if not args.check_latest:
        args.output.mkdir(parents=True, exist_ok=True)
    prepare(args.installer, args.output, args.check_latest)

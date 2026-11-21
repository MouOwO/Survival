"""Check the fixed public download page against the verified Workshop release."""
from __future__ import annotations
import argparse
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import ssl
import sys
import urllib.request
from urllib.parse import urljoin


TOOLS = Path(__file__).resolve().parents[1]
URL = "https://xiaofengnet.com/launcher/"
WORKSHOP = "3824360109"
EXE_LINK = re.compile(r"\./([0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,4})/(GoufayuLauncher-[0-9]{8}\.[0-9]{1,4}\.exe)")


class DownloadPage(HTMLParser):
    def __init__(self, raw):
        super().__init__()
        self.links = []
        self.feed(raw.decode("utf-8"))

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            link = EXE_LINK.fullmatch(dict(attrs).get("href") or "")
            if link:
                self.links.append(link.groups())


def release_identity(project):
    sys.path.insert(0, str(TOOLS))
    from release_packager.core import baseline, digest, git, read
    parent = baseline(project)
    base, report = parent["baseline"], parent["report"]
    if report.get("public_admission_enabled") is not True:
        raise ValueError("public_workshop_release_required")
    receipt = Path(base["complete_delivery"]["receipt_path"])
    if digest(receipt.read_bytes()) != base["complete_delivery"]["receipt_sha256"]:
        raise ValueError("official_download_receipt_changed")
    check = read(receipt)
    sequence, manifest = base["parent_sequence"], base["official_parent_manifest"]
    if (check.get("status") != "OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED"
            or check["steam_manifest"] != manifest or check["release_sequence"] != sequence):
        raise ValueError("official_download_binding_changed")
    helper = git(project, "show", report["source_revisions"]["game"] + ":tools/workshop_test/file_http_bridge.py")
    return {"release_sequence": sequence, "steam_manifest": manifest, "workshop_id": WORKSHOP,
            "package_files": report["package_files"], "helper_sha256": digest(helper), "access_mode": "public"}


def verify_binding(observed, expected):
    return all(observed.get(key) == value for key, value in expected.items())


class FixedOrigin(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *unused, **options):
        raise ValueError("unexpected_launcher_redirect")


def read_public(opener, url, limit):
    request = urllib.request.Request(url, headers={"Cache-Control": "no-cache"})
    with opener.open(request, timeout=15) as response:
        if response.status != 200:
            raise ValueError("launcher_download_unavailable")
        result = response.read(limit + 1)
    if len(result) > limit:
        raise ValueError("launcher_download_exceeds_budget")
    return result


def inspect_public(expected):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), FixedOrigin(),
                                         urllib.request.HTTPSHandler(context=ssl.create_default_context()))
    page = read_public(opener, URL, 64 * 1024)
    links = DownloadPage(page).links
    if len(links) != 1:
        raise ValueError("exact_one_official_launcher_required")
    version, exe = links[0]
    root = urljoin(URL, version + "/")
    binding = json.loads(read_public(opener, root + "version.json", 128 * 1024))
    if binding.get("version") != version or binding.get("exe") != exe:
        raise ValueError("launcher_page_and_version_differ")
    result = {"status": "LAUNCHER_OUT_OF_SYNC", "version": version,
              "release_sequence": binding["release_sequence"], "steam_manifest": binding["steam_manifest"],
              "index_sha256": hashlib.sha256(page).hexdigest()}
    if not verify_binding(binding, expected):
        return result
    size = binding.get("bytes")
    if type(size) is not int or not 1 <= size <= 64 * 1024 * 1024:
        raise ValueError("invalid_launcher_byte_count")
    raw = read_public(opener, root + exe, size)
    digest = hashlib.sha256(raw).hexdigest()
    if size != len(raw) or digest != binding.get("sha256"):
        raise ValueError("official_launcher_exe_changed")
    return dict(result, status="LAUNCHER_SYNCED", exe_sha256=digest, bytes=size)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=TOOLS.parent)
    parser.add_argument("--release-sequence", required=True, type=int)
    parser.add_argument("--steam-manifest", required=True)
    args = parser.parse_args()
    expected = release_identity(args.project)
    if (args.release_sequence, args.steam_manifest) != (expected["release_sequence"], expected["steam_manifest"]):
        raise ValueError("launcher_check_target_is_no_longer_current")
    print(json.dumps(inspect_public(expected), sort_keys=True))


if __name__ == "__main__":
    main()

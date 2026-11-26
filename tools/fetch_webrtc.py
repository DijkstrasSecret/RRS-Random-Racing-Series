"""Downloads the webrtc-native GDExtension that desktop builds need for WebRTC.

    python tools/fetch_webrtc.py

Web builds use the browser's own WebRTC and don't need it. The release is
pinned and its SHA-256 checked. Only the x86_64 Linux and Windows libraries
(debug and release), the .gdextension file and the licences are extracted,
into addons/webrtc_native/ (git-ignored). Does nothing if they're already
there. Afterwards Godot must import the project once so it registers the
extension: `make webrtc` does both steps.
"""
import hashlib
import io
import sys
import urllib.request
import zipfile
from pathlib import Path

VERSION = "1.2.2-stable"
URL = f"https://github.com/godotengine/webrtc-native/releases/download/{VERSION}/godot-extension-webrtc_native.zip"
SHA256 = "98e9446921740d995bd9ca1be48798dc3c2ceed51e044a25ce18b3cff11f56e5"
ROOT = Path(__file__).resolve().parent.parent
ADDON = "addons/webrtc_native/"
LIBS = [
    f"{ADDON}lib/libwebrtc_native.{platform}.template_{build}.x86_64.{ext}"
    for platform, ext in (("linux", "so"), ("windows", "dll"))
    for build in ("debug", "release")
]


def wanted(name: str) -> bool:
    return name in LIBS or name == f"{ADDON}webrtc_native.gdextension" or (
        name.startswith(f"{ADDON}LICENSE") and not name.endswith("/"))


def main() -> int:
    if all((ROOT / n).exists() for n in [*LIBS, f"{ADDON}webrtc_native.gdextension"]):
        print(f"webrtc-native {VERSION} already in {ADDON}")
        return 0
    print(f"downloading webrtc-native {VERSION} ...")
    with urllib.request.urlopen(URL, timeout=120) as response:
        data = response.read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != SHA256:
        print(f"SHA-256 mismatch: got {digest}, want {SHA256}", file=sys.stderr)
        return 1
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        names = [n for n in z.namelist() if wanted(n)]
        for n in names:
            z.extract(n, ROOT)
    missing = [n for n in LIBS if not (ROOT / n).exists()]
    if missing:
        print(f"release is missing: {missing}", file=sys.stderr)
        return 1
    print(f"extracted {len(names)} files into {ADDON}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

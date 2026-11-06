"""Fetch fixed public upstream assets into the new Mnemo project only."""
import io
import json
import pathlib
import tarfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]

def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mnemo-build"}), timeout=60).read()

def write(relative, data):
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)

raw = get("https://registry.npmjs.org/katex/-/katex-0.16.22.tgz")
with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as archive:
    for member in archive.getmembers():
        name = member.name
        if member.isfile() and (name in ("package/dist/katex.min.js", "package/dist/katex.min.css", "package/LICENSE") or name.startswith("package/dist/fonts/") and name.endswith(".woff2")):
            target = "Resources/Math/" + name.replace("package/dist/", "").replace("package/", "")
            write(target, archive.extractfile(member).read())
print("KaTeX 0.16.22 downloaded")

raw = get("https://codeload.github.com/facebook/zstd/tar.gz/refs/tags/v1.5.7")
with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as archive:
    for member in archive.getmembers():
        name = "/".join(member.name.split("/")[1:])
        if member.isfile() and (name in ("LICENSE", "COPYING", "lib/zstd.h", "lib/zstd_errors.h") or name.startswith(("lib/common/", "lib/decompress/")) and name.endswith((".c", ".h"))):
            write("Vendor/zstd/" + name.removeprefix("lib/"), archive.extractfile(member).read())
print("Zstandard 1.5.7 decompression sources downloaded")

write("docs/upstream/anki-import-export.proto", get("https://raw.githubusercontent.com/ankitects/anki/main/proto/anki/import_export.proto"))
write("docs/upstream/anki-schema.sql", get("https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/storage/schema11.sql"))
print("Anki format references downloaded")

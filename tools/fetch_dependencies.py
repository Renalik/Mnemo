"""Fetch public, pinned upstream source and reference docs; never reads credentials."""
import json
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]

def get(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Mnemo-build"})
    return urllib.request.urlopen(request, timeout=45).read()

repo = "open-spaced-repetition/swift-fsrs"
commit = json.loads(get(f"https://api.github.com/repos/{repo}/commits/main"))["sha"]
tree = json.loads(get(f"https://api.github.com/repos/{repo}/git/trees/{commit}?recursive=1"))
for entry in tree["tree"]:
    name = entry["path"]
    if entry["type"] == "blob" and (name.startswith("Sources/") or name in ("Package.swift", "LICENSE", "README.md")):
        path = ROOT / "Vendor" / "swift-fsrs" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(get(f"https://raw.githubusercontent.com/{repo}/{commit}/{name}"))
metadata = {"FSRS": {"repository": f"https://github.com/{repo}", "revision": commit}}
(ROOT / "Vendor" / "provenance.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
print("Pinned swift-fsrs", commit)
docs = {
    "gemini-function-calling.md": "https://ai.google.dev/gemini-api/docs/function-calling",
    "gemini-models.md": "https://ai.google.dev/api/models",
    "liquid-glass.md": "https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views.md",
}
for name, url in docs.items():
    try:
        path = ROOT / "docs" / "upstream" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(get(url))
        print("Reference:", name)
    except Exception as error:
        print("Reference unavailable:", name, type(error).__name__)

"""Local structural checks. Does not pretend to compile or run iOS on Windows."""
import json
import pathlib
import plistlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'python_packages'))
import yaml
import tree_sitter
import tree_sitter_swift

parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
failures = []
swift_files = list((ROOT / 'App').rglob('*.swift')) + list((ROOT / 'Core').rglob('*.swift')) + list((ROOT / 'Shared').rglob('*.swift')) + list((ROOT / 'Widgets').rglob('*.swift')) + list((ROOT / 'Tests').rglob('*.swift'))
for path in swift_files:
    source = path.read_bytes()
    tree = parser.parse(source)
    def walk(node):
        if node.type == 'ERROR' or node.is_missing:
            row, column = node.start_point
            failures.append(f'{path.relative_to(ROOT)}:{row+1}:{column+1}: {node.type} {source[node.start_byte:node.end_byte][:140]!r}')
        for child in node.children:
            walk(child)
    walk(tree.root_node)

for path in (ROOT / 'Config').glob('*'):
    if path.suffix in ('.plist', '.entitlements'):
        with path.open('rb') as file: plistlib.load(file)
for path in [ROOT / 'project.yml', ROOT / 'project-widgets.yml', ROOT / '.github/workflows/build-ios.yml']:
    yaml.safe_load(path.read_text(encoding='utf-8'))

models = (ROOT / 'Core/Themes.swift').read_text(encoding='utf-8')
assert len(re.findall(r'\.init\(id:', models)) == 26, 'App theme count'
assert '.map { CardTheme(id: $0) }' in models and '(0..<150)' in models, 'Card theme count'
assert (ROOT / 'Resources/Math/katex.min.js').is_file(), 'Missing KaTeX'
assert len(list((ROOT / 'Resources/Math/fonts').glob('*.woff2'))) > 10, 'Missing fonts'
assert (ROOT / 'Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png').is_file(), 'Missing app icon'
assert (ROOT / 'Vendor/zstd/decompress/zstd_decompress.c').is_file(), 'Missing zstd'
for path in swift_files:
    text = path.read_text(encoding='utf-8')
    assert not re.search(r'AIza[0-9A-Za-z_-]{25,}', text), f'Possible API key: {path}'
    assert not re.search(r'\d{8,12}:[A-Za-z0-9_-]{25,}', text), f'Possible bot token: {path}'

report = {'swift_files_parsed': len(swift_files), 'syntax_errors': failures, 'plist_and_yaml_valid': True,
          'app_themes': 26, 'card_themes': 150, 'ios_compilation': 'Requires GitHub Actions / Xcode; not performed by this script'}
out = ROOT / 'docs/checks-local.json'
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(1 if failures else 0)

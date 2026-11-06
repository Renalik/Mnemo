import argparse
import json
import pathlib
import plistlib
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('path', type=pathlib.Path)
parser.add_argument('--widgets', action='store_true')
args = parser.parse_args()
with zipfile.ZipFile(args.path) as archive:
    names = archive.namelist()
    root = 'Payload/Mnemo.app/'
    info = plistlib.loads(archive.read(root + 'Info.plist'))
    assert info['CFBundleIdentifier'] == 'app.renalik.mnemo'
    assert info['MinimumOSVersion'] == '26.0'
    assert root + 'Math/equation.html' in names, 'Missing offline formula renderer'
    assert root + 'Math/katex.min.js' in names, 'Missing KaTeX'
    assert len([name for name in names if name.startswith(root + 'Math/fonts/') and name.endswith('.woff2')]) >= 10, 'Missing math fonts'
    assert root + 'Assets.car' in names, 'Missing app assets'
    assert info.get('CFBundleIcons'), 'Missing compiled app icon'
    executable = archive.read(root + info['CFBundleExecutable'])
    assert executable[:4] == b'\xcf\xfa\xed\xfe', 'Expected 64-bit Mach-O executable'
    if args.widgets:
        assert root + 'PlugIns/MnemoWidgets.appex/Info.plist' in names, 'Missing widget extension'
print(json.dumps({'ipa':str(args.path),'bytes':args.path.stat().st_size,'iOS':info['MinimumOSVersion'], 'offline_math':True,'icon':True,'widgets':args.widgets}, indent=2))

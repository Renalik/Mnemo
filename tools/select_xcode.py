import glob
import re
import subprocess

candidates = []
for path in glob.glob('/Applications/Xcode*.app/Contents/Developer'):
    try:
        result = subprocess.run(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'], env={**__import__('os').environ, 'DEVELOPER_DIR': path}, text=True, capture_output=True, check=True)
        version = tuple(map(int, re.findall(r'\d+', result.stdout.strip())))
        if version >= (26,): candidates.append((version, path))
    except subprocess.CalledProcessError:
        pass
if not candidates:
    raise SystemExit('No Xcode with iOS 26+ SDK is installed on this runner.')
chosen = sorted(candidates, reverse=True)[0][1]
subprocess.run(['sudo', 'xcode-select', '-s', chosen], check=True)
print(chosen)

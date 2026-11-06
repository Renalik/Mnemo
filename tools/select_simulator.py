import json
import subprocess

devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))['devices']
for runtime, entries in sorted(devices.items(), reverse=True):
    if 'iOS-26' not in runtime:
        continue
    iphones = [device for device in entries if 'iPhone' in device['name'] and device.get('isAvailable')]
    if iphones:
        selected = next((device for device in iphones if 'iPhone 17' == device['name']), iphones[0])
        print(selected['udid'])
        break
else:
    raise SystemExit('No available iOS 26 iPhone simulator found.')

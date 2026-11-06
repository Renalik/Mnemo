"""Inspect/download Mnemo Actions results using Git's existing login.

No credential is logged, written to the project, or sent to another host.
Only read requests against the explicitly configured public repository are made.
"""
import argparse
import json
import pathlib
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import zipfile
import io

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE = 'https://api.github.com/repos/Renalik/Mnemo'

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def credential():
    result = subprocess.run(['git', '-c', 'credential.interactive=false', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n', text=True, capture_output=True)
    values = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    return values.get('password')

def request(path, *, authenticate=False):
    url = BASE + path
    headers = {'User-Agent':'Mnemo-build', 'Accept':'application/vnd.github+json', 'X-GitHub-Api-Version':'2022-11-28'}
    if authenticate:
        token = credential()
        if not token: raise SystemExit('GitHub login is not available. No credential was printed.')
        headers['Authorization'] = 'Bearer ' + token
    assert urllib.parse.urlparse(url).hostname == 'api.github.com'
    try:
        return urllib.request.build_opener(NoRedirect()).open(urllib.request.Request(url, headers=headers), timeout=45).read()
    except urllib.error.HTTPError as error:
        if error.code in (301,302,303,307,308):
            location = error.headers.get('Location', '')
            parsed = urllib.parse.urlparse(location)
            if parsed.scheme != 'https' or not parsed.hostname or not (parsed.hostname.endswith('.githubusercontent.com') or parsed.hostname.endswith('.blob.core.windows.net') or parsed.hostname.endswith('.github.com') or parsed.hostname == 'github.com' or parsed.hostname.endswith('.actions.githubusercontent.com')):
                raise SystemExit('Unexpected artifact host; download stopped without sending credentials.')
            # A signed artifact URL needs no Authorization header. Use a fresh request.
            return urllib.request.urlopen(urllib.request.Request(location, headers={'User-Agent':'Mnemo-build'}), timeout=60).read()
        raise SystemExit('GitHub HTTP ' + str(error.code)) from None

parser = argparse.ArgumentParser()
parser.add_argument('action', choices=['runs','jobs','logs','artifacts','download'])
parser.add_argument('--id', type=int)
args = parser.parse_args()
if args.action == 'runs':
    data = json.loads(request('/actions/runs?per_page=5'))
    print(json.dumps([{'id': r['id'], 'sha':r['head_sha'], 'status':r['status'], 'conclusion':r['conclusion'], 'url':r['html_url']} for r in data['workflow_runs']], indent=2))
elif args.action == 'jobs':
    data = json.loads(request(f'/actions/runs/{args.id}/jobs'))
    print(json.dumps([{'id':j['id'],'name':j['name'],'status':j['status'],'conclusion':j['conclusion'],'steps':[{'name':s['name'],'status':s['status'],'conclusion':s.get('conclusion')} for s in j.get('steps',[])]} for j in data['jobs']], indent=2))
elif args.action == 'artifacts':
    data = json.loads(request(f'/actions/runs/{args.id}/artifacts'))
    print(json.dumps([{'id':a['id'],'name':a['name'],'size':a['size_in_bytes']} for a in data['artifacts']], indent=2))
elif args.action == 'logs':
    raw = request(f'/actions/jobs/{args.id}/logs', authenticate=True)
    path = ROOT / 'docs/build-logs' / f'job-{args.id}.txt'; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
    lines = raw.decode('utf-8',errors='replace').splitlines()
    relevant = [line for line in lines if any(x in line.lower() for x in ['error:', 'failed', 'executed ', 'passed', 'test suite', 'warning:'])]
    print('\n'.join(relevant[-100:]))
elif args.action == 'download':
    raw = request(f'/actions/artifacts/{args.id}/zip', authenticate=True)
    destination = ROOT / 'build/downloads' / str(args.id); destination.mkdir(parents=True, exist_ok=True)
    archive = zipfile.ZipFile(io.BytesIO(raw))
    for info in archive.infolist():
        if info.is_dir(): continue
        target = (destination / info.filename).resolve()
        if not target.is_relative_to(destination.resolve()): raise SystemExit('Unsafe artifact path')
        target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(archive.read(info))
    print(str(destination))

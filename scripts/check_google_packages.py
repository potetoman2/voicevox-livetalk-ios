"""Check pinned official wrapper versions and their published binary checksums."""
import argparse, json
from pathlib import Path

EXPECTED={
 'swift-package-manager-google-mobile-ads': ('13.11.0','310516d18f0d600c9e45ed42b955a6b8ec52108d380f7cd8ed1e424e9d3fec22'),
 'swift-package-manager-google-user-messaging-platform': ('3.1.0','90fe6bf3b0f4ce0d0199628c0871de58b6f673375148b98d52348aecc86db231'),
}
parser=argparse.ArgumentParser();parser.add_argument('source_packages',type=Path);parser.add_argument('resolved',type=Path);args=parser.parse_args()
pins=json.loads(args.resolved.read_text())['pins'];report=[]
for name,(version,digest) in EXPECTED.items():
    found=[v for v in pins if v.get('identity')==name]
    if len(found)!=1 or found[0]['state'].get('version')!=version or found[0].get('location','').rstrip('.git') != 'https://github.com/googleads/'+name:
        raise SystemExit('Unexpected Google Swift Package resolution: '+name)
    content=(args.source_packages/'checkouts'/name/'Package.swift').read_text()
    if digest not in content or 'https://dl.google.com/googleadmobadssdk/' not in content:
        raise SystemExit('Official binary checksum differs: '+name)
    report.append({'package':name,'version':version,'revision':found[0]['state']['revision'],'binary_sha256':digest})
print(json.dumps(report,indent=2))

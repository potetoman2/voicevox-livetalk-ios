"""Read the shipped app and SDK privacy declarations without extracting the IPA.

This inventory is evidence for review, not an App Privacy answer or a traffic test.
Vendor declarations must remain unchanged, including their tracking declarations.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import plistlib
import stat
import zipfile
from pathlib import Path, PurePosixPath

MAX_METADATA_BYTES = 2 * 1024 * 1024
REQUIRED_MANIFESTS = (
    'PrivacyInfo.xcprivacy',
    'Frameworks/GoogleMobileAds.framework/PrivacyInfo.xcprivacy',
    'Frameworks/UserMessagingPlatform.framework/PrivacyInfo.xcprivacy',
)
ACTIVATION_KEYS = ('LTPlanUsageEnabled', 'LTCommerceEnabled', 'LTRevenueAdsEnabled',
                   'LTExperimentalChatEnabled', 'LTCarPlayEnabled')


def _array(value, key):
    result = value.get(key, [])
    if not isinstance(result, list):
        raise ValueError(f'{key} must be an array')
    return result


def _strings(value, key):
    result = _array(value, key)
    if any(not isinstance(s, str) or not s.strip() for s in result):
        raise ValueError(f'{key} must contain nonempty strings')
    return sorted(set(result))


def _bool(value, key, *, required=False):
    if key not in value and not required:
        return None
    result = value.get(key)
    if type(result) is not bool:
        raise ValueError(f'{key} must be a boolean')
    return result


def _text(value, key):
    result = value.get(key)
    if not isinstance(result, str) or not result.strip():
        raise ValueError(f'{key} must be nonempty text')
    return result


def read_manifest(raw):
    value = plistlib.loads(raw)
    if not isinstance(value, dict):
        raise ValueError('Privacy manifest must be a dictionary')
    collected, accessed = [], []
    for row in _array(value, 'NSPrivacyCollectedDataTypes'):
        if not isinstance(row, dict):
            raise ValueError('Collected data entry must be a dictionary')
        purposes = _strings(row, 'NSPrivacyCollectedDataTypePurposes')
        if not purposes:
            raise ValueError('Collected data entry has no purpose')
        collected.append({'type': _text(row, 'NSPrivacyCollectedDataType'),
            'linked': _bool(row, 'NSPrivacyCollectedDataTypeLinked', required=True),
            'tracking': _bool(row, 'NSPrivacyCollectedDataTypeTracking', required=True),
            'purposes': purposes})
    for row in _array(value, 'NSPrivacyAccessedAPITypes'):
        if not isinstance(row, dict):
            raise ValueError('Accessed API entry must be a dictionary')
        reasons = _strings(row, 'NSPrivacyAccessedAPITypeReasons')
        if not reasons:
            raise ValueError('Accessed API entry has no reason')
        accessed.append({'type': _text(row, 'NSPrivacyAccessedAPIType'), 'reasons': reasons})
    return {'tracking_declared': _bool(value, 'NSPrivacyTracking'),
            'tracking_domains': _strings(value, 'NSPrivacyTrackingDomains'),
            'collected_data': collected, 'accessed_apis': accessed}


def audit_ipa(path):
    with path.open('rb') as source:
        ipa_hash = hashlib.file_digest(source, 'sha256').hexdigest()
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        if len(entries) > 20000:
            raise ValueError('Too many IPA entries')
        names = [entry.filename for entry in entries]
        if len(names) != len(set(names)):
            raise ValueError('Duplicate IPA paths are ambiguous')
        for entry in entries:
            # ZipInfo normalizes separators on Windows and truncates NULs.
            # Validate the stored original as well as the interpreted path.
            for name in (entry.orig_filename, entry.filename):
                parts = PurePosixPath(name).parts
                if name.startswith('/') or '\\' in name or ':' in name or '\x00' in name or any(p in ('.', '..') for p in name.split('/')):
                    raise ValueError('Unsafe IPA path')
                if not parts:
                    raise ValueError('Empty IPA path')
        roots = [n.removesuffix('Info.plist') for n in names
                 if len(PurePosixPath(n).parts) == 3
                 and n.startswith('Payload/') and n.endswith('.app/Info.plist')]
        if len(roots) != 1:
            raise ValueError('Expected exactly one main app')
        root = roots[0]

        def read_metadata(name):
            entry = archive.getinfo(name)
            if entry.file_size > MAX_METADATA_BYTES or stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError('Metadata is oversized or a symbolic link')
            return archive.read(entry)  # ZIP CRC is verified for every inspected entry.

        info = plistlib.loads(read_metadata(root + 'Info.plist'))
        if not isinstance(info, dict) or info.get('CFBundleIdentifier') != 'jp.livetalk.mobile':
            raise ValueError('This audit requires the LiveTalk app bundle')
        for key in ACTIVATION_KEYS:
            _bool(info, key, required=True)
        for name in REQUIRED_MANIFESTS:
            if root + name not in names:
                raise ValueError(f'Missing required manifest: {name}')
        manifests = []
        for name in sorted(n for n in names if n.startswith(root) and n.endswith('/PrivacyInfo.xcprivacy')):
            raw = read_metadata(name)
            manifests.append({'path': name[len(root):], 'sha256': hashlib.sha256(raw).hexdigest(),
                              **read_manifest(raw)})
        # Keep each source's declaration. Do not flatten away linked/tracking differences.
        types = sorted({row['type'] for m in manifests for row in m['collected_data']})
        collected = [{'type': kind, 'declarations': [
            {'manifest': m['path'], **row} for m in manifests for row in m['collected_data']
            if row['type'] == kind]} for kind in types]
        declared_tracking = any(m['tracking_declared'] is True or m['tracking_domains']
            or any(r['tracking'] for r in m['collected_data']) for m in manifests)
        notices = []
        for name in sorted(n for n in names if n.startswith(root)
                           and ('/licenses/' in n or n.endswith('/NOTICE.txt')
                                or n.endswith('/google-notices.txt'))):
            entry = archive.getinfo(name)
            if entry.is_dir():
                continue
            raw = read_metadata(name)
            notices.append({'path': name[len(root):], 'bytes': len(raw),
                            'sha256': hashlib.sha256(raw).hexdigest()})
        return {'schema': 1, 'ipa_sha256': ipa_hash, 'ipa_bytes': path.stat().st_size,
            'bundle_id': info['CFBundleIdentifier'], 'version': info.get('CFBundleShortVersionString'),
            'build': info.get('CFBundleVersion'),
            'activation_flags': {key: info[key] for key in ACTIVATION_KEYS},
            'manifests': manifests, 'collected_data_inventory': collected,
            'bundled_license_files': notices,
            'tracking_declared_by_any_component': bool(declared_tracking),
            'review': {'app_privacy_answers_finalized': False, 'real_device_traffic_verified': False,
                       'att_and_vendor_tracking_review_required': bool(declared_tracking)},
            'limits': ['Declarations describe capabilities and may differ from configured traffic.',
                       'No SDK declaration was changed. Do not claim zero collection or no tracking from app settings alone.',
                       'Required-reason validity, contracts, runtime traffic and App Privacy answers need separate review.',
                       'This report is not a vulnerability scan, legal clearance or an Apple approval.']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = audit_ipa(args.ipa)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'manifests': len(report['manifests']),
                      'data_types': len(report['collected_data_inventory']),
                      'tracking_review_required': report['tracking_declared_by_any_component'],
                      'app_privacy_answers_finalized': False}))

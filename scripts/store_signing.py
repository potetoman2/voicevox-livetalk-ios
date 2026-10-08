"""Validate an Apple distribution profile before using signing credentials."""
from __future__ import annotations
import argparse
import base64
import datetime as dt
import hashlib
import plistlib
import re
from pathlib import Path

BUNDLE_ID = 'jp.livetalk.mobile'


def validate_profile(profile, team_id, identities, *, keychain_certificates, now=None):
    if not re.fullmatch(r'[A-Z0-9]{10}', team_id):
        raise ValueError('A valid Apple Team ID is required')
    if profile.get('TeamIdentifier') != [team_id]:
        raise ValueError('The profile belongs to a different Apple team')
    identifier = profile.get('UUID', '')
    if not re.fullmatch(r'[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}', identifier):
        raise ValueError('Invalid provisioning profile UUID')
    if profile.get('Platform') != ['iOS'] or 'ProvisionedDevices' in profile or profile.get('ProvisionsAllDevices'):
        raise ValueError('Use an App Store iOS profile, not device or enterprise distribution')
    entitlements = profile.get('Entitlements', {})
    if entitlements.get('get-task-allow') is not False:
        raise ValueError('A debug-enabled profile cannot be distributed')
    if entitlements.get('com.apple.developer.team-identifier') != team_id:
        raise ValueError('Profile entitlement team does not match')
    app_id = entitlements.get('application-identifier', '')
    prefixes = profile.get('ApplicationIdentifierPrefix', [])
    if not isinstance(prefixes, list) or not any(
        isinstance(prefix, str) and re.fullmatch(r'[A-Z0-9]{10}', prefix)
        and app_id == prefix + '.' + BUNDLE_ID for prefix in prefixes
    ):
        raise ValueError('Use the exact registered LiveTalk bundle ID, not a wildcard')
    expiration = profile.get('ExpirationDate')
    if not isinstance(expiration, dt.datetime):
        raise ValueError('The profile has no expiration date')
    expiration = expiration.replace(tzinfo=dt.timezone.utc) if expiration.tzinfo is None else expiration
    now = now or dt.datetime.now(dt.timezone.utc)
    if expiration <= now:
        raise ValueError('The provisioning profile has expired')
    certificates = profile.get('DeveloperCertificates', [])
    if not isinstance(certificates, list) or not certificates or any(not isinstance(c, bytes) for c in certificates):
        raise ValueError('The profile has no valid distribution certificates')
    if not isinstance(keychain_certificates, list) or not keychain_certificates or any(
        not isinstance(c, bytes) or not c for c in keychain_certificates
    ):
        raise ValueError('Export the certificates from the temporary signing keychain')
    exact_certificates = set(certificates) & set(keychain_certificates)
    if not exact_certificates:
        raise ValueError('Profile certificate bytes do not match the imported keychain')
    # Apple tools identify a signing certificate by its SHA-1 fingerprint.
    # This is a keychain lookup identifier, not signature or certificate-trust
    # verification. Never use it to authenticate a profile or an app binary.
    # https://developer.apple.com/documentation/technotes/tn3161-inside-code-signing-certificates
    allowed = {hashlib.sha1(c, usedforsecurity=False).hexdigest().upper() for c in exact_certificates}
    # Reject a lookup identifier that names more than one distinct DER certificate.
    for fingerprint in allowed:
        candidates = {c for c in keychain_certificates
                      if hashlib.sha1(c, usedforsecurity=False).hexdigest().upper() == fingerprint}
        if len(candidates) != 1:
            raise ValueError('Ambiguous signing certificate lookup identifier')
    available = set(re.findall(r'\b[0-9A-Fa-f]{40}\b', identities))
    matching = sorted(allowed & {value.upper() for value in available})
    if len(matching) != 1:
        raise ValueError('Import exactly one usable signing identity matching the profile')
    if any(entitlements.get(key) for key in ['com.apple.developer.carplay-audio', 'com.apple.developer.carplay-communication']):
        raise ValueError('CarPlay distribution needs a separately reviewed signing configuration')
    return {'profile_uuid': identifier, 'identity_sha1': matching[0]}


def read_keychain_certificates(pem):
    blocks = re.findall(r'-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\s]+?)\s*-----END CERTIFICATE-----', pem)
    if not blocks:
        raise ValueError('No exported keychain certificates')
    return [base64.b64decode(''.join(block.split()), validate=True) for block in blocks]


def export_options(team_id, result):
    return {'method': 'app-store-connect', 'destination': 'export', 'signingStyle': 'manual',
            'teamID': team_id, 'signingCertificate': result['identity_sha1'],
            'provisioningProfiles': {BUNDLE_ID: result['profile_uuid']},
            'manageAppVersionAndBuildNumber': False, 'uploadSymbols': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('profile', type=Path)
    parser.add_argument('identities', type=Path)
    parser.add_argument('--keychain-certificates', type=Path, required=True)
    parser.add_argument('--team-id', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = validate_profile(plistlib.loads(args.profile.read_bytes()), args.team_id,
                              args.identities.read_text(encoding='utf-8'),
                              keychain_certificates=read_keychain_certificates(
                                  args.keychain_certificates.read_text(encoding='ascii')))
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output/'ExportOptions.plist').write_bytes(plistlib.dumps(export_options(args.team_id, result)))
    # Only non-secret identifiers are emitted; never the profile, owner name or certificate data.
    print(result['profile_uuid'])
    print(result['identity_sha1'])

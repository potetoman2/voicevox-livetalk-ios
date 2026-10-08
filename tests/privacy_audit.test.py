import importlib.util
import plistlib
import stat
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('privacy_audit', Path(__file__).parents[1] / 'scripts/audit_ipa_privacy.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
ROOT = 'Payload/LiveTalkMobile.app/'


class PrivacyAuditTests(unittest.TestCase):
    def entries(self):
        info = {'CFBundleIdentifier': 'jp.livetalk.mobile', 'CFBundleShortVersionString': '2.8',
                'CFBundleVersion': '28', **{key: False for key in audit.ACTIVATION_KEYS}}
        plain = {'NSPrivacyTracking': False, 'NSPrivacyCollectedDataTypes': [], 'NSPrivacyAccessedAPITypes': []}
        vendor = {'NSPrivacyCollectedDataTypes': [{'NSPrivacyCollectedDataType': 'NSPrivacyCollectedDataTypeDeviceID',
            'NSPrivacyCollectedDataTypeLinked': True, 'NSPrivacyCollectedDataTypeTracking': True,
            'NSPrivacyCollectedDataTypePurposes': ['NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising']}]}
        return [(ROOT + 'Info.plist', plistlib.dumps(info))] + [
            (ROOT + name, plistlib.dumps(vendor if 'GoogleMobileAds' in name else plain))
            for name in audit.REQUIRED_MANIFESTS] + [(ROOT + 'voice/NOTICE.txt', b'License notice')]

    def inspect(self, entries):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'test.ipa'
            with warnings.catch_warnings():
                warnings.simplefilter('ignore', UserWarning)
                with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
                    for name, data in entries:
                        # ZipInfo normalizes Windows separators on construction;
                        # preserve the deliberately malformed archive name for this test.
                        if isinstance(name, str) and '\\' in name:
                            entry = zipfile.ZipInfo('placeholder'); entry.filename = name
                            entry.orig_filename = name; name = entry
                        archive.writestr(name, data)
            return audit.audit_ipa(path)

    def test_vendor_tracking_survives_app_false_declaration(self):
        report = self.inspect(self.entries())
        self.assertTrue(report['tracking_declared_by_any_component'])
        self.assertTrue(report['review']['att_and_vendor_tracking_review_required'])
        self.assertFalse(report['review']['app_privacy_answers_finalized'])
        self.assertFalse(report['review']['real_device_traffic_verified'])
        self.assertFalse(report['manifests'][-1]['tracking_declared'])
        self.assertEqual(report['bundled_license_files'][0]['bytes'], 14)

    def test_missing_vendor_manifest_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Missing required manifest'):
            self.inspect([entry for entry in self.entries() if 'UserMessagingPlatform' not in entry[0]])

    def test_duplicate_paths_are_rejected(self):
        entries = self.entries()
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            self.inspect(entries + [entries[0]])

    def test_unsafe_paths_are_rejected_without_extraction(self):
        for path in ('../private.txt', '/private.txt', 'Payload/../private.txt', 'C:/private.txt', 'Payload\\private.txt'):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'Unsafe'):
                self.inspect(self.entries() + [(path, b'test')])

    def test_oversized_metadata_and_symlink_are_rejected(self):
        for entry in ('oversized', 'symlink'):
            entries = self.entries()
            if entry == 'oversized':
                entries[1] = (entries[1][0], b' ' * (audit.MAX_METADATA_BYTES + 1))
            else:
                target = zipfile.ZipInfo(entries[1][0]); target.create_system = 3
                target.external_attr = (stat.S_IFLNK | 0o777) << 16
                entries[1] = (target, b'../private.txt')
            with self.subTest(entry=entry), self.assertRaisesRegex(ValueError, 'Metadata'):
                self.inspect(entries)

    def test_invalid_boolean_does_not_become_false(self):
        for key in ('NSPrivacyTracking',):
            with self.assertRaisesRegex(ValueError, 'boolean'):
                audit.read_manifest(plistlib.dumps({key: 'false'}))
        for value in (0, 1, 'false'):
            entries = self.entries(); info = plistlib.loads(entries[0][1]); info['LTRevenueAdsEnabled'] = value
            entries[0] = (entries[0][0], plistlib.dumps(info))
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, 'boolean'):
                self.inspect(entries)

    def test_manifest_preserves_distinct_sources_for_same_type(self):
        entries = self.entries(); vendor = plistlib.loads(entries[2][1])
        app = {'NSPrivacyTracking': False, 'NSPrivacyCollectedDataTypes': [dict(vendor['NSPrivacyCollectedDataTypes'][0])]}
        app['NSPrivacyCollectedDataTypes'][0]['NSPrivacyCollectedDataTypeTracking'] = False
        entries[1] = (entries[1][0], plistlib.dumps(app))
        declarations = self.inspect(entries)['collected_data_inventory'][0]['declarations']
        self.assertEqual({row['tracking'] for row in declarations}, {True, False})

    def test_invalid_collection_shape_or_missing_reason_is_rejected(self):
        values = [{'NSPrivacyCollectedDataTypes': {}}, {'NSPrivacyCollectedDataTypes': ['invalid']},
                  {'NSPrivacyAccessedAPITypes': [{'NSPrivacyAccessedAPIType': 'Test', 'NSPrivacyAccessedAPITypeReasons': []}]}]
        for value in values:
            with self.subTest(value=value), self.assertRaises(ValueError):
                audit.read_manifest(plistlib.dumps(value))

    def test_wrong_or_multiple_apps_are_rejected(self):
        entries = self.entries(); info = plistlib.loads(entries[0][1]); info['CFBundleIdentifier'] = 'jp.other.app'
        with self.assertRaisesRegex(ValueError, 'LiveTalk'):
            self.inspect([(entries[0][0], plistlib.dumps(info))] + entries[1:])
        with self.assertRaisesRegex(ValueError, 'exactly one'):
            self.inspect(entries + [('Payload/Other.app/Info.plist', entries[0][1])])


if __name__ == '__main__':
    unittest.main()

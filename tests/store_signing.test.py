import datetime as dt
import hashlib
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location('store_signing', pathlib.Path(__file__).parents[1]/'scripts/store_signing.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class DistributionProfileTests(unittest.TestCase):
    def setUp(self):
        self.team = 'A1B2C3D4E5'
        self.cert = b'fixture-certificate-not-a-secret'
        self.sha = hashlib.sha1(self.cert).hexdigest().upper()
        self.now = dt.datetime(2026, 10, 7, tzinfo=dt.timezone.utc)
        self.profile = {'UUID': '12345678-1234-1234-1234-123456789abc',
                        'TeamIdentifier': [self.team], 'ApplicationIdentifierPrefix': [self.team],
                        'Platform': ['iOS'], 'ExpirationDate': self.now + dt.timedelta(days=30),
                        'DeveloperCertificates': [self.cert],
                        'Entitlements': {'get-task-allow': False,
                                         'com.apple.developer.team-identifier': self.team,
                                         'application-identifier': self.team+'.jp.livetalk.mobile'}}

    def validate(self):
        return signing.validate_profile(self.profile, self.team, self.sha, now=self.now)

    def test_exact_profile_and_private_identity_match(self):
        result = self.validate()
        options = signing.export_options(self.team, result)
        self.assertEqual(options['method'], 'app-store-connect')
        self.assertEqual(options['destination'], 'export')
        self.assertFalse(options['manageAppVersionAndBuildNumber'])
        self.assertEqual(options['provisioningProfiles'], {'jp.livetalk.mobile': self.profile['UUID']})

    def test_legacy_app_prefix_can_differ_from_current_team(self):
        self.profile['ApplicationIdentifierPrefix'] = ['Z9Y8X7W6V5']
        self.profile['Entitlements']['application-identifier'] = 'Z9Y8X7W6V5.jp.livetalk.mobile'
        self.validate()

    def test_other_team_rejected(self):
        self.profile['TeamIdentifier'] = ['Z9Y8X7W6V5']
        with self.assertRaises(ValueError): self.validate()

    def test_wildcard_and_other_bundle_rejected(self):
        for app_id in [self.team+'.*', self.team+'.jp.other.app']:
            self.profile['Entitlements']['application-identifier'] = app_id
            with self.assertRaises(ValueError): self.validate()

    def test_device_enterprise_and_debug_profiles_rejected(self):
        for key, value in [('ProvisionedDevices', []), ('ProvisionsAllDevices', True)]:
            self.profile[key] = value
            with self.assertRaises(ValueError): self.validate()
            del self.profile[key]
        self.profile['Entitlements']['get-task-allow'] = True
        with self.assertRaises(ValueError): self.validate()

    def test_expired_profile_rejected(self):
        self.profile['ExpirationDate'] = self.now.replace(tzinfo=None)
        with self.assertRaises(ValueError): self.validate()

    def test_missing_or_mismatched_identity_rejected(self):
        for identities in ['', '0'*40]:
            with self.assertRaises(ValueError):
                signing.validate_profile(self.profile, self.team, identities, now=self.now)

    def test_profile_filename_injection_rejected(self):
        self.profile['UUID'] = '../../other-profile'
        with self.assertRaises(ValueError): self.validate()

    def test_carplay_is_not_silently_added(self):
        self.profile['Entitlements']['com.apple.developer.carplay-communication'] = True
        with self.assertRaises(ValueError): self.validate()


if __name__ == '__main__': unittest.main()

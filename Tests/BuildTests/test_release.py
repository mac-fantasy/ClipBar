import base64
import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


configure = load_script("configure-bundle").configure
validate = load_script("validate-appcast").validate
PUBLIC_KEY = base64.b64encode(bytes(range(32))).decode()


class BundleConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.plist = Path(self.directory.name) / "Info.plist"
        self.plist.write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.0.0"}))

    def test_tag_version_and_repository_are_embedded(self):
        configure(self.plist, "2.10.3", "owner/ClipBar", PUBLIC_KEY)
        info = plistlib.loads(self.plist.read_bytes())
        self.assertEqual(info["CFBundleVersion"], "2.10.3")
        self.assertEqual(info["CFBundleShortVersionString"], "2.10.3")
        self.assertEqual(info["SUFeedURL"], "https://github.com/owner/ClipBar/releases/latest/download/appcast.xml")
        self.assertEqual(info["SUPublicEDKey"], PUBLIC_KEY)

    def test_invalid_versions_and_incomplete_update_configuration_fail(self):
        for version, repository, key in [
            ("v1.2.3", "owner/repo", PUBLIC_KEY),
            ("1.2.3-beta", "owner/repo", PUBLIC_KEY),
            ("01.2.3", "owner/repo", PUBLIC_KEY),
            ("1.2", "owner/repo", PUBLIC_KEY),
            ("1.2.3", "owner/repo", ""),
            ("1.2.3", "", PUBLIC_KEY),
            ("1.2.3", "owner/../repo", PUBLIC_KEY),
            ("1.2.3", "owner/repo", "invalid-key"),
        ]:
            with self.subTest(version=version, repository=repository, key=key):
                before = self.plist.read_bytes()
                with self.assertRaises(ValueError):
                    configure(self.plist, version, repository, key)
                self.assertEqual(self.plist.read_bytes(), before)

    def test_local_unconfigured_build_does_not_get_placeholder_update_source(self):
        configure(self.plist, None, "", "")
        self.assertNotIn("SUFeedURL", plistlib.loads(self.plist.read_bytes()))


class AppcastValidationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.archive = Path(self.directory.name) / "ClipBar-1.2.3-macOS-universal.zip"
        self.archive.write_bytes(b"archive")
        self.feed = Path(self.directory.name) / "appcast.xml"
        self.signature = base64.b64encode(bytes(64)).decode()
        self.xml = f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel><item><sparkle:version>1.2.3</sparkle:version>
            <enclosure url="https://github.com/owner/repo/releases/download/v1.2.3/{self.archive.name}"
              length="7" sparkle:edSignature="{self.signature}" />
          </item></channel></rss>'''

    def check(self, xml):
        self.feed.write_text(xml)
        return validate(self.feed, self.archive, "1.2.3", "owner/repo", "v1.2.3")

    def test_signed_feed_metadata_matches_archive(self):
        self.assertEqual(self.check(self.xml), self.signature)

    def test_unsigned_wrong_version_wrong_url_and_wrong_size_fail(self):
        for xml in [
            self.xml.replace(self.signature, ""),
            self.xml.replace(">1.2.3<", ">1.2.4<"),
            self.xml.replace("owner/repo/", "other/repo/"),
            self.xml.replace('length="7"', 'length="8"'),
        ]:
            with self.subTest(xml=xml), self.assertRaises(ValueError):
                self.check(xml)


if __name__ == "__main__":
    unittest.main()

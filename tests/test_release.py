import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'scripts'))
import release as r  # noqa: E402


class ReleaseHelpers(unittest.TestCase):
    def test_version_from_tag(self):
        self.assertEqual(r.version_from_tag('v1.1.0'), '1.1.0')

    def test_release_type(self):
        self.assertEqual(r.release_type('1.1.0'), 'release')
        self.assertEqual(r.release_type('1.2.0-beta.1'), 'beta')
        self.assertEqual(r.release_type('1.2.0-rc.1'), 'beta')
        self.assertEqual(r.release_type('1.2.0-alpha.2'), 'alpha')

    def test_interface_to_version(self):
        self.assertEqual(r.interface_to_version('16001'), '1.60.1')
        self.assertEqual(r.interface_to_version('11504'), '1.15.4')

    def test_toc_fields(self):
        toc = '## Interface: 16000, 16001\r\n## Title: X\r\n## Version: 1.2.3\r\n\r\nLogic.lua\r\n'
        self.assertEqual(r.toc_interfaces(toc), ['16000', '16001'])
        self.assertEqual(r.toc_field(toc, 'Version'), '1.2.3')
        self.assertEqual(r.toc_interfaces('## Title: X'), [])

    def test_changelog_section(self):
        log = '# Changelog\n\n## Unreleased\n\n## 1.1.0\n\n- New thing\n\n## 1.0.0\n\nFirst.\n'
        self.assertEqual(r.changelog_section(log, '1.1.0'), '- New thing')
        self.assertEqual(r.changelog_section(log, '1.0.0'), 'First.')
        self.assertIsNone(r.changelog_section(log, 'Unreleased'))
        self.assertIsNone(r.changelog_section(log, '9.9.9'))

    def test_toc_version_matches_changelog(self):
        version = r.toc_version()
        self.assertIsNotNone(r.changelog_section(r.read('CHANGELOG.md'), version),
                             'CHANGELOG.md needs a "## %s" section' % version)

    def test_forever_game_versions(self):
        types = [{'id': 1, 'name': 'WoW Retail'}, {'id': 9, 'name': 'WoW Forever', 'slug': 'wow-forever'}]
        self.assertEqual(r.find_forever_type(types)['id'], 9)
        versions = [{'id': 5, 'name': '1.60.1', 'gameVersionTypeID': 9},
                    {'id': 6, 'name': '1.60.1', 'gameVersionTypeID': 1},
                    {'id': 7, 'name': '1.60.0', 'gameVersionTypeID': 9}]
        ids, found, available = r.pick_game_versions(versions, 9, ['1.60.1'])
        self.assertEqual(ids, [5])
        self.assertEqual(found, ['1.60.1'])
        self.assertEqual(available, ['1.60.1', '1.60.0'])


if __name__ == '__main__':
    unittest.main()

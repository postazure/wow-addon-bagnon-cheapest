"""Release helpers for Bagnon Cheapest. Standard library only.

The version lives in the TOC's "## Version:" line. A release is an annotated
tag v<version> on main whose message is the release notes.

  python scripts/release.py check v1.1.0
      The tag is annotated with notes, and matches the TOC and CHANGELOG.md.
  python scripts/release.py notes --tag v1.1.0 --out release-notes.md
      Write the tag's message (the release notes) to a file.
  python scripts/release.py package
      Zip release/Bagnon_Cheapest-<version>.zip with one Bagnon_Cheapest/ folder.
  python scripts/release.py upload --zip <file> --notes <file> [--dry-run]
      Upload to CurseForge. Needs CURSEFORGE_TOKEN and CURSEFORGE_PROJECT_ID.
      Game versions come from the zip's TOC: interface 16001 -> Forever 1.60.1.
"""
import argparse
import io
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
import zipfile

ADDON = 'Bagnon_Cheapest'
TOC = os.path.join(ADDON, ADDON + '.toc')
API = 'https://wow.curseforge.com/api'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# Pure helpers (tested in tests/test_release.py)

def version_from_tag(tag):
    return tag[1:] if tag.startswith('v') else tag


def release_type(version):
    """1.2.0-alpha.1 is an alpha, -beta.1 or -rc.1 a beta, anything else a release."""
    if re.search(r'-alpha', version, re.I):
        return 'alpha'
    if re.search(r'-(beta|rc)', version, re.I):
        return 'beta'
    return 'release'


def toc_field(toc, name):
    for line in toc.splitlines():
        m = re.match(r'^##\s*' + name + r'\s*:(.*)$', line, re.I)
        if m:
            return m.group(1).strip()
    return None


def toc_interfaces(toc):
    value = toc_field(toc, 'Interface') or ''
    return [s.strip() for s in value.split(',') if s.strip().isdigit()]


def interface_to_version(iface):
    """16001 -> '1.60.1', 11504 -> '1.15.4'."""
    n = int(iface)
    return '%d.%d.%d' % (n // 10000, (n % 10000) // 100, n % 100)


def changelog_section(changelog, version):
    """Body of '## <version>' in CHANGELOG.md, or None if missing or empty."""
    lines = changelog.splitlines()
    try:
        start = [l.strip() for l in lines].index('## ' + version)
    except ValueError:
        return None
    body = []
    for line in lines[start + 1:]:
        if line.startswith('## '):
            break
        body.append(line)
    text = '\n'.join(body).strip()
    return text or None


def find_forever_type(types):
    for t in types:
        if re.search('forever', '%s %s' % (t.get('name') or '', t.get('slug') or ''), re.I):
            return t
    return None


def pick_game_versions(versions, type_id, wanted):
    of_type = [v for v in versions if v.get('gameVersionTypeID') == type_id]
    picked = [v for v in of_type if v.get('name') in wanted]
    return [v['id'] for v in picked], [v['name'] for v in picked], [v['name'] for v in of_type]


# Repo access

def read(path):
    with open(os.path.join(ROOT, path), encoding='utf-8-sig') as f:
        return f.read()


def toc_version():
    return toc_field(read(TOC), 'Version')


def git(*args):
    return subprocess.check_output(('git',) + args, cwd=ROOT, stderr=subprocess.DEVNULL).decode('utf-8')


def read_tag_notes(tag):
    """(annotated, notes). A signature block on a signed tag is dropped."""
    try:
        kind = git('cat-file', '-t', 'refs/tags/' + tag).strip()
    except subprocess.CalledProcessError:
        return False, ''
    if kind != 'tag':
        return False, ''
    contents = git('for-each-ref', 'refs/tags/' + tag, '--format=%(contents)')
    notes = re.split(r'^-----BEGIN (?:PGP|SSH) SIGNATURE-----$', contents, flags=re.M)[0].strip()
    return True, notes


def fail(message):
    print('::error::' + message)
    sys.exit(1)


# Commands

def cmd_check(args):
    tag = args.tag
    if not tag.startswith('v'):
        fail('Usage: release.py check v<version>')
    version = version_from_tag(tag)
    problems = []
    current = toc_version()
    if current != version:
        problems.append('%s says %s, but the tag is %s. Bump the TOC, commit, and tag that commit.' % (TOC, current, tag))
    if changelog_section(read('CHANGELOG.md'), version) is None:
        problems.append('CHANGELOG.md has no "## %s" section (or it is empty).' % version)
    annotated, notes = read_tag_notes(tag)
    if not annotated:
        problems.append('%s is not an annotated tag. Its message must be the release notes: tag with the release skill.' % tag)
    elif not notes:
        problems.append('%s has an empty message. Its message must be the release notes.' % tag)
    if problems:
        for p in problems:
            print('::error::' + p)
        sys.exit(1)
    print('%s is ready: annotated with notes, and the TOC and CHANGELOG.md match.' % tag)


def cmd_notes(args):
    annotated, notes = read_tag_notes(args.tag)
    if not annotated or not notes:
        fail('%s has no release notes. Tag with the release skill (an annotated tag whose message is the notes).' % args.tag)
    with open(args.out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(notes + '\n')
    print('Release notes for %s:\n\n%s' % (args.tag, notes))


def cmd_package(args):
    version = toc_version()
    if not version or '@' in version:
        fail('%s has no usable ## Version line.' % TOC)
    os.makedirs(os.path.join(ROOT, 'release'), exist_ok=True)
    out = os.path.join('release', '%s-%s.zip' % (ADDON, version))
    names = sorted(os.listdir(os.path.join(ROOT, ADDON)))
    with zipfile.ZipFile(os.path.join(ROOT, out), 'w', zipfile.ZIP_DEFLATED) as z:
        for name in names:
            z.write(os.path.join(ROOT, ADDON, name), '%s/%s' % (ADDON, name))
        z.write(os.path.join(ROOT, 'LICENSE'), '%s/LICENSE.txt' % ADDON)
    print('packaged ' + out)
    for name in names + ['LICENSE.txt']:
        print('  %s/%s' % (ADDON, name))


def api_json(path, token):
    req = urllib.request.Request(API + path, headers={'X-Api-Token': token})
    with urllib.request.urlopen(req) as res:
        return json.load(res)


def multipart(fields, file_field, file_name, file_bytes):
    boundary = uuid.uuid4().hex
    body = io.BytesIO()
    for name, value in fields.items():
        body.write(('--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n' % (boundary, name, value)).encode('utf-8'))
    body.write(('--%s\r\nContent-Disposition: form-data; name="%s"; filename="%s"\r\n'
                'Content-Type: application/zip\r\n\r\n' % (boundary, file_field, file_name)).encode('utf-8'))
    body.write(file_bytes)
    body.write(('\r\n--%s--\r\n' % boundary).encode('utf-8'))
    return body.getvalue(), 'multipart/form-data; boundary=' + boundary


def cmd_upload(args):
    with open(args.zip, 'rb') as f:
        data = f.read()
    try:
        toc = zipfile.ZipFile(io.BytesIO(data)).read('%s/%s.toc' % (ADDON, ADDON)).decode('utf-8-sig')
    except KeyError:
        fail('%s/%s.toc is not in the zip' % (ADDON, ADDON))
    version = toc_field(toc, 'Version')
    if not version:
        fail("The zip's TOC has no ## Version line")
    wanted = [interface_to_version(i) for i in toc_interfaces(toc)]
    if not wanted:
        fail("The zip's TOC has no ## Interface line")
    with open(args.notes, encoding='utf-8') as f:
        notes = f.read()

    metadata = {
        'changelog': notes,
        'changelogType': 'markdown',
        'displayName': 'Bagnon Cheapest %s' % version,
        'releaseType': release_type(version),
    }
    zip_name = os.path.basename(args.zip)

    if args.dry_run:
        print('Dry run. Would upload %s for game versions %s with:' % (zip_name, ', '.join(wanted)))
        print(json.dumps(dict(metadata, gameVersions='<ids for %s>' % ', '.join(wanted)), indent=2))
        return

    token = os.environ.get('CURSEFORGE_TOKEN')
    project = os.environ.get('CURSEFORGE_PROJECT_ID')
    if not token or not project:
        fail('Set CURSEFORGE_TOKEN and CURSEFORGE_PROJECT_ID.')

    forever = find_forever_type(api_json('/game/version-types', token))
    if not forever:
        fail('CurseForge has no Forever game version type')
    ids, found, available = pick_game_versions(api_json('/game/versions', token), forever['id'], wanted)
    missing = [w for w in wanted if w not in found]
    if missing:
        print('::warning::CurseForge has no Forever version %s yet; tagging %s.' % (', '.join(missing), ', '.join(found) or 'none'))
    if not ids:
        fail('None of %s are CurseForge Forever versions. Available: %s' % (', '.join(wanted), ', '.join(available)))

    body, content_type = multipart({'metadata': json.dumps(dict(metadata, gameVersions=ids))}, 'file', zip_name, data)
    req = urllib.request.Request('%s/projects/%s/upload-file' % (API, project), data=body, method='POST',
                                 headers={'X-Api-Token': token, 'Content-Type': content_type})
    try:
        with urllib.request.urlopen(req) as res:
            result = res.read().decode('utf-8')
    except urllib.error.HTTPError as e:
        fail('Upload failed: %s %s' % (e.code, e.read().decode('utf-8', 'replace')))
    print('Uploaded %s to CurseForge (%s, %s): %s' % (zip_name, metadata['releaseType'], ', '.join(found), result))


def main():
    parser = argparse.ArgumentParser(description='Bagnon Cheapest release helpers')
    sub = parser.add_subparsers(dest='command')
    sub.required = True

    p = sub.add_parser('check')
    p.add_argument('tag')
    p.set_defaults(fn=cmd_check)

    p = sub.add_parser('notes')
    p.add_argument('--tag', required=True)
    p.add_argument('--out', required=True)
    p.set_defaults(fn=cmd_notes)

    p = sub.add_parser('package')
    p.set_defaults(fn=cmd_package)

    p = sub.add_parser('upload')
    p.add_argument('--zip', required=True)
    p.add_argument('--notes', required=True)
    p.add_argument('--dry-run', action='store_true')
    p.set_defaults(fn=cmd_upload)

    args = parser.parse_args()
    args.fn(args)


if __name__ == '__main__':
    main()

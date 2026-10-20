#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

if [[ $# -gt 1 || ( $# -eq 1 && "${1:-}" != "--check" ) ]]; then
  print -u2 "Usage: ./scripts/publish.sh [--check]"
  exit 2
fi

repository="henrikhestnes/MacMural"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
tag="v$version"
notes="releases/$tag.md"
asset="$PWD/dist/MacMural.zip"

# These checks do not access GitHub, install anything, or launch the app.
python3 - "$version" "$notes" <<'PY'
from pathlib import Path
from zipfile import ZipFile
import hashlib
import plistlib
import re
import subprocess
import sys

version, notes = sys.argv[1:]
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('Expected a stable semantic version in Resources/Info.plist.')
email = subprocess.check_output(['git', 'config', 'user.email'], text=True).strip()
if email != 'henrik.hestnes@hotmail.com':
    raise SystemExit('Set this repository\'s user.email to henrik.hestnes@hotmail.com before publishing.')
if subprocess.check_output(['git', 'branch', '--show-current'], text=True).strip() != 'main':
    raise SystemExit('Publish from the main branch.')
allowed = {'Casks/macmural.rb', 'README.md', 'scripts/publish.sh', notes}
changed = set(subprocess.check_output(['git', 'diff', '--name-only', 'HEAD'], text=True).splitlines())
changed.update(subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard'], text=True).splitlines())
if changed - allowed:
    raise SystemExit('Commit or set aside unrelated changes first: ' + ', '.join(sorted(changed - allowed)))
cask = Path('Casks/macmural.rb').read_text()
assert re.search(r'^  version "' + re.escape(version) + r'"$', cask, re.M), 'Cask version does not match the app.'
asset = Path('dist/MacMural.zip')
checksum = hashlib.sha256(asset.read_bytes()).hexdigest()
assert f'  sha256 "{checksum}"' in cask, 'Cask checksum does not match the release ZIP. Update it first.'
assert checksum in Path(notes).read_text(), 'Release notes checksum does not match the ZIP.'
bundle = Path('dist/MacMural.app')
architectures = subprocess.check_output(['lipo', '-archs', str(bundle / 'Contents/MacOS/MacMural')], text=True).split()
assert {'arm64', 'x86_64'} <= set(architectures), 'The release must support Apple Silicon and Intel.'
with ZipFile(asset) as archive:
    assert archive.testzip() is None, 'Damaged ZIP.'
    info = plistlib.loads(archive.read('MacMural.app/Contents/Info.plist'))
    assert info['CFBundleShortVersionString'] == version, 'ZIP contains a different app version.'
    assert info['CFBundleIdentifier'] == 'io.macmural.app'
    for name in ['Contents/Info.plist', 'Contents/MacOS/MacMural', 'Contents/Resources/AppIcon.icns']:
        assert archive.read('MacMural.app/' + name) == (bundle / name).read_bytes(), 'ZIP differs from the local bundle: ' + name
print(f'Validated MacMural {version}, release notes, cask, ZIP, and commit email.')
PY
codesign --verify --deep --strict dist/MacMural.app
ruby -c Casks/macmural.rb

if [[ "${1:-}" == "--check" ]]; then
  print "Offline release checks passed. No GitHub changes made."
  exit 0
fi

# The user explicitly requested public GitHub hosting and this same-repo tap.
account=$(gh api user --jq .login)
if [[ "${account:l}" != "henrikhestnes" ]]; then
  print -u2 "Sign gh in as henrikhestnes before publishing."
  exit 1
fi
actual_repository=$(gh repo view "$repository" --json nameWithOwner --jq .nameWithOwner)
if [[ "${actual_repository:l}" != "${repository:l}" ]]; then
  print -u2 "Unexpected GitHub repository: $actual_repository"
  exit 1
fi
git fetch origin main --tags
git merge-base --is-ancestor origin/main HEAD
git add Casks/macmural.rb README.md scripts/publish.sh "$notes"
if ! git diff --cached --quiet; then
  git commit -m "Add Homebrew cask and release publishing for $tag"
fi
git push origin main
if git rev-parse --verify "$tag" >/dev/null 2>&1; then
  if [[ "$(git rev-parse "$tag^{commit}")" != "$(git rev-parse HEAD)" ]]; then
    print -u2 "$tag already refers to another commit. Use a new app version instead of moving a published tag."
    exit 1
  fi
else
  git tag -a "$tag" -m "MacMural $version"
fi
git push origin "refs/tags/$tag"

release_state=$(gh release list --repo "$repository" --limit 100 --json tagName,isDraft \
  --jq ".[] | select(.tagName == \"$tag\") | if .isDraft then \"draft\" else \"published\" end")
if [[ -z "$release_state" ]]; then
  gh release create "$tag" "$asset" --repo "$repository" --verify-tag \
    --draft --title "MacMural $version" --notes-file "$notes"
  release_state="draft"
elif [[ "$release_state" == "draft" ]]; then
  existing_asset=$(gh release view "$tag" --repo "$repository" --json assets \
    --jq '.assets[] | select(.name == "MacMural.zip") | .name')
  if [[ -z "$existing_asset" ]]; then
    gh release upload "$tag" "$asset" --repo "$repository"
  fi
fi

# Download and verify the uploaded bytes before making anything public.
verification_dir=$(mktemp -d "${TMPDIR:-/tmp}/macmural-release.XXXXXX")
gh release download "$tag" --repo "$repository" --pattern MacMural.zip --dir "$verification_dir"
cmp "$asset" "$verification_dir/MacMural.zip"

gh repo edit "$repository" --visibility public --accept-visibility-change-consequences
if [[ "$release_state" == "draft" ]]; then
  gh release edit "$tag" --repo "$repository" --draft=false --latest
fi

# Check the public download without authentication and without installing it.
curl --fail --silent --show-error --location --retry 4 --retry-delay 2 --retry-all-errors \
  "https://github.com/$repository/releases/download/$tag/MacMural.zip" \
  --output "$verification_dir/MacMural-public.zip"
cmp "$asset" "$verification_dir/MacMural-public.zip"
curl --fail --silent --show-error --location --retry 4 --retry-delay 2 --retry-all-errors \
  "https://raw.githubusercontent.com/$repository/main/Casks/macmural.rb" \
  --output "$verification_dir/macmural.rb"
cmp Casks/macmural.rb "$verification_dir/macmural.rb"
if [[ "$(gh repo view "$repository" --json isPrivate --jq .isPrivate)" != "false" ]]; then
  print -u2 "Repository is not public."
  exit 1
fi
print "Published: https://github.com/$repository/releases/tag/$tag"
print "Install with:"
print "  brew tap henrikhestnes/macmural https://github.com/$repository.git"
print "  brew install --cask henrikhestnes/macmural/macmural"

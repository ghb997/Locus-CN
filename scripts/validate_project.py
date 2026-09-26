"""Validate localization, bundle metadata and pinned native dependencies."""
import hashlib
import json
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
LITERAL = r'"(?:\\.|[^"\\])*"'

def strings(path):
    result = {}
    for match in re.finditer(f'({LITERAL})\\s*=\\s*({LITERAL});', path.read_text(encoding='utf-8')):
        key, value = (json.loads(item) for item in match.groups())
        assert key not in result, f'Duplicate localization: {key}'
        result[key] = value
    assert result, f'No strings found in {path}'
    return result

en = strings(ROOT / 'Locus/Resources/en.lproj/Localizable.strings')
zh = strings(ROOT / 'Locus/Resources/zh-Hans.lproj/Localizable.strings')
assert en.keys() == zh.keys(), 'English/Chinese resource keys differ'
formats = re.compile(r'%(?!%)(?:\d+\$)?[-+0 #]*\d*(?:\.\d+)?(?:ll|l|z)?[@diufgse]')
for key in en:
    assert formats.findall(en[key]) == formats.findall(zh[key]), f'Format mismatch: {key}'
for path in (ROOT / 'Locus').rglob('*.swift'):
    source = path.read_text(encoding='utf-8')
    for match in re.finditer(r'L10n\.(?:tr|format)\((' + LITERAL + ')', source):
        key = json.loads(match.group(1))
        assert key in zh, f'Missing translation in {path.name}: {key}'
    assert 'L10n.tr(L10n.' not in source, f'Double localization in {path}'
info = plistlib.loads((ROOT / 'Locus/Resources/Info.plist').read_bytes())
assert info['CFBundleDisplayName'] == 'Locus'
assert info['CFBundleDevelopmentRegion'] == 'zh-Hans'
assert info['CFBundleURLTypes'][0]['CFBundleURLSchemes'] == ['locus-cn']
assert '"17.0"' in (ROOT / 'project.yml').read_text()
lock = json.loads((ROOT / 'Vendor/idevice/source-lock.json').read_text())
assert lock['revision'] == 'd32c8189c51c2789496b0768039419c3705498c3'
assert lock['deploymentTarget'] == '17.0'
assert lock['rustToolchain'] == '1.98.1'
assert (ROOT / 'Vendor/idevice/LICENSE.txt').stat().st_size > 500
print(f'Validated {len(zh)} Chinese translations, bundle metadata and pinned native source settings.')

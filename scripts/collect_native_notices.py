"""Collect the notices shipped by the pinned Rust dependency graph."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
metadata = json.loads((root / 'build/native-metadata.json').read_text())
packages = {package['id']: package for package in metadata['packages']}
nodes = {node['id']: node for node in metadata['resolve']['nodes']}
start = next(key for key, value in packages.items() if value['name'] == 'idevice-ffi')
visited = set()
pending = [start]
while pending:
    key = pending.pop()
    if key in visited:
        continue
    visited.add(key)
    pending.extend(dep['pkg'] for dep in nodes[key]['deps'])

sections = ['Locus CN native dependencies — source versions and upstream license notices.\n']
for key in sorted(visited, key=lambda key: (packages[key]['name'], packages[key]['version'])):
    package = packages[key]
    directory = Path(package['manifest_path']).parent
    candidates = set(directory.glob('LICENSE*')) | set(directory.glob('COPYING*')) | set(directory.glob('LICENCE*'))
    if package.get('license_file'):
        candidates.add(directory / package['license_file'])
    sections.append('\n' + '=' * 72 + '\n' + package['name'] + ' ' + package['version'])
    sections.append('Declared license: ' + (package.get('license') or 'See license text'))
    sections.append('Source: ' + (package.get('repository') or package.get('source') or 'Pinned idevice workspace'))
    for candidate in sorted(candidates):
        if candidate.is_file():
            sections.append('\n' + candidate.name + '\n' + candidate.read_text(encoding='utf-8', errors='replace'))
    if package['name'] in ['idevice', 'idevice-ffi']:
        sections.append((root / 'Vendor/idevice/LICENSE.txt').read_text(encoding='utf-8'))
destination = root / 'build/THIRD-PARTY-LICENSES.txt'
destination.write_text('\n'.join(sections) + '\n', encoding='utf-8')
print(f'Collected notices for {len(visited)} native packages.')

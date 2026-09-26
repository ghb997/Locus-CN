"""Reject device archives built above the app's deployment target."""
from pathlib import Path
import collections
import hashlib
import json
import struct

root = Path(__file__).resolve().parents[1]
archive = root / 'Vendor/idevice/libidevice_ffi.a'
data = archive.read_bytes()
assert data[:8] == b'!<arch>\n', 'Expected a thin arm64 archive'
versions = collections.Counter()
offset = 8
objects = 0
while offset + 60 <= len(data):
    header = data[offset:offset + 60]
    size = int(header[48:58].strip())
    name = header[:16].decode('ascii').strip()
    start = offset + 60
    extra = int(name[3:]) if name.startswith('#1/') else 0
    member = data[start + extra:start + size]
    if member[:4] == b'\xcf\xfa\xed\xfe':
        objects += 1
        assert struct.unpack_from('<I', member, 4)[0] == 0x100000c, 'Non-arm64 object found'
        commands = struct.unpack_from('<I', member, 16)[0]
        cursor = 32
        for _ in range(commands):
            command, length = struct.unpack_from('<II', member, cursor)
            version = None
            if command == 0x32:
                platform, version = struct.unpack_from('<II', member, cursor + 8)
                assert platform == 2, f'Non-iOS platform: {platform}'
            elif command == 0x25:
                version = struct.unpack_from('<I', member, cursor + 8)[0]
            if version is not None:
                parts = (version >> 16, (version >> 8) & 255, version & 255)
                assert parts <= (17, 0, 0), f'Native object requires iOS {parts}; rebuild for iOS 17'
                versions['.'.join(map(str, parts))] += 1
            cursor += length
    offset = start + size + size % 2
assert objects > 0 and versions
report = {
    'source': json.loads((root / 'Vendor/idevice/source-lock.json').read_text()),
    'machOObjects': objects, 'minimumOSCounts': dict(versions),
    'sha256': hashlib.sha256(data).hexdigest(),
    'headerSHA256': hashlib.sha256((archive.parent / 'idevice.h').read_bytes()).hexdigest(),
}
destination = root / 'build/native-build.json'
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))

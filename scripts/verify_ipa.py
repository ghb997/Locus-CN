"""Inspect the actual packaged product; produces a reusable JSON/SHA-256 report."""
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import sys
import zipfile

ipa = Path(sys.argv[1]).resolve()
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None, 'ZIP CRC validation failed'
    prefix = 'Payload/Locus.app/'
    info = plistlib.loads(archive.read(prefix + 'Info.plist'))
    assert info['CFBundleIdentifier'] == 'com.chrismack.locus'
    assert info['CFBundleDisplayName'] == 'Locus'
    assert info['MinimumOSVersion'] == '17.0'
    assert info['CFBundleShortVersionString'] == '1.2.0'
    for name in ['en.lproj/Localizable.strings', 'zh-Hans.lproj/Localizable.strings',
                 'zh-Hans.lproj/InfoPlist.strings', 'LICENSE-Locus.txt', 'LICENSE-idevice.txt', 'THIRD-PARTY-LICENSES.txt']:
        assert prefix + name in archive.namelist(), f'Missing resource: {name}'
    executable = archive.read(prefix + info['CFBundleExecutable'])
    assert struct.unpack_from('<I', executable)[0] == 0xfeedfacf, 'Expected a 64-bit Mach-O device executable'
    assert struct.unpack_from('<I', executable, 4)[0] == 0x100000c, 'Expected arm64 architecture'
    cursor = 32
    binary_minimum = None
    for _ in range(struct.unpack_from('<I', executable, 16)[0]):
        command, size = struct.unpack_from('<II', executable, cursor)
        if command == 0x32:
            platform, minimum, sdk = struct.unpack_from('<III', executable, cursor + 8)
            assert platform == 2, 'Expected iOS device platform'
            assert minimum == (17 << 16), 'Binary deployment target differs from Info.plist'
            binary_minimum = '17.0'
        cursor += size
    assert binary_minimum, 'Missing binary platform version'
    assert prefix + 'embedded.mobileprovision' not in archive.namelist(), 'Unexpected provisioning profile'
    chinese = plistlib.loads(archive.read(prefix + 'zh-Hans.lproj/Localizable.strings'))
    assert chinese['Settings'] == '设置'
    assert chinese['Pause route'] == '暂停路线'
    assert chinese['Spoofing'] == '定位指令已发送'
    report = {
        'artifact': ipa.name, 'bundleIdentifier': info['CFBundleIdentifier'],
        'displayName': info['CFBundleDisplayName'], 'version': info['CFBundleShortVersionString'],
        'build': info['CFBundleVersion'], 'minimumOS': info['MinimumOSVersion'],
        'binaryMinimumOS': binary_minimum, 'sourceRevision': info.get('LocusSourceRevision', 'unknown'),
        'architecture': 'arm64', 'signing': 'Unsigned; sign before installation',
        'chineseResourceCount': len(chinese),
        'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
        'executableSHA256': hashlib.sha256(executable).hexdigest(),
        'deviceTesting': 'Not performed; see docs/COMPATIBILITY.md',
    }
ipa.with_suffix('.ipa.sha256').write_text(f"{report['sha256']}  {ipa.name}\n", encoding='utf-8')
(ipa.parent / 'ipa-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))

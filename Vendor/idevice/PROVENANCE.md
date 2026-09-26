# idevice binary provenance

The static archive, header and module map are preserved byte-for-byte from
ChrisMack32/Locus commit `83c8fb324983728e8f44759cfd834dc637ee38b5`.
The original archive was introduced by upstream commit
`c1cc43dcf33420f03ebb900ad748c1f82e97154b`.

| File | SHA-256 |
| --- | --- |
| libidevice_ffi.a | `05e6f58f082ee9f866a60763debe9b016e003005d424ac227b8d459686a2b575` |
| idevice.h | `23b7a97ed37ebd9bc53e7620b9da8a9d1b5961f05252201462b7c5bd39e0fcc0` |

Upstream did not embed an exact idevice source revision or reproducible build recipe
with this binary. These hashes pin the actual inputs; they are not a claim that
the archive was rebuilt from a verified idevice commit.

The MIT license is copied from jkcoxson/idevice's LICENSE.txt. The borrowed lifetime
of RemoteServer in `location_simulation_new` was checked against idevice source
revision `7da735f141634c626532413e6ad86bc1973854d4` as well as current source.
CI records native minimum deployment versions in `native-minimum-os.txt`.

Protocol compatibility with iOS 17–27 requires physical-device testing independently
of the app's iOS 17 deployment target. Native tunnel calls cannot be forcibly
cancelled by cancelling a Swift Task; Stop invalidates pending commands, waits for
an in-flight call on the serial queue, then clears location.

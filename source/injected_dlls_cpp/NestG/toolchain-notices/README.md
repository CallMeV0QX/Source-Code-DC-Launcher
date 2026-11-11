The 1.0.12 bootstrap proxies were built using LLVM MinGW 20261020 UCRT x86_64,
from the upstream author's immutable release asset:
https://github.com/mstorsjo/llvm-mingw/releases/tag/20261020

Archive: `llvm-mingw-20261020-ucrt-x86_64.zip`
SHA-256: `FD5462B7F5D93B2FF981FCD3F9C7E427E47F3203C64EA91C27BCC444EEBD74CD`
The download was checked against the release asset's SHA-256 digest.
Clang: 23.1.4, LLVM commit `7a941dfb2877a0b8cf30323fefa85ad019e0b0f5`.

The LLVM and MinGW runtime notices here are copied from that toolchain. The
libc++ notice is from `libcxx/LICENSE.TXT` at the same pinned LLVM commit.
These notices cover compiler runtime components statically linked into the
bootstrap proxies. Toolchains themselves and their executables are not shipped
inside the runtime bundle. Main runtime and CloudRedirect payloads retain their
predecessor build provenance and licenses.

#pragma once
// Upstream relies on transitive MSVC includes for the C conversion functions.
// Include their owning header when building the same source with LLVM libc++.
#include <cstdlib>

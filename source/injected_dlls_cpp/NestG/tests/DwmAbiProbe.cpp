#include <windows.h>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <intrin.h>

#include "AbiDeclarations.inc"
extern "C" { void* AbiTarget = nullptr; unsigned AbiIndex = ~0u; }
void* const thunks[] = {
#include "AbiAddresses.inc"
};
static int sentinel;
static bool aligned = true;

__declspec(noinline) uint64_t Integers(uint64_t a, uint64_t b, void* c, uint64_t d,
                                      uint64_t e, void* f, uint64_t g, double h) {
    aligned = (reinterpret_cast<uintptr_t>(_AddressOfReturnAddress()) & 15) == 8;
    if (a != 0x123456789abcdef0ULL || b != 7 || c != &sentinel || d != 13 ||
        e != 17 || f != &aligned || g != 23 || h != 2.5) return 0;
    return 0xfedcba9876543210ULL;
}
__declspec(noinline) double Floats(double a, double b, double c, double d, double e, double f) {
    return a + 2*b + 4*c + 8*d + 16*e + 32*f;
}
__declspec(noinline) double Mixed(double a, uint64_t b, double c, void* d, float e, uint64_t f) {
    return d == &sentinel && b == 7 && f == 19 ? a + c + e : -1;
}
__declspec(noinline) void ThrowFromTarget() { throw std::runtime_error("controlled unwind"); }

int main() {
    static_assert(sizeof(thunks) / sizeof(thunks[0]) == 103);
    for (unsigned i = 0; i < 103; ++i) {
        AbiTarget = reinterpret_cast<void*>(&Integers);
        auto integer = reinterpret_cast<decltype(&Integers)>(thunks[i]);
        if (integer(0x123456789abcdef0ULL, 7, &sentinel, 13, 17, &aligned, 23, 2.5) != 0xfedcba9876543210ULL || !aligned || AbiIndex != i) return 10;
        AbiTarget = reinterpret_cast<void*>(&Floats);
        if (reinterpret_cast<decltype(&Floats)>(thunks[i])(0.5, 1.25, 2.5, 4.25, 8.5, 16.25) != Floats(0.5, 1.25, 2.5, 4.25, 8.5, 16.25) || AbiIndex != i) return 11;
        AbiTarget = reinterpret_cast<void*>(&Mixed);
        if (reinterpret_cast<decltype(&Mixed)>(thunks[i])(0.5, 7, 2.25, &sentinel, 4.5f, 19) != 7.25 || AbiIndex != i) return 12;
        AbiTarget = reinterpret_cast<void*>(&ThrowFromTarget);
        bool caught = false;
        try { reinterpret_cast<void(*)()>(thunks[i])(); }
        catch (const std::runtime_error&) { caught = true; }
        if (!caught || AbiIndex != i) return 13;
    }
    printf("Passed 103 original thunks x 4 ABI cases (integer/pointer/stack, XMM0..3, mixed, unwind).\n");
    return 0;
}

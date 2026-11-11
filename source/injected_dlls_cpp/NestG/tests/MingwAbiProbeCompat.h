#pragma once
#include <intrin.h>
#if defined(__MINGW32__)
// Test host only: expose the saved return-address slot to the existing ABI
// alignment assertion. Requesting the frame address preserves the frame pointer.
#define _AddressOfReturnAddress() (static_cast<unsigned char*>(__builtin_frame_address(0)) + sizeof(void*))
#endif

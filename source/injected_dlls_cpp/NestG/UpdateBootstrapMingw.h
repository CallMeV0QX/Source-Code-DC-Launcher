#pragma once
#include <cstdio>
#include <cwchar>
// UCRT MinGW has the bounded C entry points; these array overloads preserve the
// existing MSVC source without editing historical startup or loader patches.
#if defined(__MINGW32__)
template<size_t N, typename... A> inline int sprintf_s(char (&target)[N], const char* format, A... args) { return ::snprintf(target, N, format, args...); }
template<size_t N, typename... A> inline int swprintf_s(wchar_t (&target)[N], const wchar_t* format, A... args) { return ::swprintf(target, N, format, args...); }
#endif

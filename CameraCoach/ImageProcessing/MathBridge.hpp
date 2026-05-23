// MathBridge.hpp
// Day 1 C++ test: the simplest possible C++ class.
//
// Why a .hpp extension?
//   .h  = traditionally C or Objective-C headers
//   .hpp = C++ headers
// The distinction is a convention, not enforced by the compiler,
// but it makes it immediately clear which language a header belongs to.
//
// #pragma once: a non-standard but universally supported preprocessor
// directive that prevents this header from being included more than
// once per translation unit. It's the modern alternative to:
//   #ifndef MATH_BRIDGE_HPP
//   #define MATH_BRIDGE_HPP
//   ...
//   #endif
//
// MathBridge::add() is a static method — it belongs to the class
// but doesn't need an instance. In C++ this is spelled `static`
// in the class definition (same keyword as C, different meaning
// from Swift's `static`).

#pragma once

class MathBridge {
public:
    // static: no instance needed — call as MathBridge::add(3, 4)
    // This is our Day 1 smoke test: call C++ from Obj-C++ from Swift.
    static int add(int a, int b);
};

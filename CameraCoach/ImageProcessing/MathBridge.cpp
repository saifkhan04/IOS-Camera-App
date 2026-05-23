// MathBridge.cpp
// C++ implementation of MathBridge.
//
// #include "MathBridge.hpp" — uses quotes (not angle brackets) because
// it's a project-local header, not a system header. The compiler looks
// in the project directory first, then the system include paths.
//
// The MathBridge:: prefix is how C++ ties an implementation back to
// its class declaration. Without it, `add` would be a free function
// with no connection to the class.
//
// This file is compiled as plain C++ (no Objective-C, no Swift).
// It can be unit tested entirely in C++ if we add a test target later.

#include "MathBridge.hpp"

int MathBridge::add(int a, int b) {
    return a + b;
}

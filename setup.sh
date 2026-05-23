#!/bin/bash
# setup.sh — Run this ONCE from your Mac terminal to:
#   1. Clear stale git lock files (left by the sandbox)
#   2. Commit all Day 1 source files
#   3. Push to GitHub
#   4. Install xcodegen and generate the Xcode project
#
# Usage:
#   cd ~/Documents/Claude/Projects/IOS\ Camera\ App
#   chmod +x setup.sh
#   ./setup.sh

set -e  # exit on any error

echo "📁 Working in: $(pwd)"

# ── Step 1: Clear stale lock files ───────────────────────────────────
echo ""
echo "🔓 Clearing git lock files..."
rm -f .git/index.lock .git/HEAD.lock
echo "   Done."

# ── Step 2: Stage all files ───────────────────────────────────────────
echo ""
echo "📦 Staging files..."
git add .
git status --short

# ── Step 3: Commit ────────────────────────────────────────────────────
echo ""
echo "💾 Committing..."
git commit -m "Day 1: Project scaffold, camera, motion, C++ bridge

- project.yml: xcodegen spec for CameraCoach iOS 18 target
- CameraCoachApp.swift: @main entry point
- ContentView.swift: live camera + orientation overlay + C++ bridge test
- CameraPreviewView.swift: UIViewRepresentable for AVCaptureVideoPreviewLayer
- CameraManager.swift: AVCaptureSession with video + LiDAR depth outputs
- MotionManager.swift: CoreMotion pitch/roll/yaw at 30Hz
- CameraCoach-Bridging-Header.h: Swift to Obj-C++ bridge entry point
- ImageProcessor.h/mm: Obj-C++ bridge class
- MathBridge.hpp/cpp: C++ smoke test (proves full Swift->ObjC++->C++ chain)
- Assets.xcassets: app icon stub + root catalog
- MVP_Plan.md: revised plan for iPhone 17 Pro with LiDAR"

# ── Step 4: Push ──────────────────────────────────────────────────────
echo ""
echo "🚀 Pushing to GitHub..."
git push origin main
echo "   Pushed."

# ── Step 5: Install xcodegen (if needed) ─────────────────────────────
echo ""
echo "🔧 Checking xcodegen..."
if ! command -v xcodegen &> /dev/null; then
    echo "   Installing xcodegen via Homebrew..."
    brew install xcodegen
else
    echo "   xcodegen already installed: $(xcodegen --version)"
fi

# ── Step 6: Generate .xcodeproj ──────────────────────────────────────
echo ""
echo "🏗️  Generating Xcode project..."
xcodegen generate
echo "   Generated: CameraCoach.xcodeproj"

# ── Step 7: Open in Xcode ─────────────────────────────────────────────
echo ""
echo "✅ Done! Opening Xcode..."
echo ""
echo "   NEXT STEP IN XCODE:"
echo "   1. Select the CameraCoach target in the project navigator"
echo "   2. Go to Signing & Capabilities"
echo "   3. Set your Team to your Apple Developer account"
echo "   4. Connect your iPhone 17 Pro and run"
echo "   5. You should see: camera feed + pitch/roll/yaw + 'C++ bridge: 3 + 4 = 7'"
echo ""
open CameraCoach.xcodeproj

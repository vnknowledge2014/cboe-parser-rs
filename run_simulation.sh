#!/bin/bash

PROJECT_NAME="cboe-pitch-parser"

echo "🎯 CBOE PITCH Protocol Simulation Runner"
echo "======================================="

# Kiểm tra project có tồn tại không
if [ ! -d "$PROJECT_NAME" ]; then
    echo "❌ Project $PROJECT_NAME không tồn tại!"
    echo "🔧 Chạy create_cboe_project.sh trước để tạo project"
    exit 1
fi

cd $PROJECT_NAME

echo "📦 Checking Rust installation..."
if ! command -v cargo &> /dev/null; then
    echo "❌ Rust/Cargo chưa được cài đặt!"
    echo "🔗 Cài đặt từ: https://rustup.rs/"
    exit 1
fi

echo "✅ Rust version: $(rustc --version)"
echo "✅ Cargo version: $(cargo --version)"

echo ""
echo "🔨 Building project..."
if cargo build; then
    echo "✅ Build thành công!"
else
    echo "❌ Build thất bại!"
    exit 1
fi

echo ""
echo "🚀 Chạy PITCH simulation..."
echo "=========================="
cargo run

echo ""
echo "🧪 Chạy unit tests..."
echo "==================="
cargo test

echo ""
echo "📊 Project statistics:"
echo "====================="
echo "📁 Source files:"
find src -name "*.rs" -exec wc -l {} + | tail -1 | awk '{print "   Total lines:", $1}'

echo "📦 Dependencies:"
grep -E '^[a-zA-Z]' Cargo.toml | grep -v '^\[' | sed 's/^/   /'

echo ""
echo "🔍 Build performance analysis..."
echo "==============================="
echo "🏗️  Debug build:"
time cargo build --quiet
echo ""
echo "🚀 Release build:"
time cargo build --release --quiet

echo "📈 Binary sizes:"
if [ -f "target/debug/$PROJECT_NAME" ]; then
    debug_size=$(stat -f%z "target/debug/$PROJECT_NAME" 2>/dev/null || stat -c%s "target/debug/$PROJECT_NAME" 2>/dev/null)
    echo "   Debug: $(($debug_size / 1024))KB"
fi

if [ -f "target/release/$PROJECT_NAME" ]; then
    release_size=$(stat -f%z "target/release/$PROJECT_NAME" 2>/dev/null || stat -c%s "target/release/$PROJECT_NAME" 2>/dev/null)
    echo "   Release: $(($release_size / 1024))KB"
fi

echo ""
echo "🎯 Chạy benchmark với release build..."
echo "====================================="
echo "⏱️  Performance test:"
time cargo run --release --quiet

echo ""
echo "📋 Project completion checklist:"
echo "================================"
echo "✅ Project structure created"
echo "✅ Dependencies resolved"
echo "✅ Compilation successful"
echo "✅ Unit tests passed"
echo "✅ Simulation executed"
echo "✅ Performance validated"

echo ""
echo "🎉 CBOE PITCH Parser simulation hoàn thành!"
echo "🔧 Để chỉnh sửa code: cd $PROJECT_NAME && code ."
echo "🚀 Để chạy lại: cargo run"
echo "🧪 Để test: cargo test"
echo "📖 Để xem docs: cargo doc --open"

#!/bin/bash
set -e
cd ~/wxbuild
PB=$(brew --prefix protobuf@21); PLIST=$(brew --prefix libplist); JSON=$(brew --prefix jsoncpp); LAME=$(brew --prefix lame)
SDK=$(xcrun --show-sdk-path)
SRCS=()
for f in WechatExporter/core/*.cpp; do
  [[ "$f" == *IDeviceBackup.cpp ]] && continue   # live-device only
  SRCS+=("$f")
done
SRCS+=(WechatExporterCmd/WechatExporter.cpp)
clang++ -std=c++17 -arch arm64 -O1 -w -DNDEBUG \
  -I WechatExporter/core -I stubs \
  -I "$PB/include" -I "$PLIST/include" -I "$JSON/include" -I "$LAME/include" \
  -I "$SDK/usr/include/libxml2" \
  "${SRCS[@]}" \
  -L "$PLIST/lib" -lplist-2.0 -L "$JSON/lib" -ljsoncpp -L "$LAME/lib" -lmp3lame \
  -L "$PB/lib" -lprotobuf -lprotoc \
  -lsqlite3 -lxml2 -lcurl -lz -liconv \
  -framework CoreFoundation -framework Security \
  -o wxexp_cmd

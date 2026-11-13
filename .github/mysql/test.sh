#!/bin/sh
set -eu
nim --version
mysql_config --version
mysql_config --cflags
mysql_config --libs
case "${BUILD_MODE:-debug}" in
  debug) flags="" ;;
  release) flags="-d:release" ;;
  asan) flags="--mm:orc -d:useMalloc --passC:-fsanitize=address --passC:-fno-omit-frame-pointer --passL:-fsanitize=address" ;;
  *) exit 1 ;;
esac
nim c -r $flags tests/all/tmysql_abi.nim
nim c -r $flags tests/all/tdb_mysql.nim
nim c -r $flags tests/all/tmysql_native.nim
nim cpp -r $flags tests/all/tmysql_abi.nim
nim cpp -r $flags tests/all/tmysql_native.nim

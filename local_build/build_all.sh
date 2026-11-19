#!/bin/bash
# 构建 gnss-sim 联合验证用引擎变体（见 README.md）。
# 用法:  ./build_all.sh          web 三变体（local / both_off / iflc）
#        ./build_all.sh trk      追加 pocket_trk_iflc 诊断变体
# 注意: 不链接 libsdr.a —— 引擎 .c 全集直接参与编译，补丁旁路文件得以覆盖同名符号。
set -e
MINGW_BIN="${MINGW_BIN:-/d/workbuddy/tools/mingw64/bin}"
export PATH="$MINGW_BIN:$PATH"
cd "$(dirname "$0")"

INC="-I../src -I../lib/RTKLIB/src -I../lib/cyusb -I../lib/pocketfft"
CFLAGS="-O3 -DWIN32 -Wall -Wno-unused-parameter -Wno-unused-variable -Wno-unused-function"
LIBS="../lib/win32/librtk.a ../lib/win32/libpocketfft.a ../lib/cyusb/CyAPI.a \
      -lsetupapi -lavrt -lwinmm -lws2_32 -lpthread -static"

COMMON="../src/sdr_array.c ../src/sdr_ch.c ../src/sdr_cmn.c ../src/sdr_code.c \
        ../src/sdr_code_gal.c ../src/sdr_conf.c ../src/sdr_dev.c ../src/sdr_fec.c \
        ../src/sdr_ldpc.c ../src/sdr_nav.c ../src/sdr_nb_ldpc.c ../src/sdr_rcv.c \
        ../src/sdr_sdev.c ../src/sdr_usb.c ../src/sdr_web.c"
WEB="../app/pocket_web/pocket_web.c"
TRK="../app/pocket_trk/pocket_trk.c"
IFLC="sdr_func_iflc.c sdr_pvt_iflc.c ephemeris_iflc.c pntpos_iflc.c"

build() {
    local name="$1"; shift
    g++ $CFLAGS $INC "$@" $LIBS -o "$name.exe"
    echo "BUILD OK: $name.exe"
}

# 1) 标准版：原版改正配置（BRDC 电离层 + SAAS 对流层）
build pocket_web_local  $COMMON ../src/sdr_func.c ../src/sdr_pvt.c $WEB
# 2) 匹配版：电离层+对流层改正关闭（配 gnss-sim 大气关闭场景）
build pocket_web_both_off $COMMON ../src/sdr_func.c sdr_pvt_both_off.c $WEB
# 3) IFLC 双频版：E1/E5a 消电离层组合（含 E5a 捕获/跟踪扩展）
build pocket_web_iflc   $COMMON $IFLC $WEB

if [ "${1:-}" = "trk" ]; then
    build pocket_trk_iflc $COMMON $IFLC $TRK
fi

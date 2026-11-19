# local_build — PocketSDR 本地扩展（gnss-sim 联合验证用）

本目录收纳本仓库相对上游 [tomojitakasu/PocketSDR](https://github.com/tomojitakasu/PocketSDR)（v0.22）
的全部本地改动。补丁一律采用**旁路源文件**方式：不改 `src/`、`lib/RTKLIB/src/` 原文件，
而是把修改版复制进本目录，与官方源码一起编译成不同用途的**引擎变体**。
这些变体由姊妹项目 [HomeInSnow/gnss-sim](https://github.com/HomeInSnow/gnss-sim) 的
PocketSDR Desktop 桌面壳驱动，用于回放 gnss-sim 生成的 GNSS 中频 IQ 场景。

## 引擎变体

| exe | 主文件 | 定位内核 | 用途 |
|---|---|---|---|
| `pocket_web_local.exe` | `../src/sdr_pvt.c`（原版） | BRDC 电离层 + SAAS 对流层固定改正 | **标准版**：验证信号含全要素大气注入的场景（与注入模型天然对齐） |
| `pocket_web_both_off.exe` | `sdr_pvt_both_off.c` | 电离层/对流层改正全关 | **匹配版**：验证 gnss-sim"大气关闭"场景（只改正被注入的，防止错扣） |
| `pocket_web_iflc.c 组` → `pocket_web_iflc.exe` | `sdr_pvt_iflc.c` + `sdr_func_iflc.c` + `ephemeris_iflc.c` + `pntpos_iflc.c` | IFLC 消电离层组合（含 E1/E5a 扩展） | Galileo 双频链路实验 |

诊断类（历史产物，可由配方重建）：`pvt_iono_off.exe`、`pvt_tropo_off.exe`、
`pvt_satclk_off.exe`（卫星钟差预扣减）、`pocket_trk_*`（跟踪调试系列）。

## 补丁清单

相对官方源码的实际改动（`diff local_build/<补丁> <官方>` 可复核）：

1. **`sdr_pvt_both_off.c`**（vs `src/sdr_pvt.c`，2 行）
   `IONOOPT_BRDC → IONOOPT_OFF`、`TROPOPT_SAAS → TROPOPT_OFF`。
   方法论：接收机"只改正信号里实际存在的东西"——仿真场景没注入大气时，标准版仍按惯例
   扣减会引入 10 m 级垂直偏置。

2. **`sdr_pvt_satclk_off.c`**（vs `src/sdr_pvt.c`，约 17 行）
   在 both_off 基础上追加卫星钟差预扣减：以与 pntpos 内部完全同参的 `satposs()` 重算
   `dts`，观测伪距预移 `-CLIGHT*dts`，精确抵消 `resP` 内部的 `+CLIGHT*dts` 补偿
   （用于钟差注入归因实验）。

3. **`pntpos_iflc.c`**（vs `lib/RTKLIB/src/pntpos.c`，约 15 行）
   - IFLC 双频门限接受 Galileo E5a：`SYS_GAL && code[2]==CODE_L5I && P[2]!=0`；
   - 新增 E1-E5a 组合分支：`gamma=(FREQ1/FREQ5)²`、`P5 -= gettgd(sat,nav,0)`（BGD_E5a/E1）。
     官方仅支持 E1-E5b。

4. **`ephemeris_iflc.c`**（vs `lib/RTKLIB/src/ephemeris.c`，约 6 行）
   移除广播星历 `AOD<=0`（toe 超前）过滤：仿真器按"距运行起点最近"选择 50-min toe 网格记录，
   所选 toe 可能合法地略超前于仿真时刻；Kepler/钟差求值对称，`|toe-time|<=tmax` 仍然生效。

5. **`sdr_func_iflc.c`**（vs `src/sdr_func.c`，约 1500 行新增）
   - 放开 `$EPH` 星历日志输出（被默认 log_mask 掩码吞掉）；
   - E1/E5a 双频捕获/跟踪扩展（IFLC 链路所需的相关器与组合观测量）。

6. **`sdr_pvt_iflc.c`**（vs `src/sdr_pvt.c`，IFLC 主配置）
   - `opt.ionoopt = IONOOPT_IFLC`；
   - Galileo 轨道源路由 I/NAV：`setseleph(SYS_GAL, 0)`（gnss-sim 仿真器播发 I/NAV）；
   - 少星段关闭 RAIM-FDE（`#if 0`，避免 9 星以下场景被完好性检测误杀）。

## 构建

前置：winlibs/MinGW `g++` 在 PATH（或改 `build_all.sh` 的 `MINGW_BIN`）；
仓库 `lib/win32/` 预编译库齐备（`librtk.a`、`libpocketfft.a`、`CyAPI.a`）。
**不链接 `libsdr.a`**——引擎全部 `.c` 直接参与编译，保证补丁文件覆盖同名符号。

```sh
cd local_build
./build_all.sh          # web 三变体（local / both_off / iflc）
./build_all.sh trk      # 追加 pocket_trk 诊断变体
```

## 与 gnss-sim Desktop 的对接

PocketSDR Desktop 源码态按以下顺序找引擎：`POCKETSDR_BUILD` 环境变量 →
仓库兄弟目录 `../PocketSDR/local_build/`；打包态随桌面版分发预编译产物。
回放参数经 WebSocket（`set_inp`/`set_sig`）下发，IQ 文件格式以 `<file>.bin.tag`
（NCH/F_S/F_LO/CS16/BITS）为准，桌面壳在开始回放时按界面参数自动校正重写 tag。

## 验证结论摘要

- 大气全注入场景 × 标准版（本目录 `pocket_web_local.exe`）：水平 RMS 0.31 m / 垂直 0.41 m；
- 大气关闭场景 × 匹配版（`pocket_web_both_off.exe`）：0.32 / 0.45 m，而标准版错扣大气
  垂直偏置 -11 m——注入清单与改正清单必须对齐；
- E1+E5a 无电离层场景：IFLC（3.60 m 单频匹配 < 6.19 IFLC < 10.93 原版）不占优，
  双频收益只在真电离层下兑现。

#!/usr/bin/env bash
# Project-relative AFileManager AROS build; run from any directory.
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="${AFILEMANAGER_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

source "$SCRIPT_DIR/../../../scripts/lib/arosa-build-env.sh"

arosa_require_fpc_aros
arosa_require_aros_toolchain

LIB="$AROS_LIB"
# Preview-stage embedded NanoSVG library.  Override NANOSVG_ROOT if needed.
NANOSVG_ROOT="${NANOSVG_ROOT:-$AROS_ROOT/dev/AROS/libraries/nanosvg}"
NANOSVG_LIB="$NANOSVG_ROOT/build"
# AROSA native FreeType2 specimen bridge (0.7.34).
FONT_BRIDGE_SRC="$AROSA_ROOT/source/platform/aros/fonts"
FONT_BRIDGE_OUT="$AROSA_BUILD/fontbridge"
FONT_BRIDGE_LIB="$FONT_BRIDGE_OUT/libarosa_freetype2_bridge.a"
OUT="$AROSA_BUILD/afilemanager"
# 0.8.23: ThorVG (SVG text, masks, clip paths, patterns, blur), C++
TVG_OUT="$AROSA_BUILD/tvg"
# 0.8.24: the outline font engine (FreeType, shaping) for Unicode text
WF_OUT="$AROSA_BUILD/wf"
# Shared AROSA static C++ ABI compatibility provider.  The current x86_64
# AROS GCC toolchain omits crtbegin.o, so collect-aros links consume this
# provider for ABI symbols normally supplied by GCC's executable CRT.
CXXABI_OUT="$AROSA_BUILD/cxxabi"
BINDINGS="$AROSA_BINDINGS"
# 0.8.29.2.2: the AROS i386 system is built binary compatible: its Exec
# struct Node is ln_Succ, ln_Pred, ln_Type, ln_Pri, ln_Name.  The FPC
# bindings follow that layout only with -dAROS_BINCOMPAT; without it they
# put ln_Name before ln_Type, so every port a program publishes carries a
# broken name (FindPort never finds it) and Node type/priority/name reads
# are wrong.  One bindings drawer is shared by all AROSA programs, so the
# layout it was compiled for is recorded and a mismatch rebuilds it.
AROS_BINCOMPAT_DEFINE="${AROS_BINCOMPAT_DEFINE:-AROS_BINCOMPAT}"
BINDINGS_LAYOUT="arch=$AROSA_ARCH smp=$AROS_SMP_DEFINE bincompat=$AROS_BINCOMPAT_DEFINE"
mkdir -p "$BINDINGS"
if [[ "$(cat "$BINDINGS/.layout" 2>/dev/null)" != "$BINDINGS_LAYOUT" ]]; then
  echo "=== Bindings layout changed ($BINDINGS_LAYOUT): rebuilding bindings ==="
  find "$BINDINGS" -maxdepth 1 -type f \( -name '*.ppu' -o -name '*.o' \) -delete
  printf '%s\n' "$BINDINGS_LAYOUT" > "$BINDINGS/.layout"
fi
LOG_DIR="$APP_ROOT/logs"
mkdir -p "$OUT" "$BINDINGS" "$LOG_DIR"
LOG="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"
# Keep stdout visible while saving the same messages in the project log.
exec > >(tee -a "$LOG") 2>&1
trap 'status=$?; printf "Build status: %s; log: %s\n" "$status" "$LOG"; exit "$status"' EXIT
for required in "$COMPILER" "$RTL/system.ppu" "$LIB/libautoinit.a" "$NANOSVG_LIB/libarosa_nanosvg.a" "$FONT_BRIDGE_SRC/arosa_freetype2_bridge.c"; do
  [[ -f "$required" ]] || { echo "Missing dependency: $required"; exit 1; }
done

# A public-preview build must not be linked against the temporary RTL that
# prints semaphore snapshots/ObtainSemaphore tracing to stdout. Those strings
# are emitted before AFileManager itself starts, so application logging cannot
# suppress them. Fail early instead of shipping another noisy binary.
if command -v strings >/dev/null 2>&1; then
  if find "$RTL" -maxdepth 1 -type f \( -name '*.o' -o -name '*.a' \) -print0 2>/dev/null |
     xargs -0 -r strings 2>/dev/null |
     grep -Eq 'semaphore initialized and snapshotted|before ObtainSemaphore|SysInitAmigaOS complete'; then
    echo 'ERROR: instrumented i386-AROS RTL detected.'
    echo 'Remove the temporary [RTL] semaphore/stdout diagnostics and rebuild the RTL before building the preview.'
    exit 1
  fi
fi

echo '=== Building AROSA FreeType2 bridge ==='
mkdir -p "$FONT_BRIDGE_OUT"
if [[ ! -f "$FONT_BRIDGE_LIB" || "$FONT_BRIDGE_SRC/arosa_freetype2_bridge.c" -nt "$FONT_BRIDGE_LIB" ]]; then
  "$AROS_CC" -O2 -fno-common -c     -I"$FONT_BRIDGE_SRC"     -o "$FONT_BRIDGE_OUT/arosa_freetype2_bridge.o"     "$FONT_BRIDGE_SRC/arosa_freetype2_bridge.c"
  "$AROS_AR" rcs "$FONT_BRIDGE_LIB" "$FONT_BRIDGE_OUT/arosa_freetype2_bridge.o"
fi
command -v "$AROS_COLLECT" >/dev/null || { echo 'Missing "$AROS_COLLECT"'; exit 1; }
echo '=== Building ThorVG (libarosa_tvg.a) ==='
bash "$AROSA_ROOT/source/platform/vectorgraphics/build-tvg.sh" aros "$TVG_OUT"
echo '=== Building the outline font engine (libarosa_wf.a) ==='
bash "$AROSA_ROOT/source/platform/webfont/build-wf.sh" aros "$WF_OUT"
MODE="${1:-build}"
case "$MODE" in
  clean) echo 'Removing application build products (not bindings or logs)'; find "$OUT" -maxdepth 1 -type f \( -name '*.ppu' -o -name '*.o' -o -name 'link*.res' -o -name 'afilemanager-final.res' -o -name AFileManager -o -name AFileManagerTransferWorker \) -delete; exit 0 ;;
  build|rebuild|bindings) ;;
  *) echo "Usage: $0 [build|rebuild|bindings|clean]"; exit 2 ;;
esac
if [[ "$MODE" == rebuild || "$MODE" == bindings ]]; then
  find "$BINDINGS" -maxdepth 1 -type f \( -name '*.ppu' -o -name '*.o' \) -delete
fi
if [[ ! -f "$BINDINGS/exec.ppu" || ! -f "$BINDINGS/amigados.ppu" || ! -f "$BINDINGS/cybergraphics.ppu" || ! -f "$BINDINGS/datatypes.ppu" || ! -f "$BINDINGS/workbench.ppu" || ! -f "$BINDINGS/icon.ppu" || ! -f "$BINDINGS/diskfont.ppu" || ! -f "$BINDINGS/cliputils.ppu" ]]; then
  echo '=== Building AROS binding units ==='
  for unit in exec amigados cybergraphics datatypes; do
    "$COMPILER" -n -TAROS "$FPC_CPU_SWITCH" -Cn "-d$AROS_SMP_DEFINE" "-d$AROS_BINCOMPAT_DEFINE" -Fu"$RTL" -Fu"$AROS_UNITS" -Fu"$BINDINGS" -FU"$BINDINGS" "$AROS_UNITS/$unit.pas"
  done
  WORKBENCH_UNIT="$AROS_UNITS/workbench.pas"
  [[ -f "$WORKBENCH_UNIT" ]] || WORKBENCH_UNIT="$AM_UNITS/workbench.pas"
  [[ -f "$WORKBENCH_UNIT" ]] || { echo "Missing Workbench Pascal binding (checked $AROS_UNITS and $AM_UNITS)"; exit 1; }
  "$COMPILER" -n -TAROS "$FPC_CPU_SWITCH" -Cn "-d$AROS_SMP_DEFINE" "-d$AROS_BINCOMPAT_DEFINE" -Fu"$RTL" -Fu"$AROS_UNITS" -Fu"$AM_UNITS" -Fu"$BINDINGS" -FU"$BINDINGS" "$WORKBENCH_UNIT"
  ICON_UNIT="$AROS_UNITS/icon.pas"
  [[ -f "$ICON_UNIT" ]] || ICON_UNIT="$AM_UNITS/icon.pas"
  [[ -f "$ICON_UNIT" ]] || { echo "Missing icon.library Pascal binding (checked $AROS_UNITS and $AM_UNITS)"; exit 1; }
  "$COMPILER" -n -TAROS "$FPC_CPU_SWITCH" -Cn "-d$AROS_SMP_DEFINE" "-d$AROS_BINCOMPAT_DEFINE" -Fu"$RTL" -Fu"$AROS_UNITS" -Fu"$AM_UNITS" -Fu"$BINDINGS" -FU"$BINDINGS" "$ICON_UNIT"

  DISKFONT_UNIT="$AROS_UNITS/diskfont.pas"
  [[ -f "$DISKFONT_UNIT" ]] || DISKFONT_UNIT="$AM_UNITS/diskfont.pas"
  [[ -f "$DISKFONT_UNIT" ]] || { echo "Missing diskfont.library Pascal binding (checked $AROS_UNITS and $AM_UNITS)"; exit 1; }
  "$COMPILER" -n -TAROS "$FPC_CPU_SWITCH" -Cn "-d$AROS_SMP_DEFINE" "-d$AROS_BINCOMPAT_DEFINE" -Fu"$RTL" -Fu"$AROS_UNITS" -Fu"$AM_UNITS" -Fu"$BINDINGS" -FU"$BINDINGS" "$DISKFONT_UNIT"

  "$COMPILER" -n -TAROS "$FPC_CPU_SWITCH" -Cn "-d$AROS_SMP_DEFINE" "-d$AROS_BINCOMPAT_DEFINE" -Fu"$RTL" -Fu"$AROS_UNITS" -Fu"$AMI_EXTRA" -Fu"$BINDINGS" -FU"$BINDINGS" "$AMI_EXTRA/cliputils.pas"
fi
if [[ "$MODE" == bindings ]]; then echo 'Bindings built'; exit 0; fi
[[ -f "$APP_ROOT/AFileManager.pas" ]] || { echo "Missing $APP_ROOT/AFileManager.pas"; exit 1; }
# AROSA 0.17.11 application placement bridge
APPPLACEMENT_OUT="$OUT/appplacement"
APPPLACEMENT_CPU_OBJ="$APPPLACEMENT_OUT/arosa_cpu_telemetry.o"
APPPLACEMENT_AFF_OBJ="$APPPLACEMENT_OUT/arosa_execution_placement.o"
AFM_ENUM_WORKER_OBJ="$APPPLACEMENT_OUT/arosa_afm_enumeration_worker.o"
mkdir -p "$APPPLACEMENT_OUT"
echo '=== Building application placement bridge ==='
"$AROS_CC" -O2 -fno-common -c -o "$APPPLACEMENT_CPU_OBJ" \
  "$AROSA_ROOT/source/platform/aros/arosa_cpu_telemetry.c"
"$AROS_CC" -O2 -fno-common -DAROSA_CPUMASK_API="${AROSA_CPUMASK_API:-2}" -c \
  -o "$APPPLACEMENT_AFF_OBJ" "$AROSA_ROOT/source/platform/aros/arosa_execution_placement.c"
echo '=== Building AFileManager off-CPU enumeration worker bridge ==='
"$AROS_CC" -O2 -fno-common -c -o "$AFM_ENUM_WORKER_OBJ" \
  "$AROSA_ROOT/source/platform/aros/arosa_afm_enumeration_worker.c"
echo '=== Compiling AFileManager ==='
find "$OUT" -maxdepth 1 -type f \( -name '*.ppu' -o -name '*.o' -o -name 'link*.res' -o -name 'afilemanager-final.res' \) -delete
unit_paths=()
for root in source/core source/platform source/graphics source/ui source/services applications/afilemanager; do
  [[ -d "$AROSA_ROOT/$root" ]] || { echo "Missing source directory: $AROSA_ROOT/$root"; exit 1; }
  while IFS= read -r -d '' dir; do unit_paths+=("-Fu$dir"); done < <(find "$AROSA_ROOT/$root" -type f -name '*.pas' -printf '%h\0' | sort -zu)
done
"$COMPILER" -n -TAROS "$FPC_CPU_SWITCH" -Cn "-d$AROS_SMP_DEFINE" "-d$AROS_BINCOMPAT_DEFINE" -Fu"$RTL" -Fu"$BINDINGS" "${unit_paths[@]}" -Fl"$NANOSVG_LIB" -Fl"$FONT_BRIDGE_OUT" -Fl"$TVG_OUT" -Fl"$WF_OUT" -FU"$OUT" -FE"$OUT" "$APP_ROOT/AFileManager.pas"
echo '=== Linking AFileManager ==='
mapfile -t resfiles < <(find "$OUT" -maxdepth 1 -name 'link*.res' -type f)
[[ "${#resfiles[@]}" == 1 ]] || { echo "Expected one link response file; found ${#resfiles[@]}"; exit 1; }
final="$OUT/afilemanager-final.res"
cp "${resfiles[0]}" "$final"
# AROS_COLLECT owns SDK autoinit linkage on both architectures.
# Manual libraries.o injection duplicates the collector's libautoinit.a member.
echo "=== Using $AROSA_ARCH SDK libautoinit.a via AROS_COLLECT (manual libraries.o injection disabled) ==="
# AFileManager links static C++ provider code through collect-aros.  The current
# x86_64 AROS GCC 6.5 cross toolchain does not ship crtbegin.o, so it cannot
# provide __dso_handle through the normal compiler-driver CRT path.  Use the
# shared AROSA AROS C++ ABI provider instead of defining application-local
# compatibility symbols.  Keep the proven i386 path unchanged.
cxxabi_link=()
if [[ "$AROSA_ARCH" == "x86_64" ]]; then
  bash "$AROSA_ROOT/source/platform/aros/cxx/build-cxx-abi.sh" "$CXXABI_OUT"
  cxxabi_link=(-L"$CXXABI_OUT" -larosa_cxxabi)
fi

"$AROS_COLLECT" -e __startup_entry \
  -L"$LIB" -L"$RTL" -L"$BINDINGS" -L"$NANOSVG_LIB" -L"$FONT_BRIDGE_OUT" -L"$TVG_OUT" -L"$WF_OUT" \
  -L"$(dirname "$("$AROS_CC" -print-libgcc-file-name)")" \
  -o "$OUT/AFileManager" "$final" "$APPPLACEMENT_CPU_OBJ" "$APPPLACEMENT_AFF_OBJ" "$AFM_ENUM_WORKER_OBJ" \
  -larosa_tvg -lstdc++ "${cxxabi_link[@]}" -larosa_wf -larosa_freetype2_bridge -lfreetype2 -lposixc -lstdcio -lstdc -lm -lgcc
ls -lh "$OUT/AFileManager"

echo 'Build complete'

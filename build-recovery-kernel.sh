#!/usr/bin/env bash
# Build in an isolated Linux environment. Never run on the speaker.
set -euo pipefail
recipe_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work_dir=${JARVIS_BUILD_WORKDIR:?Set an empty build workspace}
mkdir -p "$work_dir"
if [ -e "$work_dir/kernel" ]; then
    printf 'Refusing to reuse an existing kernel checkout.\n' >&2
    exit 1
fi
source_repo=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repository"])' "$recipe_dir/source-lock.json")
source_commit=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "$recipe_dir/source-lock.json")
test "$source_repo" = 'https://github.com/comp18man/vk-capsula-mini-a113x-linux.git'
test "$source_commit" = '8d850405b091aaf217f8bb1bbdf22852f5cdb61e'
git init "$work_dir/kernel"
git -C "$work_dir/kernel" remote add origin "$source_repo"
git -C "$work_dir/kernel" fetch --depth=1 origin "$source_commit"
git -C "$work_dir/kernel" checkout --detach FETCH_HEAD
test "$(git -C "$work_dir/kernel" rev-parse HEAD)" = "$source_commit"
cd "$work_dir/kernel"
board_dts=arch/arm64/boot/dts/amlogic/meson-axg-s420-marusia-mini.dts
cat "$recipe_dir/recovery-disable.dtsi" >> "$board_dts"

make ARCH=arm64 LLVM=1 LLVM_IAS=1 tinyconfig
scripts/config --enable ARCH_MESON --enable SMP --set-val NR_CPUS 4 \
    --enable ARM_PSCI_FW --enable ARM_GIC --enable ARM_GIC_V3 \
    --enable OF --enable PRINTK --enable TTY --enable SERIAL_MESON \
    --enable SERIAL_MESON_CONSOLE --enable SERIAL_EARLYCON \
    --enable BINFMT_ELF --enable BINFMT_SCRIPT --enable BLK_DEV_INITRD --enable RD_GZIP \
    --enable PROC_FS --enable SYSFS --enable TMPFS --enable POSIX_TIMERS \
    --enable FUTEX --enable EPOLL --enable CONFIGFS_FS \
    --enable USB_SUPPORT --enable USB --enable USB_GADGET \
    --enable USB_DWC2 --enable USB_DWC2_DUAL_ROLE --enable USB_DWC3 \
    --enable USB_DWC3_DUAL_ROLE --enable USB_DWC3_MESON_G12A \
    --enable USB_G_SERIAL --enable U_SERIAL_CONSOLE \
    --enable PINCTRL --enable PINCTRL_MESON --enable PINCTRL_MESON_AXG \
    --enable PINCTRL_MESON_AXG_AO --enable COMMON_CLK --enable RESET_CONTROLLER \
    --enable PM --enable PM_GENERIC_DOMAINS --enable MESON_EE_PM_DOMAINS \
    --enable REGULATOR --enable REGULATOR_FIXED_VOLTAGE --enable PHY_MESON_GXL_USB2 \
    --enable PHY_MESON_GXL_USB3 --enable CC_OPTIMIZE_FOR_SIZE \
    --disable MODULES --disable MTD --disable BLOCK --disable MMC --disable NET \
    --disable SOUND --disable I2C --disable SPI --disable CPU_FREQ --disable CPU_IDLE \
    --disable DRM --disable FB --disable VT --disable NVMEM_MESON_EFUSE \
    --disable DEVTMPFS --disable DEVTMPFS_MOUNT --disable KALLSYMS \
    --enable CMDLINE_FORCE --set-str INITRAMFS_SOURCE '' \
    --set-str CMDLINE 'rdinit=/init init=/init root=/dev/ram0 ro console=ttyAML0,115200n8 console=ttyGS0,115200n8 panic=0 maxcpus=1 cpufreq.off=1 clk_ignore_unused pd_ignore_unused regulator_ignore_unused' \
    --set-str LOCALVERSION '-jarvis-ram-diagnostic'
make ARCH=arm64 LLVM=1 LLVM_IAS=1 olddefconfig
python3 - <<'PY'
from pathlib import Path
text = Path('.config').read_text()
values = dict(line.split('=', 1) for line in text.splitlines() if line.startswith('CONFIG_') and '=' in line)
for key in ['MTD','BLOCK','MMC','MODULES','NET','SOUND','I2C','SPI','CPU_FREQ','DEVTMPFS','NVMEM_MESON_EFUSE']:
    if values.get('CONFIG_' + key) in ('y', 'm'):
        raise SystemExit('Unsafe diagnostic configuration: '+key)
for key in ['BLK_DEV_INITRD','RD_GZIP','BINFMT_ELF','BINFMT_SCRIPT','PROC_FS','SYSFS','TMPFS','USB_G_SERIAL','U_SERIAL_CONSOLE','USB_DWC2','ARCH_MESON','CMDLINE_FORCE']:
    if values.get('CONFIG_' + key) != 'y':
        raise SystemExit('Missing diagnostic requirement: '+key)
if values.get('CONFIG_INITRAMFS_SOURCE') != '""':
    raise SystemExit('Unexpected built-in initramfs or fallback root configuration')
args = values.get('CONFIG_CMDLINE', '').strip('"').split()
for key, expected in [('root', '/dev/ram0'), ('rdinit', '/init'), ('init', '/init')]:
    if [arg for arg in args if arg.startswith(key + '=')] != [key + '=' + expected]:
        raise SystemExit('Unsafe forced command line: ' + key)
PY
make -j"${JARVIS_BUILD_JOBS:-2}" ARCH=arm64 LLVM=1 LLVM_IAS=1 Image amlogic/meson-axg-s420-marusia-mini.dtb
mkdir -p "$work_dir/output"
cp arch/arm64/boot/Image "$work_dir/output/Image.unpatched"
cp arch/arm64/boot/dts/amlogic/meson-axg-s420-marusia-mini.dtb "$work_dir/output/board.dtb"
cp .config "$work_dir/output/kernel.config"
cp "$recipe_dir/source-lock.json" "$work_dir/output/source-lock.json"
cp "$recipe_dir/recovery-disable.dtsi" "$work_dir/output/recovery-disable.dtsi"
git diff --binary > "$work_dir/output/board-change.patch"
# Complete corresponding source accompanies any binary download, including the patch.
git archive HEAD | gzip -1 > "$work_dir/output/kernel-source.tar.gz"
python3 - "$work_dir/output" <<'PY'
import hashlib,json,struct,sys
from pathlib import Path
p=Path(sys.argv[1]); image=(p/'Image.unpatched').read_bytes()
if len(image)<64 or image[56:60]!=b'ARM\x64':
    raise SystemExit('Not a raw ARM64 Image')
if len(image)>32*1024*1024:
    raise SystemExit('Kernel exceeds diagnostic memory budget')
text_offset,image_size,flags=struct.unpack_from('<QQQ',image,8)
r={'artifact':'RAM_KERNEL_CANDIDATE_NOT_BOOT_VERIFIED','launch_allowed':False,
   'boot_command':None,'flash_command':None,'header_text_offset':text_offset,
   'header_image_size':image_size,'header_flags':flags,'old_loader_header_patch_applied':False,
   'files':{f.name:{'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()}
            for f in p.iterdir() if f.is_file()}}
(p/'build-manifest.json').write_text(json.dumps(r,indent=2))
PY

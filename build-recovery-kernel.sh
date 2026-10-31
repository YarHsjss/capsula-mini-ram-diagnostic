#!/usr/bin/env bash
# Build in an isolated Linux environment. Never run on the speaker.
set -euo pipefail
recipe_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
profile=${JARVIS_DIAGNOSTIC_PROFILE:-core}
case "$profile" in core|peripherals) ;; *) printf 'Unknown diagnostic profile\n' >&2; exit 1 ;; esac
export JARVIS_DIAGNOSTIC_PROFILE="$profile"
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
if [ "$profile" = peripherals ]; then
cat >> "$board_dts" <<'DTS_PERIPHERALS'

// Discovery only: SDIO identity and microphone ALSA enumeration, no RF driver,
// no PCM capture/playback device nodes or userspace commands, no I2C driver.
&sd_emmc_b {
    status = "okay";
    max-frequency = <25000000>;
    /delete-property/ sd-uhs-sdr104;
    /delete-property/ cap-sd-highspeed;
};
&uart_A { status = "disabled"; };
&ntp8910a { status = "disabled"; };
&gpio {
    amp-enable-hog {
        /delete-property/ output-high;
        output-low;
    };
    amp-reset-discovery-hog {
        gpio-hog;
        gpios = <GPIOA_17 GPIO_ACTIVE_LOW>;
        output-high;
        line-name = "amp-reset-discovery";
    };
};
&frddr_a { status = "disabled"; };
&tdmin_c { status = "disabled"; };
&tdmin_lb { status = "disabled"; };
&tdmout_c { status = "disabled"; };
&tdmif_c { status = "disabled"; };
&toddr_b { status = "disabled"; };
/ {
    /delete-node/ sound;
    sound {
        compatible = "amlogic,axg-sound-card";
        model = "JARVIS-MIC-DISCOVERY";
        audio-routing = "TODDR_A IN 4", "PDM Capture";
        dai-link-0 { sound-dai = <&toddr_a>; };
        dai-link-1 {
            sound-dai = <&pdm>;
            codec { sound-dai = <&dmics>; };
        };
    };
};
DTS_PERIPHERALS
fi
# The inspected legacy loader ignores placement flag bit 3 and always computes
# bd.bi_dram[0].start + low32(text_offset). Keep the header layout and entry code,
# but emit an explicit 32 MiB load offset from source, above reserved low RAM.
python3 - <<'PY_HEADER'
from pathlib import Path
path = Path('arch/arm64/kernel/head.S')
source = path.read_text()
old = '\t.quad\t0\t\t\t\t// Image load offset from start of RAM, little-endian'
if source.count(old) != 1:
    raise SystemExit('Pinned ARM64 Image load-offset field changed')
path.write_text(source.replace(old, old.replace('.quad\t0\t', '.quad\t0x02000000\t'), 1))
PY_HEADER

# Windows' built-in usbser.inf matches class 02/subclass 02. The upstream
# legacy gadget otherwise advertises device subclass 00, requiring a custom
# INF on some hosts. Set only the default ACM branch to its correct subclass.
python3 - <<'PY_CDC'
from pathlib import Path
path = Path('drivers/usb/gadget/legacy/serial.c')
source = path.read_text()
old = '\t\tserial_config_driver.bConfigurationValue = 2;\n\t\tdevice_desc.bDeviceClass = USB_CLASS_COMM;'
if source.count(old) != 1:
    raise SystemExit('Pinned USB ACM device descriptor branch changed')
path.write_text(source.replace(old, old + '\n\t\tdevice_desc.bDeviceSubClass = USB_CDC_SUBCLASS_ACM;', 1))
PY_CDC

make ARCH=arm64 LLVM=1 LLVM_IAS=1 tinyconfig
scripts/config --enable ARCH_MESON --enable SMP --set-val NR_CPUS 4 \
    --enable ARM_PSCI_FW --enable ARM_GIC --enable ARM_GIC_V3 \
    --enable OF --enable PRINTK --enable TTY --enable SERIAL_MESON \
    --enable SERIAL_MESON_CONSOLE --enable SERIAL_EARLYCON \
    --enable BINFMT_ELF --enable BINFMT_SCRIPT --enable BLK_DEV_INITRD --enable RD_GZIP \
    --enable PROC_FS --enable SYSFS --enable SHMEM --enable TMPFS --enable POSIX_TIMERS \
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
if [ "$profile" = peripherals ]; then
scripts/config --enable MMC --enable MMC_MESON_GX --enable PWRSEQ_SIMPLE \
    --enable PWM --enable PWM_MESON --enable COMMON_CLK_PWM \
    --enable SOUND --enable SND --enable SND_PCM --enable SND_SOC \
    --enable SND_MESON_AXG_SOUND_CARD --enable SND_MESON_AXG_PDM \
    --enable SND_MESON_AXG_TODDR --enable SND_SOC_DMIC \
    --enable COMMON_CLK_AXG_AUDIO --enable RESET_MESON_AUDIO_ARB \
    --disable SND_MESON_AXG_FRDDR --disable SND_MESON_AXG_TDMIN \
    --disable SND_MESON_AXG_TDMOUT --disable SND_MESON_AXG_SPDIFOUT \
    --disable SND_MESON_AXG_SPDIFIN --disable SND_MESON_G12A_TOACODEC \
    --disable SND_MESON_G12A_TOHDMITX --disable SND_SOC_NTP8918 \
    --disable SND_SOC_ALL_CODECS --disable SND_DRIVERS --disable SND_USB \
    --disable SND_HDA --disable SND_PCI --disable SND_SEQUENCER \
    --disable MMC_BLOCK --disable NET --disable I2C --disable SPI
fi
make ARCH=arm64 LLVM=1 LLVM_IAS=1 olddefconfig
python3 - <<'PY'
import os
from pathlib import Path
text = Path('.config').read_text()
values = dict(line.split('=', 1) for line in text.splitlines() if line.startswith('CONFIG_') and '=' in line)
profile = os.environ.get('JARVIS_DIAGNOSTIC_PROFILE', 'core')
if profile not in ('core', 'peripherals'):
    raise SystemExit('Unknown diagnostic profile')
for key in ['MTD','BLOCK','MMC_BLOCK','MODULES','NET','I2C','SPI','CPU_FREQ','DEVTMPFS','NVMEM_MESON_EFUSE','SND_SOC_NTP8918','SND_MESON_AXG_FRDDR','SND_MESON_AXG_TDMOUT','BT','W1_AML','RTW88'] + (['MMC','SOUND'] if profile == 'core' else []):
    if values.get('CONFIG_' + key) in ('y', 'm'):
        raise SystemExit('Unsafe diagnostic configuration: '+key)
required = ['BLK_DEV_INITRD','RD_GZIP','BINFMT_ELF','BINFMT_SCRIPT','PROC_FS','SYSFS','SHMEM','TMPFS','USB_G_SERIAL','U_SERIAL_CONSOLE','USB_DWC2','ARCH_MESON','CMDLINE_FORCE']
if profile == 'peripherals':
    required += ['MMC','MMC_MESON_GX','PWRSEQ_SIMPLE','PWM_MESON','COMMON_CLK_PWM',
                 'SOUND','SND_SOC','SND_MESON_AXG_SOUND_CARD','SND_MESON_AXG_PDM',
                 'SND_MESON_AXG_TODDR','SND_SOC_DMIC','COMMON_CLK_AXG_AUDIO']
missing = [key for key in required if values.get('CONFIG_' + key) != 'y']
if missing:
    raise SystemExit('Missing diagnostic requirements: '+', '.join(missing))
if values.get('CONFIG_INITRAMFS_SOURCE') != '""':
    raise SystemExit('Unexpected built-in initramfs or fallback root configuration')
args = values.get('CONFIG_CMDLINE', '').strip('"').split()
for key, expected in [('root', '/dev/ram0'), ('rdinit', '/init'), ('init', '/init')]:
    if [arg for arg in args if arg.startswith(key + '=')] != [key + '=' + expected]:
        raise SystemExit('Unsafe forced command line: ' + key)
PY
make -j"${JARVIS_BUILD_JOBS:-2}" ARCH=arm64 LLVM=1 LLVM_IAS=1 Image amlogic/meson-axg-s420-marusia-mini.dtb
mkdir -p "$work_dir/output"
cp arch/arm64/boot/Image "$work_dir/output/Image.axg-legacy"
cp arch/arm64/boot/dts/amlogic/meson-axg-s420-marusia-mini.dtb "$work_dir/output/board.dtb"
cp .config "$work_dir/output/kernel.config"
cp "$recipe_dir/source-lock.json" "$work_dir/output/source-lock.json"
cp "$recipe_dir/recovery-disable.dtsi" "$work_dir/output/recovery-disable.dtsi"
git diff --binary > "$work_dir/output/source-change.patch"
# Complete corresponding source accompanies any binary download, including the patch.
git archive HEAD | gzip -1 > "$work_dir/output/kernel-source.tar.gz"
python3 - "$work_dir/output" <<'PY'
import hashlib,json,os,struct,sys
from pathlib import Path
p=Path(sys.argv[1]); image=(p/'Image.axg-legacy').read_bytes()
if len(image)<64 or image[56:60]!=b'ARM\x64':
    raise SystemExit('Not a raw ARM64 Image')
if len(image)>32*1024*1024:
    raise SystemExit('Kernel exceeds diagnostic memory budget')
text_offset,image_size,flags=struct.unpack_from('<QQQ',image,8)
if text_offset != 0x02000000 or not flags & 8 or image_size > 16*1024*1024:
    raise SystemExit('Unexpected legacy-loader placement or oversized runtime image')
r={'artifact':'RAM_KERNEL_CANDIDATE_NOT_BOOT_VERIFIED','launch_allowed':False,
   'boot_command':None,'flash_command':None,'header_text_offset':text_offset,
   'header_image_size':image_size,'header_flags':flags,'old_loader_header_patch_applied':True,
   'header_change_method':'source-only ARM64 load-offset field; no post-build binary patch',
   'usb_cdc_device_class':2,'usb_cdc_device_subclass':2,
   'diagnostic_profile':os.environ['JARVIS_DIAGNOSTIC_PROFILE'],
   'files':{f.name:{'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()}
            for f in p.iterdir() if f.is_file()}}
(p/'build-manifest.json').write_text(json.dumps(r,indent=2))
PY

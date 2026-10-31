# JARVIS Mini RAM diagnostic kernel recipe

Two manual profiles are supported. `core` is the original diagnostic.
`peripherals` enumerates the SDIO module at 25 MHz and a microphone-only ALSA
card. It does not load a Wi-Fi/radio driver, join networks, record audio, or play
sound. NAND and block I/O remain disabled. The amplifier is held disabled and
in reset, its I2C bus/codec and all playback links remain disabled. Firmware,
RF calibration and audio calibration from a real device must never be published.

Prepared recipe, not a tested boot image or flasher. Publishing and running this
recipe require the owner's approval. Only public source, configuration and build
code belong here. Never upload a speaker backup, original firmware, initramfs
extracted from it, serial number, Wi-Fi configuration or API credentials.

The public kernel source is pinned in `source-lock.json`. This first diagnostic
configuration excludes MTD, block devices, MMC, module loading, networking and
sound. CPU frequency scaling is disabled. The board source additionally disables
storage and audio buses; USB serial is the intended future log transport.

The default ACM gadget additionally advertises USB device class 02/subclass 02
so Windows can match its built-in usbser.inf without a vendor installer. Only
the ACM branch in drivers/usb/gadget/legacy/serial.c is changed; the exact patch
and descriptor values are included in the artifact. This is preparation for a
USB logging test, not proof of enumeration on the target.

The inspected legacy U-Boot computes the destination as DRAM start plus the
32-bit Image text_offset, ignoring the modern arbitrary-placement flag. A zero
offset collides with the board's reserved first 16 MiB. The recipe changes only
the load-offset field in arch/arm64/kernel/head.S to 0x02000000 before compiling;
entry instructions and the header layout are preserved. The exact source patch
is included as source-change.patch and the output is named Image.axg-legacy.
No post-build binary patch or boot command is applied. USB return/logging,
loader DTB fixups and the absence of any fallback factory init must be reviewed
before execution. A static memory map is not proof that the image boots.
No software from this recipe runs on the speaker or the Windows computer.

To build in an approved Linux build environment with LLVM, Make, Python, Bison,
Flex, bc, libelf and OpenSSL development headers:

```
JARVIS_BUILD_WORKDIR=/path/to/new/workspace JARVIS_BUILD_JOBS=2 bash build-recovery-kernel.sh
```

Outputs include the pinned complete kernel source archive, the board patch and
the exact configuration alongside the binary. See the kernel's COPYING and
LICENSES directory for its license; the board DTS retains its upstream SPDX
license. This recipe is for a personal diagnostic environment, without any
guarantee of compatibility or restoration.

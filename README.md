# JARVIS Mini RAM diagnostic kernel recipe

Prepared recipe, not a tested boot image or flasher. Publishing and running this
recipe require the owner's approval. Only public source, configuration and build
code belong here. Never upload a speaker backup, original firmware, initramfs
extracted from it, serial number, Wi-Fi configuration or API credentials.

The public kernel source is pinned in `source-lock.json`. This first diagnostic
configuration excludes MTD, block devices, MMC, module loading, networking and
sound. CPU frequency scaling is disabled. The board source additionally disables
storage and audio buses; USB serial is the intended future log transport.

The output retains the original kernel header. No loader-specific address patch
or boot command is guessed. Compatibility, reserved RAM, USB return/logging and
the absence of any fallback factory init must be reviewed before execution.
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

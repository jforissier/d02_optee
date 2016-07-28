# OP-TEE on the Hisilicon D02 board

## Introduction

The purpose of this repository is to build OP-TEE and associated software for
the Hisilicon D02 board.

## What's in here

Here you will find:

- Git submodules to various software: ARM Trusted Firmware, UEFI, Linux,
Grub, OP-TEE OS and client library and tests
- A Makefile to generate everything

Not everything is built from sources for various reasons. The following is a
list of all the files needed to boot Linux with OP-TEE, and produced by the
`make` command:

  1. `PV660D02.fd` is the BIOS binary. It contains UEFI, ARM Trusted Firmware
and OP-TEE. UEFI is built from `./uefi`, which is a mix of source code and
pre-compiled binaries (some libraries are closed source). ARM Trusted Firmware
is build from source (`./arm-trusted-firmware`) as well as OP-TEE
(`./optee_os`).
  2. `hip05-d02.dtb` is the Device Tree Blob, used by the kernel to detect the
hardware plaftorm. It is built from the kernel sources in `./linux`.
  3. `Image_arm64` is the linux kernel, built from sources in `./linux`.
  4. `grubaa64.efi` is the EFI application for the GRUB OS loader. It is built
from sources (./grub).
  5. `grub.cfg` is the GRUB configuration file, you can define boot entries
there or change the kernel command line parameters. It is a source file.
  6. `Debian_ARM64.tar.gz` is a complete Debian 8 root filesystem. It can be
downloaded pre-built from http://open-estuary.org/. 
  7. The OP-TEE client library (`libteec.so.1.0`) is built from sources
(`./optee_client`).
  8. The OP-TEE test application (`xtest`) and the Trusted Applications
(`*.ta`) are built from sources (`./optee_test`).

OP-TEE specific parts are in ARM Trusted Firmware (EL3 Secure Payload
Dispatcher), the kernel (OP-TEE driver) and the DT (reserved memory for OP-TEE
core and applications an secure/non-secure shared memory). And of course, the
TEE client library and test applications.
GRUB is also modified to work with PyPXE -- this is not related to OP-TEE.

## Prerequisites

TODO: list cross-compiler & tools.

```
git submodule init
git submodule update --recursive
```

## How to build

```
make
```

## How to run

Install into the folder where you have extracted the Debian distribution.
You can download `Debian_ARM64.tar.gz` from the Open Estuary site.

```
make install DESTDIR=/path/to/Debian_ARM64
```

TODO.
- Use PyPXE to set up a PXE environment.

- Configure NFS to export the root FS, such as Debian (Debian_ARM64 folder)
so that the kernel can mount root over NFS.

- Start FTPd to get and flash new BIOS (PV660D02.fd) and DTB (hip05-d02.dtb)
from the EBL menu.
You may create a user account called "d02" with password "d02" for instance.
Create links:
~d02/PV660D02.fd -> <path>/d02_optee/uefi/Build/Pv660D02/DEBUG_GCC49/FV/PV660D02.fd
~d02/hip05-d02.dtb -> <path>/d02_optee/linux/arch/arm64/boot/dts/hisilicon/hip05-d02.dtb
Start the FTP daemon:
```
  sudo ftpd -D
```

- Flash the binaries
Reboot the D02 board. If needed: Ctrl+T Ctrl+L to change EOL (e.g., if the
return key does not work).
Enter EBL, type:
```
  provision 192.168.1.10 -u d02 -p d02 -f PV660D02.fd -a 100000
  spiwfmem 100000 0000000 300000
```
To update the DTB:
```
  provision 192.168.1.10 -u d02 -p d02 -f hip05-d02.dtb -a 0x100000
  spiwfmem 0x100000 0x300000 0x100000
```

Then reboot by pressing the reset button or typing:
```
  reset
```

## Links

- PyPXE: https://github.com/psychomario/pypxe
- Open Estuary: http://open-estuary.org/


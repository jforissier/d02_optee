# Makefile for OP-TEE for Hisilicon D02
#
# 'make help' for details

SHELL = /bin/bash

ifeq ($(V),1)
  Q :=
  ECHO := @:
  _ECHO := :
else
  Q := @
  ECHO := @echo
  _ECHO := echo
endif

CROSS_COMPILE32 ?= ccache arm-linux-gnueabihf-
CROSS_COMPILE64 ?= ccache aarch64-linux-gnu-

# Secure Kernel: 32 or 64-bits
SK ?= 64
# Secure User mode (TAs): 32 or 64-bits
SU ?= 64

ifeq ($(SK),32)
ifeq ($(SU),64)
$(error Must set SU=32 when SK=32)
endif
endif

# Note: to build OP-TEE with pager:
# make SK=32 SU=32 CFG_WITH_PAGER=y #CFG_TEE_CORE_LOG_LEVEL=3 CFG_TEE_CORE_DEBUG=1

ifeq ($(SU),32)
CROSS_COMPILE_TA=$(CROSS_COMPILE32)
else
CROSS_COMPILE_TA=$(CROSS_COMPILE64)
endif

# Where the various Linux files get installed by "make install" (kernel
# modules, TEE client library, test applications...).
# This has to be merged with the root FS of the linux distribution you will
# be using, for instance using the overlay FS and exporting via NFS
# (see README.md)
# !!! Overly FS does not work. I tried creating it with:
# sudo mount -t overlay overlay -olowerdir=./Debian_ARM64_lower \
#            -oupperdir=./Debian_ARM64_upper -oworkdir=./Debian_ARM64_work \
#             ./Debian_ARM64
# ...and exporting via NFS. Kernel hangs when trying to mount root FS.
# If I unmount the Overlay FS, and "ln -s Debian_ARM64_lower Debian_ARM64"
# then "sudo service nfs-kernel-server restart", it works.
#
# Example:
#   make install DESTDIR=/home/jerome/work/d02/netboot/Debian_ARM64

DESTDIR = $(CURDIR)/install

.PHONY: all
all: arm-trusted-firmware grub linux optee-client optee-os uefi optee-test \
     aes-perf sha-perf tee-stats

.PHONY: install

help:
	@echo TODO

#
# GRUB
#

GRUB = grubaa64.efi grub.cfg

grub: grubaa64.efi

grubaa64.efi: grub/grub-mkimage
	$(ECHO) '  GEN    $@'
	$(Q)cd grub ; \
		./grub-mkimage -o ../grubaa64.efi \
			--format=arm64-efi \
			--prefix=/ \
			--directory=grub-core \
			boot chain configfile efinet ext2 fat gettext help \
			hfsplus loadenv lsefi normal normal ntfs ntfscomp \
			part_gpt part_msdos read search search_fs_file \
			search_fs_uuid search_label terminal terminfo tftp \
			linux

grub/grub-mkimage: grub/Makefile
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C grub

grub/Makefile: grub/configure
	$(ECHO) '  GEN     $@'
	$(Q)cd grub ; ./configure --target=aarch64-linux-gnu --with-platform=efi 

grub/configure: grub/configure.ac
	$(ECHO) '  GEN     $@'
	$(Q)cd grub ; ./autogen.sh

clean-grub:
	$(ECHO) '  CLEAN   $@'
	$(Q)if [ -e grub/Makefile ] ; then $(MAKE) -C grub clean ; fi
	$(Q)rm -f grubaa64.efi

clean: clean-grub

distclean-grub:
	$(ECHO) '  DISTCLEAN   $@'
	$(Q)if [ -e grub/Makefile ] ; then $(MAKE) -C grub distclean ; fi
	$(Q)rm -f grub/configure

distclean: distclean-grub

#
# ARM Trusted Firmware
#

ARMTF_DEBUG = 0

ARMTF_FLAGS := PLAT=d02

ifeq ($(ARMTF_DEBUG),1)
BL1 = arm-trusted-firmware/build/d02/debug/bl1.bin
FIP = arm-trusted-firmware/build/d02/debug/fip.bin
ARMTF_FLAGS += DEBUG=1 LOG_LEVEL=50 # 10=error 20=notice 30=warning 40=info 50=verbose
else
BL1 = arm-trusted-firmware/build/d02/release/bl1.bin
FIP = arm-trusted-firmware/build/d02/release/fip.bin
endif

BL32 = optee_os/out/arm-plat-d02/core/tee.bin

ARMTF_EXPORTS += CROSS_COMPILE='$(CROSS_COMPILE64)'

ifneq (,$(BL32))
ARMTF_FLAGS += SPD=opteed
ARMTF_EXPORTS += BL32=$(CURDIR)/$(BL32)
endif

define arm-tf-make
	+$(Q)export $(ARMTF_EXPORTS) ; \
		$(MAKE) -C arm-trusted-firmware $(ARMTF_FLAGS) $(1) $(2)
endef

.PHONY: arm-trusted-firmware
arm-trusted-firmware: optee-os
	$(ECHO) '  BUILD   $@'
	$(call arm-tf-make, bl1 fip)

clean-arm-trusted-firmware:
	$(ECHO) '  CLEAN   $@'
	$(call arm-tf-make, clean)

clean: clean-arm-trusted-firmware

#
# OP-TEE OS
#

CFG_TEE_CORE_LOG_LEVEL ?= 2

optee-os-flags := PLATFORM=d02
optee-os-flags += DEBUG=0
optee-os-flags += CFG_TEE_CORE_LOG_LEVEL=$(CFG_TEE_CORE_LOG_LEVEL) # 0=none 1=err 2=info 3=debug 4=flow
optee-os-flags += CFG_TEE_TA_LOG_LEVEL=3
optee-os-flags += CFG_RPMB_FS=y
optee-os-flags += CFG_SQL_FS=y
optee-os-flags += CFG_WITH_STATS=y # Needed for tee-stats
ifeq ($(SK),64)
optee-os-flags += CFG_ARM64_core=y
endif
optee-os-flags += CROSS_COMPILE32="$(CROSS_COMPILE32)" CROSS_COMPILE64="$(CROSS_COMPILE64)"

.PHONY: optee-os
optee-os:
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C optee_os $(optee-os-flags) all mem_usage

.PHONY: clean-optee-os
clean-optee-os:
	$(ECHO) '  CLEAN   $@'
	$(Q)$(MAKE) -C optee_os $(optee-os-flags) clean

clean: clean-optee-os

#
# OP-TEE client (libteec)
#

optee-client-flags := CROSS_COMPILE="$(CROSS_COMPILE64)"
#optee-client-flags += CFG_TEE_SUPP_LOG_LEVEL=4 CFG_TEE_CLIENT_LOG_LEVEL=4
optee-client-flags += CFG_SQL_FS=y

.PHONY: optee-client
optee-client:
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C optee_client $(optee-client-flags)

.PHONY: install-optee-client
install-optee-client: optee-client
	$(ECHO) '  INSTALL $@'
	$(Q)mkdir -p $(DESTDIR)
	$(Q)$(MAKE) -C optee_client $(optee-client-flags) install EXPORT_DIR=$(DESTDIR)
	$(ECHO) '  INSTALL $(DESTDIR)/etc/init.d/optee'
	$(Q)mkdir -p $(DESTDIR)/etc/init.d
	$(Q)cp init.d.optee $(DESTDIR)/etc/init.d/optee
	$(Q)chmod a+x $(DESTDIR)/etc/init.d/optee
	$(ECHO) '  LN      $(DESTDIR)/etc/rc5.d/S99optee'
	$(Q)mkdir -p $(DESTDIR)/etc/rc5.d
	$(Q)ln -sf /etc/init.d/optee $(DESTDIR)/etc/rc5.d/S99optee

install: install-optee-client

.PHONY: clean-optee-client
clean-optee-client:
	$(ECHO) '  CLEAN   $@'
	$(Q)$(MAKE) -C optee_client $(optee-client-flags) clean

clean: clean-optee-client

#
# OP-TEE tests (xtest)
#

optee-test-deps := optee-os

optee-test-flags := CROSS_COMPILE_HOST="$(CROSS_COMPILE64)" \
		    CROSS_COMPILE_TA="$(CROSS_COMPILE_TA)" \
		    TA_DEV_KIT_DIR=$(CURDIR)/optee_os/out/arm-plat-d02/export-ta_arm$(SU) \
		    O=$(CURDIR)/optee_test/out
#optee-test-flags += CFG_TEE_TA_LOG_LEVEL=3

ifneq (,$(wildcard optee_test/TEE_Initial_Configuration-Test_Suite_v1_1_0_4-2014_11_07))
GP_TESTS=1
endif

ifeq ($(GP_TESTS),1)
optee-test-flags += CFG_GP_PACKAGE_PATH=$(CURDIR)/optee_test/TEE_Initial_Configuration-Test_Suite_v1_1_0_4-2014_11_07
optee-test-flags += COMPILE_NS_USER=64
optee-test-deps += optee-test-do-patch
endif


.PHONY: optee-test
optee-test: $(optee-test-deps)
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C optee_test $(optee-test-flags)

.PHONY: optee-test-do-patch
optee-test-do-patch:
	$(Q)$(MAKE) -C optee_test $(optee-test-flags) patch


.PHONY: install-optee-test
install-optee-test: optee-test
	$(Q)$(MAKE) -C optee_test $(optee-test-flags) install DESTDIR=$(DESTDIR)

install: install-optee-test

.PHONY: clean-optee-test
clean-optee-test:
	$(ECHO) '  CLEAN   $@'
	$(Q)$(MAKE) -C optee_test $(optee-test-flags) clean

clean: clean-optee-test

#
# Linux kernel
#

LINUX = linux/arch/arm64/boot/Image
DTB = linux/arch/arm64/boot/dts/hisilicon/hip05-d02.dtb

linux-flags := CROSS_COMPILE="$(CROSS_COMPILE64)" ARCH=arm64

# Install modules and firmware files
.PHONY: install-linux
install-linux: linux
	$(ECHO) '  INSTALL $@'
	$(Q)mkdir -p $(DESTDIR)
	$(Q)$(MAKE) -C linux $(linux-flags) modules_install INSTALL_MOD_PATH=$(DESTDIR)
	$(Q)$(MAKE) -C linux $(linux-flags) firmware_install INSTALL_FW_PATH=$(DESTDIR)/lib/firmware

install: install-linux

.PHONY: linux
linux: linux/.config
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C linux $(linux-flags) Image modules dtbs

# FIXME: *lots* of modules are built uselessly
linux/.config:
	$(ECHO) '  GEN     $@'
	$(Q)$(MAKE) -C linux $(linux-flags) defconfig
	$(Q)cd linux ; ./scripts/config --enable TEE --enable OPTEE --enable DRM

clean-linux:
	$(ECHO) '  CLEAN   $@'
	$(Q)$(MAKE) -C linux $(linux-flags) clean
	$(ECHO) '  RM      linux/.config'
	$(Q)rm -f linux/.config

clean: clean-linux

#
# UEFI
#

UEFI_DEBUG = 0

ifeq ($(UEFI_DEBUG),1)
UEFI_DEB_OR_REL = DEBUG
else
UEFI_DEB_OR_REL = RELEASE
endif

UEFI_BIN = uefi/OpenPlatformPkg/Platforms/Hisilicon/Binary/D02
UEFI_BL1 = $(UEFI_BIN)/bl1.bin
UEFI_FIP = $(UEFI_BIN)/fip.bin

.PHONY: uefi-check-arm-tf-links
uefi-check-arm-tf-links:
	$(ECHO) '  CHECK    $(UEFI_BL1)'
	$(Q)if [ ! -L $(UEFI_BL1) ] ; then \
	        $(_ECHO) '  RM  $(UEFI_BL1)' ; \
	        rm -f $(UEFI_BL1) ; \
	        $(_ECHO) '  LN      $(UEFI_BL1)' ; \
	        ln -s $(CURDIR)/$(BL1) $(UEFI_BL1) ; \
	    fi
	$(ECHO) '  CHECK    $(UEFI_FIP)'
	$(Q)if [ ! -L $(UEFI_FIP) ] ; then \
	        $(_ECHO) '  RM       $(UEFI_FIP)' ; \
	        rm -f $(UEFI_FIP) ; \
	        $(_ECHO) '  LN      $(UEFI_FIP)' ; \
	        ln -s $(CURDIR)/$(FIP) $(UEFI_FIP) ; \
	    fi

# ARM Trusted Firmware is a prerequisite, because the final BIOS binary
# is UEFI (PV660D02.fd) and this file contains the ARM TF output (bl1.bin,
# fip.bin).
.PHONY: uefi
uefi: arm-trusted-firmware uefi-check-arm-tf-links
	$(ECHO) '  BUILD   $@'
	$(Q)export GCC49_AARCH64_PREFIX="$(CROSS_COMPILE64)" ; \
	    cd uefi ; \
	    ./uefi-tools/uefi-build.sh -b $(UEFI_DEB_OR_REL) -c LinaroPkg/platforms.config d02

.PHONY: clean-uefi
clean-uefi:
	$(ECHO) '  RESTORE $(UEFI_BL1)'
	$(Q)rm -f $(UEFI_BL1) ; cd $(UEFI_BIN) && git co bl1.bin
	$(ECHO) '  RESTORE $(UEFI_FIP)'
	$(Q)rm -f $(UEFI_FIP) ; cd $(UEFI_BIN) && git co fip.bin

clean: clean-uefi

#
# aes-perf (AES crypto performance test)
#

aes-perf-flags := CROSS_COMPILE_HOST="$(CROSS_COMPILE64)" \
                  CROSS_COMPILE_TA="$(CROSS_COMPILE_TA)" \
                  TA_DEV_KIT_DIR=$(PWD)/optee_os/out/arm-plat-d02/export-ta_arm$(SU)

.PHONY: aes-perf
aes-perf: optee-os optee-client
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C aes-perf $(aes-perf-flags)

.PHONY: install-aes-perf
install-aes-perf:
	$(ECHO) '  INSTALL $@'
	$(Q)$(MAKE) -C aes-perf $(aes-perf-flags) install DESTDIR=$(DESTDIR)

install: install-aes-perf

.PHONY: clean-aes-perf
clean-aes-perf:
	$(ECHO) '  CLEAN   $@'
	$(Q)rm -rf aes-perf/out

clean: clean-aes-perf

#
# sha-perf (SHA crypto performance test)
#

sha-perf-flags := CROSS_COMPILE_HOST="$(CROSS_COMPILE64)" \
                  CROSS_COMPILE_TA="$(CROSS_COMPILE_TA)" \
                  TA_DEV_KIT_DIR=$(PWD)/optee_os/out/arm-plat-d02/export-ta_arm$(SU)

.PHONY: sha-perf
sha-perf: optee-os optee-client
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C sha-perf $(sha-perf-flags)

.PHONY: install-sha-perf
install-sha-perf:
	$(ECHO) '  INSTALL $@'
	$(Q)$(MAKE) -C sha-perf $(sha-perf-flags) install DESTDIR=$(DESTDIR)

install: install-sha-perf

.PHONY: clean-sha-perf
clean-sha-perf:
	$(ECHO) '  CLEAN   $@'
	$(Q)rm -rf sha-perf/out

clean: clean-sha-perf

#
# tee-stats (statistics tool, client side of static TA:
# core/arch/arm/sta/stats.c)
#

tee-stats-flags := CROSS_COMPILE_HOST="$(CROSS_COMPILE64)"

.PHONY: tee-stats
tee-stats: optee-client
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C tee-stats $(tee-stats-flags)

.PHONY: install-tee-stats
install-tee-stats:
	$(ECHO) '  INSTALL $@'
	$(Q)$(MAKE) -C tee-stats $(tee-stats-flags) install DESTDIR=$(DESTDIR)

install: install-tee-stats

.PHONY: clean-tee-stats
clean-tee-stats:
	$(ECHO) '  CLEAN   $@'
	$(Q)rm -rf tee-stats/out

clean: clean-tee-stats


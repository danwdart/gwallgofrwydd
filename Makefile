SHELL=/bin/bash -O extglob -c
PROJROOT = $(realpath .)
SRC = $(PROJROOT)/src
ROOT_SKEL = $(PROJROOT)/root-skel
ROOT = $(PROJROOT)/root
EFIROOT = $(PROJROOT)/efiroot
BUILD = $(PROJROOT)/build
CC = /usr/bin/gcc
THREADS = 12
QEMU_RAM = 512
QEMU_CPUS = 4
MAKE = /usr/bin/make -j$(THREADS)
DISKIMG = $(BUILD)/disk.img
PARTIMG = $(BUILD)/part.img
DISKSECTS = 204800
STARTSECT = 2048
ENDSECT = 204766
PARTSECTS = 202720
EFIBIOS = $(SRC)/uefi.bin
BOOTEFIPATH = EFI/BOOT
BOOTEFINAME = BOOTX64.EFI
BOOTEFIFILE = $(BOOTEFIPATH)/$(BOOTEFINAME)

all: $(BUILD)/kernel

clean:
	rm -rf $(EFIROOT) $(BUILD) $(ROOT)

$(ROOT)/.fs_ready:
	cp -r $(ROOT_SKEL) $(ROOT)
	mkdir -p $(BUILD) $(ROOT)/{dev,home,proc,root,sys,tmp,var/{log,tmp}}
	touch $(ROOT)/.fs_ready

libs_install: openssl_install

apps_install: $(ROOT)/.fs_ready $(ROOT)/bin/busybox $(ROOT)/apps/ddate $(ROOT)/apps/git $(ROOT)/apps/tcc $(ROOT)/etc/protocols $(ROOT)/apps/vim $(ROOT)/apps/node

# Kernel
$(SRC)/linux/.config:
	cp configs/linux $(SRC)/linux/.config

$(SRC)/linux/kernel/configs.ko: $(SRC)/linux/.config
	cd $(SRC)/linux && $(MAKE) modules

$(ROOT)/lib/modules: $(SRC)/linux/kernel/configs.ko
	cd $(SRC)/linux && $(MAKE) INSTALL_MOD_PATH=$(ROOT) modules_install

$(SRC)/linux/arch/x86/boot/bzImage: apps_install $(ROOT)/lib/modules
	cd $(SRC)/linux && $(MAKE) bzImage

$(BUILD)/kernel: $(SRC)/linux/arch/x86/boot/bzImage
	cp $(SRC)/linux/arch/x86/boot/bzImage $(BUILD)/kernel

#$(BUILD)/initramfs: apps_install
#	cd $(ROOT) && find | cpio --owner=0:0 -oH newc | gzip > $(BUILD)/initramfs && cd ..

# Libraries
openssl:
	cd $(SRC)/openssl && ./config -static -fPIC --prefix=/ && $(MAKE) all

openssl_install: openssl
	cd $(SRC)/openssl && $(MAKE) CFLAGS=-static CCFLAGS=-static LDFLAGS=-static MAKEFLAGS=-static DESTDIR=$(ROOT)/libs/openssl install

# Software

# busybox

$(SRC)/busybox/busybox: $(SRC)/busybox/.config
	cd $(SRC)/busybox && $(MAKE) DESTDIR=$(ROOT)

$(ROOT)/bin/busybox: $(SRC)/busybox/busybox
	cd $(SRC)/busybox && $(MAKE) install

$(SRC)/busybox/.config:
	cp configs/busybox $(SRC)/busybox/.config

# ddate

$(SRC)/ddate/build/ddate:
	cd $(SRC)/ddate && mkdir -p build && cd build && cmake -DCMAKE_INSTALL_PREFIX=/ ../ && $(MAKE)

$(ROOT)/apps/ddate: $(SRC)/ddate/build/ddate
	cd $(SRC)/ddate/build && $(MAKE) DESTDIR=$(ROOT)/apps/ddate install

# git

$(SRC)/git/git:
	cd $(SRC)/git && $(MAKE) CFLAGS="$(CFLAGS) -static -ldl" CCFLAGS="$(CCFLAGS) -static -ldl" LDFLAGS="$(LDFLAGS) -static -ldl" NO_OPENSSL=1 NO_CURL=1 NO_INSTALL_HARDLINKS=1 prefix=/

$(ROOT)/apps/git: $(SRC)/git/git
	cd $(SRC)/git && $(MAKE) CFLAGS="$(CFLAGS) -static -ldl" CCFLAGS="$(CCFLAGS) -static -ldl" LDFLAGS="$(LDFLAGS) -static -ldl" NO_OPENSSL=1 NO_CURL=1 NO_INSTALL_HARDLINKS=1 prefix=/ DESTDIR=$(ROOT)/apps/git install

# vim

$(SRC)/vim/src/vim:
	cd $(SRC)/vim && CFLAGS=-static CCFLAGS=-static LDFLAGS=-static ./configure --prefix=/ && $(MAKE) CFLAGS=-static CCFLAGS=-static LDFLAGS=-static

$(ROOT)/apps/vim: $(SRC)/vim/src/vim
	cd $(SRC)/vim && $(MAKE) CFLAGS=-static CCFLAGS=-static LDFLAGS=-static DESTDIR=$(ROOT)/apps/vim install

# iana_etc

$(ROOT)/etc/protocols:
	cd $(SRC)/iana-etc && $(MAKE) STRIP=yes DESTDIR=$(ROOT) install

# tcc

$(SRC)/tinycc/tcc:
	cd $(SRC)/tinycc && ./configure --prefix=/ && $(MAKE) CFLAGS=-static CCFLAGS=-static LDFLAGS=-static

$(ROOT)/apps/tcc: $(SRC)/tinycc/tcc
	cd $(SRC)/tinycc && $(MAKE) DESTDIR=$(ROOT)/apps/tcc install

# node

$(SRC)/node/node:
	cd $(SRC)/node && ./configure --prefix=/ --fully-static && $(MAKE)

$(ROOT)/apps/node: $(SRC)/node/node
	cd $(SRC)/node && $(MAKE) DESTDIR=$(ROOT)/apps/node install

# Filesystem
$(EFIROOT)/$(BOOTEFIFILE): $(BUILD)/kernel
	mkdir -p $(EFIROOT)/$(BOOTEFIPATH)
	cp $(BUILD)/kernel $(EFIROOT)/$(BOOTEFIFILE)

# UEFI Boot image compilation
makedisk:
	dd if=/dev/zero of=$(DISKIMG) bs=512 count=$(DISKSECTS)

partdisk: makedisk
	sgdisk -o -n 1:$(STARTSECT):$(ENDSECT) -t 1:ef00 -c 1:"EFI System" -p $(DISKIMG)

makepart:
	dd if=/dev/zero of=$(PARTIMG) bs=512 count=$(PARTSECTS)
	mkfs.vfat -F32 $(PARTIMG)

copytopart: makepart $(BUILD)/kernel
	mmd -i $(PARTIMG) ::/EFI
	mmd -i $(PARTIMG) ::/EFI/BOOT
	mcopy -i $(PARTIMG) $(BUILD)/kernel ::/EFI/BOOT/BOOTX64.EFI

bootimg: partdisk copytopart
	dd if=$(PARTIMG) of=$(DISKIMG) bs=512 seek=2048 count=$(PARTSECTS) conv=notrunc

# Emulation

qemuraw: $(BUILD)/kernel # $(BUILD)/initramfs
	qemu-system-x86_64 -cpu qemu64 -kernel $(BUILD)/kernel -m $(QEMU_RAM) -smp $(QEMU_CPUS) #-initrd $(BUILD)/initramfs -append "root=/dev/ram0"

qemuefi: $(EFIBIOS) bootimg
	qemu-system-x86_64 -cpu qemu64 -bios $(EFIBIOS) -drive file=$(DISKIMG),format=raw -m $(QEMU_RAM) -smp $(QEMU_CPUS)

qemuefifat: $(EFIBIOS) $(EFIROOT)/$(BOOTEFIFILE)
	qemu-system-x86_64 -cpu qemu64 -bios $(EFIBIOS) -drive file=fat:rw:$(EFIROOT) -m $(QEMU_RAM) -smp $(QEMU_CPUS)

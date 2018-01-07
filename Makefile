SHELL = /bin/sh
PROJROOT = $(realpath .)
SRC = $(PROJROOT)/src
ROOT_SKEL = $(PROJROOT)/root-skel
ROOT = $(PROJROOT)/root
EFIROOT = $(PROJROOT)/efiroot
BUILD = $(PROJROOT)/build
CC = /usr/bin/gcc
THREADS = 12
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

all: fs_build linux

fs_build: $(ROOT)/.fs_ready $(ROOT)/.apps_ready

fs_skeleton:
	cp -r $(ROOT_SKEL) $(ROOT)
	mkdir -p $(BUILD) $(ROOT)/{dev,home,proc,root,sys,tmp,var/{log,tmp}}
	touch $(ROOT)/.fs_ready

libs_install: openssl_install

apps_install: $(ROOT)/bin/busybox $(ROOT)/apps/ddate $(ROOT)/apps/git $(ROOT)/apps/tcc $(ROOT)/etc/protocols
	touch $(ROOT)/.apps_ready

clean:
	rm -rf $(EFIROOT) $(BUILD) $(ROOT)

# Kernel

linux: $(ROOT)/lib/modules $(BUILD)/kernel $(BUILD)/initramfs

linux_copy_config:
		cp configs/linux $(SRC)/linux/.config

linux_modules: $(SRC)/linux/.config
	cd $(SRC)/linux && $(MAKE) modules

linux_modules_install: linux_modules
	cd $(SRC)/linux && $(MAKE) INSTALL_MOD_PATH=$(ROOT) modules_install

linux_image:
	cd $(SRC)/linux && $(MAKE) bzImage

linux_image_copy: $(SRC)/linux/arch/x86/boot/bzImage
	cp $(SRC)/linux/arch/x86/boot/bzImage $(BUILD)/kernel

initramfs: fs_build
	cd $(ROOT) && find | cpio --owner=0:0 -oH newc | gzip > $(BUILD)/initramfs && cd ..

# Libraries
openssl:
	cd $(SRC)/openssl && ./config -static -fPIC --prefix=/ && $(MAKE) all

openssl_install: openssl
	cd $(SRC)/openssl && $(MAKE) CFLAGS=-static CCFLAGS=-static LDFLAGS=-static MAKEFLAGS=-static DESTDIR=$(ROOT)/libs/openssl install

# Software

# busybox

busybox: busybox_copy_config
	cd $(SRC)/busybox && $(MAKE) DESTDIR=$(ROOT)

busybox_install: busybox
	cd $(SRC)/busybox && $(MAKE) install

busybox_copy_config:
	cp configs/busybox $(SRC)/busybox/.config

# ddate

ddate:
	cd $(SRC)/ddate && mkdir -p build && cd build && cmake -DCMAKE_INSTALL_PREFIX=/ ../ && $(MAKE)

ddate_install: ddate
	cd $(SRC)/ddate/build && $(MAKE) DESTDIR=$(ROOT)/apps/ddate install

# git

git:
	cd $(SRC)/git && $(MAKE) CFLAGS="$(CFLAGS) -static -ldl" CCFLAGS="$(CCFLAGS) -static -ldl" LDFLAGS="$(LDFLAGS) -static -ldl" NO_OPENSSL=1 NO_CURL=1 NO_INSTALL_HARDLINKS=1 prefix=/

git_install: git
	cd $(SRC)/git && $(MAKE) CFLAGS="$(CFLAGS) -static -ldl" CCFLAGS="$(CCFLAGS) -static -ldl" LDFLAGS="$(LDFLAGS) -static -ldl" NO_OPENSSL=1 NO_CURL=1 NO_INSTALL_HARDLINKS=1 prefix=/ DESTDIR=$(ROOT)/apps/git install

# vim

vim:
	cd $(SRC)/vim && CFLAGS=-static CCFLAGS=-static LDFLAGS=-static ./configure --prefix=/ && $(MAKE) CFLAGS=-static CCFLAGS=-static LDFLAGS=-static

vim_install: vim
	cd $(SRC)/vim && $(MAKE) CFLAGS=-static CCFLAGS=-static LDFLAGS=-static DESTDIR=$(ROOT)/apps/vim install

# iana_etc

iana_etc_install:
	cd $(SRC)/iana-etc && $(MAKE) STRIP=yes DESTDIR=$(ROOT) install

# tcc

tcc:
	cd $(SRC)/tinycc && ./configure --prefix=/ && $(MAKE) CFLAGS=-static CCFLAGS=-static LDFLAGS=-static

tcc_install: tcc
	cd $(SRC)/tinycc && $(MAKE) DESTDIR=$(ROOT)/apps/tcc install

# node

node:
	cd $(SRC)/node && ./configure --prefix=/ --fully-static && $(MAKE)

node_install: node
	cd $(SRC)/node && $(MAKE) DESTDIR=$(ROOT)/apps/node install

# Filesystem
createefifs: $(BUILD)/kernel
	mkdir -p $(EFIROOT)/$(BOOTEFIPATH)
	cp $(BUILD)/kernel $(EFIROOT)/$(BOOTEFIFILE)

# UEFI Boot image compilation
bootimg: makedisk partdisk makepart copytopart parttodisk

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

parttodisk: partdisk copytopart
	dd if=$(PARTIMG) of=$(DISKIMG) bs=512 seek=2048 count=$(PARTSECTS) conv=notrunc

# Emulation

qemuraw: $(BUILD)/kernel $(BUILD)/initramfs
	qemu-system-x86_64 -kernel $(BUILD)/kernel -initrd $(BUILD)/initramfs -append "root=/dev/ram0" -m 512 -smp 4

qemuefi: $(EFIBIOS) bootimg
	qemu-system-x86_64 -cpu qemu64 -bios $(EFIBIOS) -drive file=$(DISKIMG),format=raw -m 512 -smp 4

qemuefifat: $(EFIBIOS) $(EFIROOT)/$(BOOTEFIFILE)
	qemu-system-x86_64 -cpu qemu64 -bios $(EFIBIOS) -drive file=fat:rw:$(EFIROOT) -m 512 -smp 4

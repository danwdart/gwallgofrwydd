SHELL = /bin/sh
PROJROOT = $(realpath .)
SRC = $(PROJROOT)/src
ROOT = $(PROJROOT)/root
EFIROOT = $(PROJROOT)/efiroot
CC = /usr/bin/gcc
THREADS = 12
MAKE = /usr/bin/make -j$(THREADS)
DISKIMG = build/disk.img
PARTIMG = build/part.img
DISKSECTS = 204800
STARTSECT = 2048
ENDSECT = 204766
PARTSECTS = 202720
EFIBIOS = $(SRCPATH)/uefi.bin
BOOTEFIPATH = EFI/BOOT
BOOTEFINAME = BOOTX64.EFI
BOOTEFIFILE = $(BOOTEFIPATH)/$(BOOTEFINAME)

all: fs_build linux

fs_build: fs_skeleton apps_install symlinks

fs_skeleton:
	cd root && mkdir -p dev home proc root sys tmp var/log var/tmp	

libs_install: openssl_install

apps_install: busybox_install ddate_install git_install tcc_install iana_etc_install

clean:
	rm -rf build/* root/{bin,sbin,share,lib,libexec,include,etc/{protocols,services}}

# Kernel
	
linux: linux_modules_install linux_image_copy initramfs

linux_copy_config:
	cp configs/linux $(SRC)/linux/.config

linux_modules: linux_copy_config
	cd $(SRC)/linux && $(MAKE) modules

linux_modules_install: linux_modules
	cd $(SRC)/linux && $(MAKE) INSTALL_MOD_PATH=$(ROOT) modules_install

linux_image:
	cd $(SRC)/linux && $(MAKE) bzImage

linux_image_copy: linux_image
	cp $(SRC)/linux/arch/x86/boot/bzImage build/kernel

initramfs: fs_build
	cd $(ROOT) && find | cpio --owner=0:0 -oH newc | gzip > ../build/initramfs && cd ..

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

tcc_install:
	cd $(SRC)/tinycc && $(MAKE) DESTDIR=$(ROOT)/apps/tcc install

# node

node:
	cd $(SRC)/node && ./configure --prefix=/ --fully-static && $(MAKE)

node_install:
	cd $(SRC)/node && $(MAKE) DESTDIR=$(ROOT)/apps/node install

# Packaging

symlinks:
	cd root/apps && for d in *; do cd $d; find -type d | cut -d . -f 2 | xargs echo mkdir -p; \
	for f in $(find -type f | cut -d . -f 2); do echo ln -sv $$PWD/$$f $(ROOT)$$f; done; \
	cd ..; \
	done

# Filesystem
createefifs: linux
	mkdir -p $(EFIROOT)/$(BOOTEFIPATH)
	cp build/kernel $(EFIROOT)/$(BOOTEFIFILE)
	
# UEFI Boot image compilation
bootimg: makedisk partdisk makepart copytopart parttodisk

makedisk:
	dd if=/dev/zero of=$(DISKIMG) bs=512 count=$(DISKSECTS)

partdisk: makedisk
	sgdisk -o -n 1:$(STARTSECT):$(ENDSECT) -t 1:ef00 -c 1:"EFI System" -p $(DISKIMG)

makepart:
	dd if=/dev/zero of=$(PARTIMG) bs=512 count=$(PARTSECTS)
	mkfs.vfat -F32 $(PARTIMG)

copytopart: makepart linux
	mmd -i $(PARTIMG) ::/EFI
	mmd -i $(PARTIMG) ::/EFI/BOOT
	mcopy -i $(PARTIMG) build/kernel ::/EFI/BOOT/BOOTX64.EFI

parttodisk: partdisk copytopart
	dd if=$(PARTIMG) of=$(DISKIMG) bs=512 seek=2048 count=$(PARTSECTS) conv=notrunc

# Emulation

qemuraw: linux initramfs 
	qemu-system-x86_64 -kernel build/kernel -initrd build/initramfs -append "root=/dev/ram0" -m 512
	
qemuefi: bootimg
	qemu-system-x86_64 -cpu qemu64 -bios $(EFIBIOS) -drive file=$(DISKIMG),format=raw -m 512

qemuefifat: createefifs
	qemu-system-x86_64 -cpu qemu64 -bios $(EFIBIOS) file=fat:rw:$(EFIROOT) -m 512


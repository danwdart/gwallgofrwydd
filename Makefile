SHELL = /bin/sh
PROJROOT = $(realpath .)
ROOT = $(PROJROOT)/root
CC = /usr/bin/gcc
THREADS = 6
MAKE = /usr/bin/make -j${THREADS}
DISKIMG = build/disk.img
PARTIMG = build/part.img
PARTEDCMD = parted ${DISKIMG} -s -a minimal
DISKSECTS = 204800
STARTSECT = 2048
ENDSECT = 204766
PARTSECTS = 202720
EFIBIOS = src/uefi.bin

all: busybox_install ddate_install git_install iana_etc_install linux

clean:
	rm -rf build/* root/{bin,sbin,share,lib,libexec,include,etc/{protocols,services}}

linux: linux_modules_install linux_image_copy

linux_copy_config:
	cp configs/linux src/linux/.config

linux_modules: linux_copy_config
	cd src/linux && ${MAKE} modules

linux_modules_install: linux_modules
	cd src/linux && ${MAKE} INSTALL_MOD_PATH=${ROOT} modules_install

linux_image:
	cd src/linux && ${MAKE} bzImage

linux_image_copy: linux_image
	cp src/linux/arch/x86/boot/bzImage build/kernel

busybox: busybox_copy_config
	cd src/busybox && ${MAKE} DESTDIR=$(ROOT)

busybox_install: busybox
	cd src/busybox && ${MAKE} install

busybox_copy_config:
	cp configs/busybox src/busybox/.config

ddate:
	cd src/ddate && mkdir -p build && cd build && cmake ../ && ${MAKE} CMAKE_INSTALL_PREFIX=/apps/ddate

ddate_install: ddate
	cd src/ddate/build && ${MAKE} DESTDIR=${ROOT} CMAKE_INSTALL_PREFIX=/apps/ddate install

git:
	cd src/git && ${MAKE} CFLAGS="${CFLAGS} -static -ldl" CCFLAGS="${CCFLAGS} -static -ldl" LDFLAGS="${LDFLAGS} -static -ldl" NO_OPENSSL=1 NO_CURL=1 NO_INSTALL_HARDLINKS=1 prefix=/


git_install: git
	cd src/git && ${MAKE} CFLAGS="${CFLAGS} -static -ldl" CCFLAGS="${CCFLAGS} -static -ldl" LDFLAGS="${LDFLAGS} -static -ldl" NO_OPENSSL=1 NO_CURL=1 NO_INSTALL_HARDLINKS=1 prefix=/ DESTDIR=${ROOT} install

vim:
	cd src/vim && CFLAGS=-static CCFLAGS=-static LDFLAGS=-static ./configure --prefix=/ && ${MAKE} CFLAGS=-static CCFLAGS=-static LDFLAGS=-static

vim_install: vim
	cd src/vim && ${MAKE} CFLAGS=-static CCFLAGS=-static LDFLAGS=-static DESTDIR=${ROOT} install

iana_etc_install:
	cd src/iana-etc && ${MAKE} STRIP=yes DESTDIR=${ROOT} install

tcc:


#initramfs:
#	cd root && find | cpio --owner=0:0 -oH newc | gzip > ../build/initramfs && cd ..

qemu:
	qemu-system-x86_64 -kernel build/kernel -append "root=/dev/ram0" -m 256

bootimg: disk partdisk part copyfilestopart parttodisk

disk:
	dd if=/dev/zero of=build/disk.img bs=512 count=${DISKSECTS}

partdisk:
	sgdisk -o -n 1:${STARTSECT}:${ENDSECT} -t 1:ef00 -c 1:"EFI System" -p build/disk.img

part:
	dd if=/dev/zero of=${PARTIMG} bs=512 count=${PARTSECTS}
	mkfs.vfat -F32 ${PARTIMG} # mformat -i ${PARTIMG} -h 32 -t 32 -n 64 -c 1

copyfilestopart:
	mmd -i ${PARTIMG} ::/EFI
	mmd -i ${PARTIMG} ::/EFI/BOOT
	mcopy -i ${PARTIMG} build/kernel ::/EFI/BOOT/BOOTX64.EFI

parttodisk:
	dd if=${PARTIMG} of=${DISKIMG} bs=512 seek=2048 count=${PARTSECTS} conv=notrunc

qemuefi:
	qemu-system-x86_64 -cpu qemu64 -bios ${EFIBIOS} -drive file=${DISKIMG},format=raw

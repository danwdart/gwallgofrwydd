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
PARTSECTS = 202720
EFIBIOS = /usr/share/qemu-efi/QEMU_EFI.fd

all: busybox_install ddate_install git_install vim_install iana_etc_install linux_modules_install linux_install initramfs

clean:
	rm -rf build/*

linux:
	cd src/linux && ${MAKE} defconfig mrproper all

linux_modules_install: linux
	cd src/linux && ${MAKE} INSTALL_MOD_PATH=${ROOT} install

linux_install: linux
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

initramfs:
	cd root && find | cpio --owner=0:0 -oH newc | gzip > ../build/initramfs && cd ..

qemu:
	qemu-system-x86_64 -kernel build/kernel -initrd build/initramfs -append "root=/dev/ram0" -m 256

grubimg:
	grub-mkimage -Ox86_64-efi -o build/grub.efi

bootimg: disk partdisk part copyfiles parttodisk

disk:
	dd if=/dev/zero of=build/disk.img bs=512 count=${DISKSECTS}

partdisk:
	echo -e "o\ny\nn\n\n\n\nef00\nw\ny\n" | gdisk build/disk.img
	# ${PARTEDCMD} mklabel gpt
	# ${PARTEDCMD} mkpart EFI FAT16 2048s # 93716s
	# ${PARTEDCMD} toggle 1 boot

part:
	dd if=/dev/zero of=${PARTIMG} bs=512 count=${PARTSECTS}
	mkfs.vfat -F32 ${PARTIMG} # mformat -i ${PARTIMG} -h 32 -t 32 -n 64 -c 1

copyfiles: grubimg
	mcopy -i ${PARTIMG}	build/initramfs build/kernel ::/
	mmd -i ${PARTIMG} ::/EFI
	mmd -i ${PARTIMG} ::/EFI/BOOT
	mmd -i ${PARTIMG} ::/boot
	mmd -i ${PARTIMG} ::/boot/grub
	mcopy -i ${PARTIMG} build/grub.efi ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i ${PARTIMG} configs/grub.cfg ::/boot/grub

parttodisk:
	dd if=${PARTIMG} of=${DISKIMG} bs=512 seek=2048 count=${PARTSECTS} conv=notrunc

qemuefi:
	qemu-system-x86_64 -cpu qemu64 -bios ${EFIBIOS} -drive file=${DISKIMG},format=raw

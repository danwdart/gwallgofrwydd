SHELL = /bin/sh
PROJROOT = $(realpath .)
ROOT=$(PROJROOT)/root
CC=/usr/bin/gcc

all: busybox_install ddate_install initramfs

clean:
	rm build/initramfs

busybox: busybox_copy_config
	cd src/busybox && make DESTDIR=$(ROOT)

busybox_install: busybox
	cd src/busybox && make install

busybox_copy_config:
	cp configs/busybox src/busybox/.config

ddate:
	cd src/ddate && $(CC) -static ddate.c -o ddate

ddate_install: ddate
	cp src/ddate/ddate root/bin/

initramfs:
	cd root && find | cpio --owner=0:0 -oH newc | gzip > ../build/initramfs && cd ..

qemu:
	qemu-system-x86_64 -kernel build/kernel -initrd build/initramfs

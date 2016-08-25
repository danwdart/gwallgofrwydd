SHELL = /bin/sh
PROJROOT = $(realpath .)
ROOT=$(PROJROOT)/root
CC=/usr/bin/gcc
THREADS=6
MAKE=/usr/bin/make -j${THREADS}

all: busybox_install ddate_install git_install vim_install initramfs

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

git:
	cd src/git && ${MAKE} CFLAGS="${CFLAGS} -static -ldl" CCFLAGS="${CCFLAGS} -static -ldl" LDFLAGS="${LDFLAGS} -static -ldl" NO_OPENSSL=1 NO_CURL=1 NO_INSTALL_HARDLINKS=1 prefix=/
 

git_install: git
	cd src/git && ${MAKE} CFLAGS="${CFLAGS} -static -ldl" CCFLAGS="${CCFLAGS} -static -ldl" LDFLAGS="${LDFLAGS} -static -ldl" NO_OPENSSL=1 NO_CURL=1 NO_INSTALL_HARDLINKS=1 prefix=/ DESTDIR=${ROOT} install

vim:
	cd src/vim && CFLAGS=-static CCFLAGS=-static LDFLAGS=-static ./configure --prefix=/ && ${MAKE} CFLAGS=-static CCFLAGS=-static LDFLAGS=-static

vim_install: vim
	cd src/vim && ${MAKE} CFLAGS=-static CCFLAGS=-static LDFLAGS=-static DESTDIR=${ROOT} install

initramfs:
	cd root && find | cpio --owner=0:0 -oH newc | gzip > ../build/initramfs && cd ..

qemu:
	qemu-system-x86_64 -kernel build/kernel -initrd build/initramfs -append "root=/dev/ram0" -m 256

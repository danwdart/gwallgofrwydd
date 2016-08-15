all: initramfs

clean:
	rm build/initramfs

initramfs:
	cd root && find | cpio -oH newc | gzip > ../build/initramfs && cd ..

qemu:
	qemu-system-x86_64 -kernel build/kernel -initrd build/initramfs

#!/bin/sh
set -xe
readonly THREADS=$(nproc)
readonly OKSH_VERSION="7.8"
readonly TOYBOX_VERSION="0.8.9"
readonly LINUX_VERSION="7.0"

mkdir -p build
cd build

if [ ! -d fs ]; then
	mkdir fs
	cd fs

	mkdir bin lib usr dev proc sys tmp run etc mnt root opt

	ln -s bin sbin
	ln -s ../bin usr/bin
	ln -s ../bin usr/sbin

	ln -s lib lib32
	ln -s lib lib64
	ln -s ../lib usr/lib
	ln -s ../lib usr/lib32
	ln -s ../lib usr/lib64

	cd ..
fi
cp -a ../fs/. fs

mkdir -p boot/boot
cp -a ../boot/. boot/boot

if [ ! -d sinit ]; then
	git clone git://git.suckless.org/sinit
	cp ../sinit/config.h sinit
fi
cd sinit
make
make install DESTDIR=../fs PREFIX=/usr
cd ..

if [ ! -d oksh ]; then
	wget \
		-O oksh.tar.gz \
		https://github.com/ibara/oksh/releases/download/oksh-$OKSH_VERSION/oksh-$OKSH_VERSION.tar.gz
	tar xf oksh.tar.gz
	rm oksh.tar.gz
	mv oksh-$OKSH_VERSION oksh
fi
cd oksh
if [ ! -f Makefile ]; then
	export CFLAGS="-std=c99 -Os -pipe -Wall -Wextra -fno-pie -fno-PIE"
	export LDFLAGS="-static -no-pie -s"
	./configure --no-thanks
fi
make -j$THREADS
cd ..
cp oksh/oksh fs/bin/
ln -sf oksh fs/bin/sh

if [ ! -d toybox ]; then
	wget \
		-O toybox.tar.gz \
		https://landley.net/toybox/downloads/toybox-$TOYBOX_VERSION.tar.gz
	tar -xf toybox.tar.gz
	rm toybox.tar.gz
	mv toybox-$TOYBOX_VERSION toybox
fi
cd toybox
if [ ! -f .config ]; then
	cp ../../toybox/.config .
fi
export CFLAGS="-Os -U_FORTIFY_SOURCE -static"
export PREFIX=../fs/bin
make -j$THREADS
make install_flat
cd ..

if [ ! -d linux ]; then
	readonly LINUX_MAJOR=${LINUX_VERSION%%.*}
	wget \
		-O linux.tar.xz \
		https://cdn.kernel.org/pub/linux/kernel/v$LINUX_MAJOR.x/linux-$LINUX_VERSION.tar.xz
	tar xf linux.tar.xz
	rm linux.tar.xz
	mv linux-$LINUX_VERSION "linux"
fi
cd linux
if [ ! -f .config ]; then
	cp ../../linux/.config .
fi
if [ ! -f drivers/video/logo/logo_microbuntu_clut224.ppm ]; then
	cp ../../linux/drivers/video/logo/logo_microbuntu_clut224.ppm drivers/video/logo/logo_microbuntu_clut224.ppm
fi
make bzImage -j $THREADS
cd ..
cp -f linux/arch/x86/boot/bzImage boot/boot/vmlinuz

cd fs
find | cpio -o -H newc > ../boot/boot/init.cpio
cd ..
grub-mkrescue -o microbuntu.iso boot

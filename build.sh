#!/bin/sh
set -xe
readonly THREADS=$(nproc)
readonly OKSH_VERSION="7.8"
readonly TOYBOX_VERSION="0.8.9"

mkdir -p build
cd build

if [ ! -d "fs" ]; then
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

mkdir -p boot
cp -a ../boot/. boot

if [ ! -d "oksh" ]; then
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
	cd ..
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
	make defconfig
	echo "CONFIG_INIT=y" >> .config
	echo "CONFIG_GETTY=y" >> .config
fi
export CFLAGS="-Os -U_FORTIFY_SOURCE -static"
export PREFIX=../fs/bin
make -j$THREADS
make install_flat
cd ..

cd fs
find | cpio -o -H newc > ../boot/init.cpio
cd ..
grub-mkrescue -o microbuntu.iso boot

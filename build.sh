#!/bin/sh
set -xe
readonly THREADS=$(nproc)
readonly MUSL_VERSION="1.2.6"
readonly BINUTILS_VERSION="2.41"
readonly GCC_VERSION="13.2.0"
readonly OKSH_VERSION="7.8"
readonly TOYBOX_VERSION="0.8.9"
readonly LINUX_VERSION="7.0"

mkdir -p build
cd build

readonly FS="$(realpath ./fs)"
if [ ! -d $FS ]; then
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

if [ ! -d musl ]; then
	wget \
		-O musl.tar.gz \
		https://git.musl-libc.org/cgit/musl/snapshot/musl-$MUSL_VERSION.tar.gz
	tar xf musl.tar.gz
	rm musl.tar.gz
	mv musl-$MUSL_VERSION musl
fi
cd musl
if [ ! -f config.mak ]; then
	./configure --prefix=/usr --syslibdir=/lib --disable-shared
fi
make -j$THREADS
make DESTDIR=../fs install
cd ..


# Building toolchain
mkdir -p toolchain
readonly TOOLCHAIN="$(realpath ./toolchain)"
export PATH="$PATH:$TOOLCHAIN/bin"

if [ ! -d binutils ]; then
	wget \
		-O binutils.tar.gz \
		https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VERSION.tar.gz
	tar -xf binutils.tar.gz
	rm binutils.tar.gz
	mv binutils-$BINUTILS_VERSION binutils
fi
cd binutils
mkdir -p build/target
cd build/target
if [ ! -f Makefile ]; then
	../../configure --target=x86_64-linux-musl --prefix="$TOOLCHAIN" --with-sysroot="$FS" --disable-nls --disable-werror
fi
make -j$THREADS
make install
cd ../../..

if [ ! -d gcc ]; then
	wget \
		-O gcc.tar.gz \
		https://ftp.gnu.org/gnu/gcc/gcc-13.2.0/gcc-$GCC_VERSION.tar.gz
	tar -xf gcc.tar.gz
	rm gcc.tar.gz
	mv gcc-$GCC_VERSION gcc
fi
cd gcc
mkdir -p build/target
cd build/target
if [ ! -f Makefile ]; then
	../../configure --target=x86_64-linux-musl --prefix="$TOOLCHAIN" --with-sysroot="$FS" --disable-nls --enable-languages=c,c++ --disable-multilib --without-headers
fi
make all-gcc -j$THREADS
make all-target-libgcc -j$THREADS
make install-gcc
make install-target-libgcc
cd ../../..
export CC=x86_64-linux-musl-gcc

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
make headers_install \
	ARCH=x86_64 \
	INSTALL_HDR_PATH="$TOOLCHAIN"
make bzImage -j $THREADS
cd ..
cp -f linux/arch/x86/boot/bzImage boot/boot/vmlinuz

if [ ! -d sinit ]; then
	git clone git://git.suckless.org/sinit
	cp ../sinit/config.h sinit
fi
cd sinit
make -j$THREADS CC=x86_64-linux-musl-gcc
make DESTDIR=../fs PREFIX=/usr install
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
make -j$THREADS CC=x86_64-linux-musl-gcc
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
export CFLAGS="-Os -U_FORTIFY_SOURCE -I$TOOLCHAIN/include"
export PREFIX=../fs/bin
make -j$THREADS
make install_flat
cd ..

cd fs
find | cpio -o -H newc > ../boot/boot/init.cpio
cd ..
grub-mkrescue -o microbuntu.iso boot

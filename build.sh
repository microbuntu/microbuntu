#!/bin/sh
readonly THREADS=$(nproc)
readonly MUSL_VERSION="1.2.6"
readonly BINUTILS_VERSION="2.41"
readonly GCC_VERSION="13.2.0"
readonly OKSH_VERSION="7.8"
readonly TOYBOX_VERSION="0.8.9"
readonly LINUX_VERSION="7.0"

run() {
	"$@" > run.log 2>&1
	code=$?
	if [ $code -ne 0 ]; then
		cat run.log
		echo "$@: exited with code $code"
		exit $code
	fi
}

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
	printf "download\tmusl\n"
	run wget \
		-O musl.tar.gz \
		https://git.musl-libc.org/cgit/musl/snapshot/musl-$MUSL_VERSION.tar.gz
	run tar xf musl.tar.gz
	rm musl.tar.gz
	run mv musl-$MUSL_VERSION musl
fi
cd musl
if [ ! -f config.mak ]; then
	printf "configure\tmusl\n"
	run ./configure --prefix=/usr --syslibdir=/lib --disable-shared
fi
printf "build\t\tmusl\n"
run make -j$THREADS
printf "install\t\tmusl\n"
run make DESTDIR=../fs install
cd ..

# Building toolchain
mkdir -p toolchain
readonly TOOLCHAIN="$(realpath ./toolchain)"
export PATH="$PATH:$TOOLCHAIN/bin"

if [ ! -d binutils ]; then
	printf "download\tbinutils\n"
	run wget \
		-O binutils.tar.gz \
		https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VERSION.tar.gz
	run tar -xf binutils.tar.gz
	rm binutils.tar.gz
	run mv binutils-$BINUTILS_VERSION binutils
fi
cd binutils
mkdir -p build/target
cd build/target
if [ ! -f Makefile ]; then
	printf "configure\tbinutils\n"
	run ../../configure --target=x86_64-linux-musl --prefix="$TOOLCHAIN" --with-sysroot="$FS" --disable-nls --disable-werror
fi
printf "build\t\tbinutils\n"
run make -j$THREADS
printf "install\t\tbinutils\n"
run make install
cd ../../..

if [ ! -d gcc ]; then
	printf "download\tgcc\n"
	run wget \
		-O gcc.tar.gz \
		https://ftp.gnu.org/gnu/gcc/gcc-13.2.0/gcc-$GCC_VERSION.tar.gz
	run tar -xf gcc.tar.gz
	rm gcc.tar.gz
	run mv gcc-$GCC_VERSION gcc
fi
cd gcc
mkdir -p build/target
cd build/target
if [ ! -f Makefile ]; then
	printf "configure\t\tgcc\n"
	run ../../configure --target=x86_64-linux-musl --prefix="$TOOLCHAIN" --with-sysroot="$FS" --disable-nls --enable-languages=c,c++ --disable-multilib --without-headers
fi
printf "build\t\tgcc\n"
run make all-gcc -j$THREADS
run make all-target-libgcc -j$THREADS
printf "install\t\tgcc\n"
run make install-gcc
run make install-target-libgcc
cd ../../..
export CC=x86_64-linux-musl-gcc

if [ ! -d linux ]; then
	readonly LINUX_MAJOR=${LINUX_VERSION%%.*}
	printf "download\tlinux\n"
	run wget \
		-O linux.tar.xz \
		https://cdn.kernel.org/pub/linux/kernel/v$LINUX_MAJOR.x/linux-$LINUX_VERSION.tar.xz
	run tar xf linux.tar.xz
	rm linux.tar.xz
	run mv linux-$LINUX_VERSION "linux"
fi
cd linux
printf "configure\tlinux\n"
cp -a ../../linux/. .
printf "build\t\tlinux\n"
run make bzImage -j $THREADS
printf "install\t\tlinux\n"
run make headers_install \
	ARCH=x86_64 \
	INSTALL_HDR_PATH="$TOOLCHAIN"
cd ..
cp -f linux/arch/x86/boot/bzImage boot/boot/vmlinuz

if [ ! -d sinit ]; then
	printf "download\tsinit\n"
	run git clone git://git.suckless.org/sinit
fi
cd sinit
if [ ! -f config.h ]; then
	printf "configure\tsinit\n"
	run cp ../../sinit/config.h .
fi
printf "build\t\tsinit\n"
run make -j$THREADS CC=x86_64-linux-musl-gcc
printf "install\t\tsinit\n"
run make DESTDIR=../fs PREFIX=/usr install
cd ..

if [ ! -d oksh ]; then
	printf "download\toksh\n"
	run wget \
		-O oksh.tar.gz \
		https://github.com/ibara/oksh/releases/download/oksh-$OKSH_VERSION/oksh-$OKSH_VERSION.tar.gz
	run tar xf oksh.tar.gz
	rm oksh.tar.gz
	run mv oksh-$OKSH_VERSION oksh
fi
cd oksh
if [ ! -f Makefile ]; then
	printf "configure\toksh\n"
	export CFLAGS="-std=c99 -Os -pipe -Wall -Wextra -fno-pie -fno-PIE"
	export LDFLAGS="-static -no-pie -s"
	run ./configure --no-thanks
fi
printf "build\t\toksh\n"
run make -j$THREADS CC=x86_64-linux-musl-gcc
cd ..
printf "install\t\toksh\n"
run cp oksh/oksh fs/bin/
ln -sf oksh fs/bin/sh

if [ ! -d toybox ]; then
	printf "install\ttoybox\n"
	run wget \
		-O toybox.tar.gz \
		https://landley.net/toybox/downloads/toybox-$TOYBOX_VERSION.tar.gz
	run tar -xf toybox.tar.gz
	rm toybox.tar.gz
	run mv toybox-$TOYBOX_VERSION toybox
fi
cd toybox
if [ ! -f .config ]; then
	printf "configure\ttoybox\n"
	run cp ../../toybox/.config .
fi
printf "build\t\ttoybox\n"
export CFLAGS="-Os -U_FORTIFY_SOURCE -I$TOOLCHAIN/include"
export PREFIX=../fs/bin
run make -j$THREADS
printf "install\t\ttoybox\n"
run make install_flat
cd ..

cd fs
find | cpio -o -H newc > ../boot/boot/init.cpio
cd ..
run grub-mkrescue -o microbuntu.iso boot

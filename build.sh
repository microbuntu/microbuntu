#!/bin/sh
set -xe

mkdir -p build/fs
cd build/fs

mkdir -p bin lib usr dev proc sys tmp run etc mnt root opt

ln -sf bin sbin
ln -sf ../bin usr/bin
ln -sf ../bin usr/sbin

ln -sf lib lib32
ln -sf lib lib64
ln -sf ../lib usr/lib
ln -sf ../lib usr/lib32
ln -sf ../lib usr/lib64

cp -a ../../fs/. .

cd ../../

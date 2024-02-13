#!/bin/bash

if [ $# -ne 1 ] || [ $1 == "-h" -o $1 == "--help" ]; then
  echo "Usage: $0 DSTDIR"
  exit 1
fi

mkdir -p $1
if [ ! -d $1 ]; then
  echo "Could not find or create the destination directory"
  exit 1
fi

DSTDIR=$(cd $1 && pwd)
mkdir -p $DSTDIR/bin

cd /tmp
mkdir $$
cd $$
git clone https://github.com/bochs-emu/Bochs bochs
cd bochs/bochs

os="`uname`"
if [ $os == "Darwin" ]; then
  if [ ! -d /opt/X11 ]; then
    echo "Error: X11 directory does not exist. Have you installed XQuartz https://www.xquartz.org?"
    exit 1
  fi
  # Bochs will have trouble finding X11 header files and library
  # We need to set the pkg config path explicitly.
  export PKG_CONFIG_PATH=/opt/X11/lib/pkgconfig
fi

WD=$(pwd)

CFGOPTS="--with-x --with-x11 --with-term --with-nogui --prefix=$DSTDIR"

mkdir plain && cd plain
../configure $CFGOPTS --enable-gdb-stub && make -j8
if [ $? -ne 0 ]; then
  echo "Error: build bochs failed"
  exit 1
fi
echo "Bochs plain successfully built"
make install

cd $WD

mkdir with-dbg && cd with-dbg
../configure --enable-debugger --disable-debugger-gui $CFGOPTS && make -j8
if [ $? -ne 0 ]; then
  echo "Error: build bochs-dbg failed"
  exit 1
fi

cp bochs $DSTDIR/bin/bochs-dbg
rm -rf /tmp/$$

echo "Done. bochs and bochs-dbg has been built and copied to $DSTDIR/bin"

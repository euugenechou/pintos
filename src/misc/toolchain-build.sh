#!/bin/bash

######################################################
#
# Setup OS lab tool chain (i386-elf-* cross compiler).
#
# Tested on Mac OS, Ubuntu and Fedora.
#
# Authors: Ryan Huang <huang@cs.jhu.edu>
#          Eugene Chou <euchou@ucsc.edu> (added version bump)
#
# Example Usage: ./toolchain-build.sh /home/ryan/318/toolchain
#

perror() {
  >&2 echo $1
  exit 1
}

download_and_check()
{
  local src=$(basename $1)
  local sig=$(basename $2)
  local dir="${src%.tar.*}"
  local keyring=$3

  cd $CWD/src

  # Download the source.
  if [[ ! -f $src ]]; then
    wget $1
    if [[ ! -f $src ]]; then
      perror "Failed to download $1 (source)"
    fi
  fi

  # Download the signature.
  if [[ ! -f $sig ]]; then
    wget $2
    if [[ ! -f $sig ]]; then
      perror "Failed to download $1 (signature)"
    fi
  fi

  # Verify the signature.
  if ! gpgv --keyring $keyring $sig $src; then
    perror "Failed to verify $1"
  fi

  echo "Downloaded and verified $src from $1"
  if [ ! -d $dir ]; then
    echo "Extracting $src to $fdirname..."
    if [ $src == *.tar.gz ]; then
      tar xzf $src
    elif [ $src == *.tar.bz2 ]; then
      tar xjf $src
    elif [ $src == *.tar.xz ]; then
      tar xJf $src
    else
      perror "Unrecognized archive extension $src"
    fi
  else
    echo "$src is already extracted"
  fi
}

usage()
{
  cat <<EOF

  Usage: $0 [options] [DEST_DIR] [TOOL]

    -h, --help           Display this message

    -p, --prefix PATH    Install the executables to PATH, instead of the default
                         DEST_DIR/dist

    DEST_DIR             Base directory to store the downloeaded source code,
                         build and distribute the compiled toolchain.

    TOOL                 By default, this script build three targets: binutils,
                         GCC, and GDB. Specify a single target to download and build.
                         Must be one of {binutils, gcc, gdb}.

  Example:
    1. $0 /home/ryan/318/toolchain
    2. $0 /home/ryan/318/toolchain gcc
    3. $0 --prefix /usr/local /home/ryan/318/toolchain gdb

EOF
}

if [ $# -eq 0 ]; then
  >&2 usage
  exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PREFIX=
ARGS=""
while (( "$#" )); do
  case "$1" in
    -p|--prefix)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        PREFIX=$2
        shift 2
      else
        echo "Error: Prefix argument is missing" >&2
        exit 1
      fi
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*|--*=)
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *)
      ARGS="$ARGS $1"
      shift
      ;;
  esac
done
eval set -- "$ARGS"
tool=all
if [ $# -eq 2 ]; then
  tool=$(echo "$2" | tr '[:upper:]' '[:lower:]')
  if [ $tool != "binutils" -a $tool != "gcc" -a $tool != "gdb" ]; then
    perror "TOOL must be one of {binutils,gcc,gdb}"
  fi
fi

os="`uname`"
dist="`uname -m`"

mkdir -p $1/{src,$dist,build} || perror "Failed to create toolchain source and build directories"

CWD=$(cd $1 && pwd)
if [ -z "$PREFIX" ]; then
  # if prefix is not set, we use the dist dir as the default prefix
  PREFIX=$CWD/$dist
else
  if [[ $PREFIX != /* ]]; then
    echo "Prefix must be an absolute path, got '$PREFIX'"
    exit 1
  fi
fi

export PATH=$PREFIX/bin:$PATH
if [ $os == "Linux" ]; then
  export LD_LIBRARY_PATH=$PREFIX/lib:$LD_LIBRARY_PATH
elif [ $os == "Darwin" ]; then
  export DYLD_LIBRARY_PATH=$PREFIX/lib:$DYLD_LIBRARY_PATH
else
  perror "Unsupported OS: $os"
fi

TARGET=i386-elf

# Latest as of 2024-02-13
BINUTILS_VER="binutils-2.42"
BINUTILS_SRC="https://ftp.gnu.org/gnu/binutils/$BINUTILS_VER.tar.gz"
BINUTILS_SIG="https://ftp.gnu.org/gnu/binutils/$BINUTILS_VER.tar.gz.sig"

# Latest as of 2024-02-13
GCC_VER="gcc-13.2.0"
GCC_SRC="https://ftp.gnu.org/gnu/gcc/$GCC_VER/$GCC_VER.tar.gz"
GCC_SIG="https://ftp.gnu.org/gnu/gcc/$GCC_VER/$GCC_VER.tar.gz.sig"

# Latest as of 2024-02-13
GDB_VER="gdb-14.1"
GDB_SRC="https://ftp.gnu.org/gnu/gdb/$GDB_VER.tar.gz"
GDB_SIG="https://ftp.gnu.org/gnu/gdb/$GDB_VER.tar.gz.sig"

# Download GPG keyring
if [[ ! -f $CWD/gnu-keyring.gpg ]]; then
  wget https://ftp.gnu.org/gnu/gnu-keyring.gpg
  mv gnu-keyring.gpg $CWD/.
fi

# Download sources
if [ $tool == "all" -o $tool == "binutils" ]; then
  download_and_check $BINUTILS_SRC $BINUTILS_SIG $CWD/gnu-keyring.gpg
fi
if [ $tool == "all" -o $tool == "gcc" ]; then
  download_and_check $GCC_SRC $GCC_SIG $CWD/gnu-keyring.gpg
fi
if [ $tool == "all" -o $tool == "gdb" ]; then
  download_and_check $GDB_SRC $GDB_SIG $CWD/gnu-keyring.gpg
fi

if [ $tool == "all" -o $tool == "binutils" ]; then
  echo "Building binutils..."
  mkdir -p $CWD/build/binutils && cd $CWD/build/binutils
  ../../src/$BINUTILS_VER/configure --prefix=$PREFIX --target=$TARGET \
    --disable-multilib --disable-nls --disable-werror || perror "Failed to configure binutils"
  make -j8 || perror "Failed to make binutils"
  make install
fi

if [ $tool == "all" -o $tool == "gcc" ]; then
  echo "Building GCC..."
  mkdir -p $CWD/build/gcc && cd $CWD/build/gcc
  ../../src/$GCC_VER/configure CXXFLAGS="-fpermissive" --prefix=$PREFIX --target=$TARGET \
    --disable-multilib --disable-nls --disable-werror --disable-libssp \
    --disable-libmudflap --with-newlib --without-headers --enable-languages=c,c++ || perror "Failed to configure gcc"
  make -j8 all-gcc  || perror "Failed to make gcc"
  make install-gcc
  make all-target-libgcc || perror "Failed to libgcc"
  make install-target-libgcc
fi

if [ $tool == "all" -o $tool == "gdb" ]; then
  echo "Building gdb..."
  mkdir -p $CWD/build/gdb && cd $CWD/build/gdb
  ../../src/$GDB_VER/configure --prefix=$PREFIX --target=$TARGET --disable-werror || perror "Failed to configure gdb"
  make -j8 || perror "Failed to make gdb"
  make install
fi

# Remove the keyring.
rm -f gnu-keyring.gpg

echo "************************************************************"
echo "*                                                          *"
echo "* Congratulations! You've built the cross-compiler!        *"
echo "* Don't forget to add the following to .bashrc or .zshrc:  *"
echo "* export PATH=$PREFIX/bin:\$PATH                           *"
echo "*                                                          *"
echo "************************************************************"

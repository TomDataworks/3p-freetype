#!/bin/bash

cd "$(dirname "$0")"

# Load autobuild provided shell functions and variables
set +x
eval "$("$AUTOBUILD" source_environment)"
set -x

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

FREETYPE_VERSION="2.4.4"
FREETYPELIB_SOURCE_DIR="freetype-$FREETYPE_VERSION"
FREETYPE_ARCHIVE="$FREETYPELIB_SOURCE_DIR.tar.bz2"
FREETYPE_URL="http://download.savannah.gnu.org/releases/freetype/$FREETYPE_ARCHIVE"
FREETYPE_MD5="b3e2b6e2f1c3e0dffa1fd2a0f848b671"

# Fetch and extract the official freetype release source code
#
fetch_archive "$FREETYPE_URL" "$FREETYPE_ARCHIVE" "$FREETYPE_MD5"
extract "$FREETYPE_ARCHIVE"

if [ -z "$AUTOBUILD" ] ; then 
    fail
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="$(cygpath -u $AUTOBUILD)"
fi

# load autbuild provided shell functions and variables
set +x
eval "$("$AUTOBUILD" source_environment)"
set -x

stage="$(pwd)/stage"
pushd "$FREETYPELIB_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        "windows")
            load_vsvars
            
            build_sln "builds/win32/vc2010/freetype.sln" "LIB Debug|Win32" 
            build_sln "builds/win32/vc2010/freetype.sln" "LIB Release|Win32" 

            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"
            cp "objs/win32/vc2010/freetype239_D.lib" "$stage/lib/debug/freetype.lib"
            cp "objs/win32/vc2010/freetype239.lib" "$stage/lib/release/freetype.lib"
                
            mkdir -p "$stage/include/freetype"
            cp -r include/ft2build.h "$stage/include/ft2build.h"
            cp -r include/freetype/* "$stage/include/freetype/"            
        ;;
        "darwin")
            CPPFLAGS="-arch i386 -iwithsysroot /Developer/SDKs/MacOSX10.8.sdk" ./configure --prefix="$stage"
            make
            make install
            mv "$stage/include/freetype2/freetype" "$stage/include/freetype"
            mv "$stage/lib" "$stage/release"
            mkdir -p "$stage/lib"
            mv "$stage/release" "$stage/lib"
        ;;
        "linux")
            LDFLAGS="-m32" CFLAGS="-m32" CXXFLAGS="-m32" ./configure --prefix="$stage"
            make
            make install
            mv "$stage/include/freetype2/freetype" "$stage/include/freetype"
            mv "$stage/lib" "$stage/release"
            mkdir -p "$stage/lib"
            mv "$stage/release" "$stage/lib"
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp docs/LICENSE.TXT "$stage/LICENSES/freetype.txt"
popd

pass


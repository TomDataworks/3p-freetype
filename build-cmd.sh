#!/bin/bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

FREETYPE_VERSION="2.3.9"
FREETYPELIB_SOURCE_DIR="freetype-$FREETYPE_VERSION"

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
            cp "objs/win32/vc2010/freetype244_D.lib" "$stage/lib/debug/freetype.lib"
            cp "objs/win32/vc2010/freetype244.lib" "$stage/lib/release/freetype.lib"
                
            mkdir -p "$stage/include/freetype"
            cp -r include/ft2build.h "$stage/include/ft2build.h"
            cp -r include/freetype/* "$stage/include/freetype/"            
        ;;
        "darwin")
            ./configure --prefix="$stage"
            make
            make install
            mv "$stage/include/freetype2/freetype" "$stage/include/freetype"
            mv "$stage/lib" "$stage/release"
            mkdir -p "$stage/lib"
            mv "$stage/release" "$stage/lib"
        ;;
        "linux")
            CFLAGS="-m32" CXXFLAGS="-m32" ./configure --prefix="$stage"
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


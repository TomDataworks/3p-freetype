#!/bin/bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

FREETYPELIB_SOURCE_DIR="freetype"
FREETYPE_VERSION="2.6.3"

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

top="$(pwd)"
stage="$(pwd)/stage"

[ -f "$stage"/packages/include/zlib/zlib.h ] || fail "You haven't installed packages yet."

echo "${FREETYPE_VERSION}" > "${stage}/VERSION.txt"

pushd "$FREETYPELIB_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        "windows")
            load_vsvars
            
            build_sln "builds/windows/vc2015/freetype.sln" "Debug" "Win32" 
            build_sln "builds/windows/vc2015/freetype.sln" "Release" "Win32" 

            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"
            cp -a "objs/vc2015/win32/freetype263d.lib" "$stage/lib/debug/freetype.lib"
            cp -a "objs/vc2015/win32/freetype263.lib" "$stage/lib/release/freetype.lib"
                
            mkdir -p "$stage/include/freetype2/"
            cp -a include/ft2build.h "$stage/include/freetype2/"
            cp -a include/freetype "$stage/include/freetype2/"
        ;;

        "windows64")
            load_vsvars
            
            build_sln "builds/windows/vc2015/freetype.sln" "Debug" "x64" 
            build_sln "builds/windows/vc2015/freetype.sln" "Release" "x64" 

            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"
            cp -a "objs/vc2015/x64/freetype263d.lib" "$stage/lib/debug/freetype.lib"
            cp -a "objs/vc2015/x64/freetype263.lib" "$stage/lib/release/freetype.lib"
                
            mkdir -p "$stage/include/freetype2/"
            cp -a include/ft2build.h "$stage/include/freetype2/"
            cp -a include/freetype "$stage/include/freetype2/"
        ;;

        "darwin")
            # Darwin build environment at Linden is also pre-polluted like Linux
            # and that affects colladadom builds.  Here are some of the env vars
            # to look out for:
            #
            # AUTOBUILD             GROUPS              LD_LIBRARY_PATH         SIGN
            # arch                  branch              build_*                 changeset
            # helper                here                prefix                  release
            # repo                  root                run_tests               suffix

            # Select SDK with full path.  This shouldn't have much effect on this
            # build but adding to establish a consistent pattern.
            #
            # sdk=/Developer/SDKs/MacOSX10.6.sdk/
            # sdk=/Developer/SDKs/MacOSX10.7.sdk/
            # sdk=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.6.sdk/
            sdk=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.11.sdk/
            
            opts="${TARGET_OPTS:--arch x86_64 -iwithsysroot $sdk -mmacosx-version-min=10.8}"

            # Debug first
            CFLAGS="$opts -gdwarf-2 -O0" \
                CXXFLAGS="$opts -gdwarf-2 -O0" \
                CPPFLAGS="-I$stage/packages/include/zlib -I/$stage/packages/include/bzip2 -I$stage/packages/include/libpng16" \
                LDFLAGS="$opts -Wl,-headerpad_max_install_names -L$stage/packages/lib/debug -Wl,-unexported_symbols_list,$stage/packages/lib/debug/libz_darwin.exp" \
				ZLIB_CFLAGS="" LIBPNG_CFLAGS="" \
                ZLIB_LIBS="${stage}/packages/lib/debug/libz.a" LIBPNG_LIBS="${stage}/packages/lib/debug/libpng.a" \
				./configure --with-pic \
				--with-png --with-zlib --without-harfbuzz \
               --enable-shared=yes --enable-static=no --prefix="$stage" --libdir="$stage/lib/debug"
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                # make test
                echo "No tests"
            fi

            install_name_tool -id "@executable_path/../Resources/libfreetype.6.dylib" "$stage"/lib/debug/libfreetype.6.dylib

            make distclean

            # Release last
            CFLAGS="$opts -gdwarf-2 -Os" \
                CXX_FLAGS="$opts -gdwarf-2 -Os" \
                CPPFLAGS="-I$stage/packages/include/zlib -I/$stage/packages/include/bzip2 -I$stage/packages/include/libpng16" \
                LDFLAGS="$opts -Wl,-headerpad_max_install_names -L$stage/packages/lib/debug -Wl,-unexported_symbols_list,$stage/packages/lib/debug/libz_darwin.exp" \
                ZLIB_LIBS="${stage}/packages/lib/release/libz.a" LIBPNG_LIBS="${stage}/packages/lib/release/libpng.a" BZIP2_LIBS="${stage}/packages/lib/libbz2.a" \
				ZLIB_CFLAGS="" BZIP2_CFLAGS="" LIBPNG_CFLAGS="" \
				./configure --with-pic \
				--with-png --with-zlib --with-bzip2 --without-harfbuzz \
               --enable-shared=yes --enable-static=no --prefix="$stage" --libdir="$stage/lib/release"
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                # make test
                echo "No tests"
            fi

            install_name_tool -id "@executable_path/../Resources/libfreetype.6.dylib" "$stage"/lib/release/libfreetype.6.dylib

            make distclean
        ;;

        "linux")
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

            # Prefer gcc-4.8 if available.
            if [ -x /usr/bin/gcc-4.8 -a -x /usr/bin/g++-4.8 ]; then
                export CC=/usr/bin/gcc-4.8
                export CXX=/usr/bin/g++-4.8s
            fi

            # Default target to 32-bit
            opts="${TARGET_OPTS:--m32}"
            JOBS=`cat /proc/cpuinfo | grep processor | wc -l`
            HARDENED="-fstack-protector -D_FORTIFY_SOURCE=2"

            # Handle any deliberate platform targeting
            if [ -z "$TARGET_CPPFLAGS" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS" 
            fi

            fix_pkgconfig_prefix "$stage/packages"

            # Debug first
            CFLAGS="$opts -Og -g" \
                CXXFLAGS="$opts -Og -g" \
                LDFLAGS="$opts -Wl,--exclude-libs,libz" \
                PKG_CONFIG_LIBDIR="$stage/packages/lib/debug/pkgconfig"\
                ./configure --with-pic --without-png --with-zlib \
                --prefix="${stage}" --libdir="${stage}/lib/debug" --includedir="${stage}/include"
            make -j$JOBS
            make install

            cp ../extras/freetype2-debug.pc ${stage}/lib/debug/pkgconfig/freetype2.pc

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                # make test
                echo "No tests"
            fi

            make distclean

            # Release last
            CFLAGS="$opts -O2 -g $HARDENED" \
                CXXFLAGS="$opts -O2 -g $HARDENED" \
                LDFLAGS="$opts -Wl,--exclude-libs,libz" \
                PKG_CONFIG_LIBDIR="$stage/packages/lib/release/pkgconfig"\
                ./configure --with-pic --without-png --with-zlib \
                --prefix="${stage}" --libdir="${stage}/lib/release" --includedir="${stage}/include"
            make -j$JOBS
            make install

            cp ../extras/freetype2.pc ${stage}/lib/release/pkgconfig/freetype2.pc

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                # make test
                echo "No tests"
            fi

            make distclean
        ;;

        "linux64")
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

            # Prefer gcc-4.8 if available.
            if [ -x /usr/bin/gcc-4.8 -a -x /usr/bin/g++-4.8 ]; then
                export CC=/usr/bin/gcc-4.8
                export CXX=/usr/bin/g++-4.8s
            fi

            # Default target to 64-bit
            opts="${TARGET_OPTS:--m64}"
            JOBS=`cat /proc/cpuinfo | grep processor | wc -l`
            HARDENED="-fstack-protector -D_FORTIFY_SOURCE=2"

            # Handle any deliberate platform targeting
            if [ -z "$TARGET_CPPFLAGS" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS" 
            fi

            fix_pkgconfig_prefix "$stage/packages"

            # Debug first
            CFLAGS="$opts -Og -g" \
                CXXFLAGS="$opts -Og -g" \
                LDFLAGS="$opts -Wl,--exclude-libs,libz" \
                PKG_CONFIG_LIBDIR="$stage/packages/lib/debug/pkgconfig"\
                ./configure --with-pic --without-png --with-zlib \
                --prefix="${stage}" --libdir="${stage}/lib/debug" --includedir="${stage}/include"
            make -j$JOBS
            make install

            cp ../extras/freetype2-debug.pc ${stage}/lib/debug/pkgconfig/freetype2.pc

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                # make test
                echo "No tests"
            fi

            make distclean

            # Release last
            CFLAGS="$opts -O2 -g $HARDENED" \
                CXXFLAGS="$opts -O2 -g $HARDENED" \
                LDFLAGS="$opts -Wl,--exclude-libs,libz" \
                PKG_CONFIG_LIBDIR="$stage/packages/lib/release/pkgconfig"\
                ./configure --with-pic --without-png --with-zlib \
                --prefix="${stage}" --libdir="${stage}/lib/release" --includedir="${stage}/include"
            make -j$JOBS
            make install

            cp ../extras/freetype2.pc ${stage}/lib/release/pkgconfig/freetype2.pc

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                # make test
                echo "No tests"
            fi

            make distclean
        ;;

    esac
    mkdir -p "$stage/LICENSES"
    cp docs/LICENSE.TXT "$stage/LICENSES/freetype.txt"
popd

mkdir -p "$stage"/docs/freetype/
cp -a README.Linden "$stage"/docs/freetype/

pass


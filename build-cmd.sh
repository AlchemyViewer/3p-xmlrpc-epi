#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

XMLRPCEPI_SOURCE_DIR="xmlrpc-epi"
XMLRPCEPI_VERSION="$(sed -n 's/^ *VERSION=\([0-9.]*\)$/\1/p' "$XMLRPCEPI_SOURCE_DIR/configure")"

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

stage="$(pwd)/stage"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

copy_headers ()
{
    cp src/base64.h $1
    cp src/encodings.h $1
    cp src/queue.h $1
    cp src/simplestring.h $1
    cp src/xml_element.h $1
    cp src/xmlrpc.h $1
    cp src/xmlrpc_introspection.h $1
    cp src/xml_to_xmlrpc.h $1
}

echo "${XMLRPCEPI_VERSION}" > "${stage}/VERSION.txt"

pushd "$XMLRPCEPI_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            load_vsvars

            build_sln "xmlrpcepi.sln" "Debug" "$AUTOBUILD_WIN_VSPLATFORM" "xmlrpcepi"
            build_sln "xmlrpcepi.sln" "Release" "$AUTOBUILD_WIN_VSPLATFORM" "xmlrpcepi"
            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then 
                cp Debug/xmlrpc-epid.{lib,dll,exp,pdb} "$stage/lib/debug/"
                cp Release/xmlrpc-epi.{lib,dll,exp,pdb} "$stage/lib/release/"
            else 
                cp x64/Debug/xmlrpc-epid.{lib,dll,exp,pdb} "$stage/lib/debug/"
                cp x64/Release/xmlrpc-epi.{lib,dll,exp,pdb} "$stage/lib/release/"
            fi
     
            mkdir -p "$stage/include/xmlrpc-epi"
            copy_headers "$stage/include/xmlrpc-epi"
        ;;
        darwin*)
            # Setup osx sdk platform
            SDKNAME="macosx"
            export SDKROOT=$(xcodebuild -version -sdk ${SDKNAME} Path)
            export MACOSX_DEPLOYMENT_TARGET=10.13

            # Setup build flags
            ARCH_FLAGS="-arch x86_64"
            SDK_FLAGS="-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET} -isysroot ${SDKROOT}"
            DEBUG_COMMON_FLAGS="$ARCH_FLAGS $SDK_FLAGS -Og -g -msse4.2 -fPIC -DPIC"
            RELEASE_COMMON_FLAGS="$ARCH_FLAGS $SDK_FLAGS -Ofast -ffast-math -g -msse4.2 -fPIC -DPIC -fstack-protector-strong"
            DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
            RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
            RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
            RELEASE_CPPFLAGS="-DPIC"
            DEBUG_LDFLAGS="$ARCH_FLAGS $SDK_FLAGS -Wl,-headerpad_max_install_names -Wl,-macos_version_min,$MACOSX_DEPLOYMENT_TARGET"
            RELEASE_LDFLAGS="$ARCH_FLAGS $SDK_FLAGS -Wl,-headerpad_max_install_names -Wl,-macos_version_min,$MACOSX_DEPLOYMENT_TARGET"

            JOBS=`sysctl -n hw.ncpu`

            PREFIX_DEBUG="$stage/temp_debug"
            PREFIX_RELEASE="$stage/temp_release"

            mkdir -p $PREFIX_DEBUG
            mkdir -p $PREFIX_RELEASE

            autoreconf -fvi

            mkdir -p "build_debug"
            pushd "build_debug"
                CFLAGS="$DEBUG_CFLAGS" CXXFLAGS="$DEBUG_CXXFLAGS" LDFLAGS="$DEBUG_LDFLAGS" \
                    ../configure --enable-debug --prefix="$PREFIX_DEBUG" \
                        --with-expat="$SDKROOT/usr"
                make -j$JOBS
                make install
            popd

            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$RELEASE_CFLAGS" CXXFLAGS="$RELEASE_CXXFLAGS" LDFLAGS="$RELEASE_LDFLAGS" \
                    ../configure --prefix="$PREFIX_RELEASE" \
                        --with-expat="$SDKROOT/usr"
                make -j$JOBS
                make install
            popd

            pushd "$PREFIX_DEBUG/lib"
                fix_dylib_id "libxmlrpc-epi.dylib"
                dsymutil libxmlrpc-epi.*.dylib
                strip -x -S libxmlrpc-epi.*.dylib
            popd

            pushd "$PREFIX_RELEASE/lib"
                fix_dylib_id "libxmlrpc-epi.dylib"
                dsymutil libxmlrpc-epi.*.dylib
                strip -x -S libxmlrpc-epi.*.dylib
            popd

            mkdir -p "$stage/include/xmlrpc-epi"
            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"

            cp -a $PREFIX_DEBUG/lib/*.dylib* $stage/lib/debug
            cp -a $PREFIX_RELEASE/lib/*.dylib* $stage/lib/release

            cp -a $PREFIX_RELEASE/include/* $stage/include/xmlrpc-epi/
        ;;
        linux*)
            # Default target per --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE}"
            DEBUG_COMMON_FLAGS="$opts -Og -g -fPIC"
            RELEASE_COMMON_FLAGS="$opts -O3 -g -fPIC -fstack-protector-strong -DPIC -D_FORTIFY_SOURCE=2"
            DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
            RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
            RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
            RELEASE_CPPFLAGS="-DPIC -D_FORTIFY_SOURCE=2"
            DEBUG_LDFLAGS="$opts"
            RELEASE_LDFLAGS="$opts"

            JOBS=`cat /proc/cpuinfo | grep processor | wc -l`

            PREFIX_DEBUG="$stage/temp_debug"
            PREFIX_RELEASE="$stage/temp_release"

            mkdir -p $PREFIX_DEBUG
            mkdir -p $PREFIX_RELEASE

            autoreconf -fvi

            mkdir -p "build_debug"
            pushd "build_debug"
                CFLAGS="$DEBUG_CFLAGS -I$stage/packages/include/expat" CXXFLAGS="$DEBUG_CXXFLAGS" LDFLAGS="-L$stage/packages/lib/debug $DEBUG_LDFLAGS" LIBS="-lexpat" \
                    ../configure --prefix="$PREFIX_DEBUG" \
                        --with-expat=package \
                        --with-expat-lib="-L$stage/packages/lib/debug -lexpat" \
                        --with-expat-inc="$stage/packages/include/expat"
                make -j$JOBS
                make install
            popd

            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$RELEASE_CFLAGS -I$stage/packages/include/expat" CXXFLAGS="$RELEASE_CXXFLAGS" LDFLAGS="-L$stage/packages/lib/release $RELEASE_LDFLAGS" LIBS="-lexpat" \
                    ../configure --prefix="$PREFIX_RELEASE" \
                        --with-expat=package \
                        --with-expat-lib="-L$stage/packages/lib/release -lexpat" \
                        --with-expat-inc="$stage/packages/include/expat"
                make -j$JOBS
                make install
            popd

            mkdir -p "$stage/include/xmlrpc-epi"
            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"

            cp -a $PREFIX_DEBUG/lib/*.a $stage/lib/debug
            cp -a $PREFIX_RELEASE/lib/*.a $stage/lib/release

            cp -a $PREFIX_RELEASE/include/* $stage/include/xmlrpc-epi/
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp "COPYING" "$stage/LICENSES/xmlrpc-epi.txt"
popd

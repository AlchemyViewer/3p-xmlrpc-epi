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

            build_sln "xmlrpcepi.sln" "Debug|$AUTOBUILD_WIN_VSPLATFORM" "xmlrpcepi"
            build_sln "xmlrpcepi.sln" "Release|$AUTOBUILD_WIN_VSPLATFORM" "xmlrpcepi"
            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then 
                cp Debug/xmlrpc-epid.lib "$stage/lib/debug/"
                cp Release/xmlrpc-epi.lib "$stage/lib/release/"
            else 
                cp x64/Debug/xmlrpc-epid.lib "$stage/lib/debug/"
                cp x64/Release/xmlrpc-epi.lib "$stage/lib/release/"
            fi
     
            mkdir -p "$stage/include/xmlrpc-epi"
            copy_headers "$stage/include/xmlrpc-epi"
        ;;
        darwin*)
            # Setup osx sdk platform
            SDKNAME="macosx"
            export SDKROOT=$(xcodebuild -version -sdk ${SDKNAME} Path)

            # Deploy Targets
            X86_DEPLOY=10.15
            ARM64_DEPLOY=11.0

            # Setup build flags
            ARCH_FLAGS_X86="-arch x86_64 -mmacosx-version-min=${X86_DEPLOY} -isysroot ${SDKROOT} -msse4.2"
            ARCH_FLAGS_ARM64="-arch arm64 -mmacosx-version-min=${ARM64_DEPLOY} -isysroot ${SDKROOT}"
            DEBUG_COMMON_FLAGS="-O0 -g -fPIC -DPIC"
            RELEASE_COMMON_FLAGS="-O3 -g -fPIC -DPIC -fstack-protector-strong"
            DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
            RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
            RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
            RELEASE_CPPFLAGS="-DPIC"
            DEBUG_LDFLAGS="-Wl,-headerpad_max_install_names"
            RELEASE_LDFLAGS="-Wl,-headerpad_max_install_names"

            # Regen autoconf
            autoreconf -fvi

            # x86 Deploy Target
            export MACOSX_DEPLOYMENT_TARGET=${X86_DEPLOY}

            ARM_PREFIX_DEBUG="$stage/debug_arm64"
            ARM_PREFIX_RELEASE="$stage/release_arm64"
            X86_PREFIX_DEBUG="$stage/debug_x86"
            X86_PREFIX_RELEASE="$stage/release_x86"

            mkdir -p $ARM_PREFIX_DEBUG
            mkdir -p $ARM_PREFIX_RELEASE
            mkdir -p $X86_PREFIX_DEBUG
            mkdir -p $X86_PREFIX_RELEASE

            mkdir -p "build_debug_x86"
            pushd "build_debug_x86"
                CFLAGS="$ARCH_FLAGS_X86 $DEBUG_CFLAGS" \
                CXXFLAGS="$ARCH_FLAGS_X86 $DEBUG_CXXFLAGS" \
                LDFLAGS="$ARCH_FLAGS_X86 $DEBUG_LDFLAGS" \
                    ../configure --enable-debug --prefix="$X86_PREFIX_DEBUG" \
                        --host x86_64-apple-darwin \
                        --with-expat="$SDKROOT/usr"
                make -j$AUTOBUILD_CPU_COUNT
                make install
            popd

            mkdir -p "build_release_x86"
            pushd "build_release_x86"
                CFLAGS="$ARCH_FLAGS_X86 $RELEASE_CFLAGS" \
                CXXFLAGS="$ARCH_FLAGS_X86 $RELEASE_CXXFLAGS" \
                LDFLAGS="$ARCH_FLAGS_X86 $RELEASE_LDFLAGS" \
                    ../configure --prefix="$X86_PREFIX_RELEASE" \
                        --host x86_64-apple-darwin \
                        --with-expat="$SDKROOT/usr"
                make -j$AUTOBUILD_CPU_COUNT
                make install
            popd

            # ARM64 Deploy Target
            export MACOSX_DEPLOYMENT_TARGET=${ARM64_DEPLOY}

            mkdir -p "build_debug_arm64"
            pushd "build_debug_arm64"
                CFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CFLAGS" \
                CXXFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CXXFLAGS" \
                LDFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_LDFLAGS" \
                    ../configure --enable-debug --prefix="$ARM_PREFIX_DEBUG" \
                        --host arm64-apple-darwin \
                        --with-expat="$SDKROOT/usr"
                make -j$AUTOBUILD_CPU_COUNT
                make install
            popd

            mkdir -p "build_release_arm64"
            pushd "build_release_arm64"
                CFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CFLAGS" \
                CXXFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CXXFLAGS" \
                LDFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_LDFLAGS" \
                    ../configure --prefix="$ARM_PREFIX_RELEASE" \
                        --host arm64-apple-darwin \
                        --with-expat="$SDKROOT/usr"
                make -j$AUTOBUILD_CPU_COUNT
                make install
            popd

            mkdir -p "$stage/include/xmlrpc-epi"
            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"

            # create fat libs
            lipo -create ${stage}/debug_x86/lib/libxmlrpc-epi.a ${stage}/debug_arm64/lib/libxmlrpc-epi.a -output ${stage}/lib/debug/libxmlrpc-epi.a
            lipo -create ${stage}/release_x86/lib/libxmlrpc-epi.a ${stage}/release_arm64/lib/libxmlrpc-epi.a -output ${stage}/lib/release/libxmlrpc-epi.a

            # copy includes
            cp -a $X86_PREFIX_RELEASE/include/* $stage/include/xmlrpc-epi/
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
                make -j$AUTOBUILD_CPU_COUNT
                make install
            popd

            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$RELEASE_CFLAGS -I$stage/packages/include/expat" CXXFLAGS="$RELEASE_CXXFLAGS" LDFLAGS="-L$stage/packages/lib/release $RELEASE_LDFLAGS" LIBS="-lexpat" \
                    ../configure --prefix="$PREFIX_RELEASE" \
                        --with-expat=package \
                        --with-expat-lib="-L$stage/packages/lib/release -lexpat" \
                        --with-expat-inc="$stage/packages/include/expat"
                make -j$AUTOBUILD_CPU_COUNT
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

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

            msbuild.exe $(cygpath -w 'xmlrpcepi.sln') /p:Configuration=Debug /p:Platform=$AUTOBUILD_WIN_VSPLATFORM
            msbuild.exe $(cygpath -w 'xmlrpcepi.sln') /p:Configuration=Release /p:Platform=$AUTOBUILD_WIN_VSPLATFORM
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
            # Setup build flags
            C_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_CFLAGS"
            C_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_CFLAGS"
            CXX_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_CXXFLAGS"
            CXX_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_CXXFLAGS"
            LINK_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_LINKER"
            LINK_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_LINKER"

            # deploy target
            export MACOSX_DEPLOYMENT_TARGET=${LL_BUILD_DARWIN_BASE_DEPLOY_TARGET}

            # Regen autoconf
            autoreconf -fvi

            ARM_PREFIX_RELEASE="$stage/release_arm64"
            X86_PREFIX_RELEASE="$stage/release_x86"

            mkdir -p $ARM_PREFIX_RELEASE
            mkdir -p $X86_PREFIX_RELEASE

            mkdir -p "build_release_x86"
            pushd "build_release_x86"
                cp -a $stage/packages/lib/release/*.a $stage/packages/lib

                CFLAGS="$C_OPTS_X86" \
                CXXFLAGS="$CXX_OPTS_X86" \
                LDFLAGS="$LINK_OPTS_X86" \
                    ../configure --prefix="$X86_PREFIX_RELEASE" \
                        --host x86_64-apple-darwin \
                        --with-expat="$stage/packages"
                make -j$AUTOBUILD_CPU_COUNT
                make install

                rm $stage/packages/lib/*.a
            popd

            mkdir -p "build_release_arm64"
            pushd "build_release_arm64"
                cp -a $stage/packages/lib/release/*.a $stage/packages/lib

                CFLAGS="$C_OPTS_ARM64" \
                CXXFLAGS="$CXX_OPTS_ARM64" \
                LDFLAGS="$LINK_OPTS_ARM64" \
                    ../configure --prefix="$ARM_PREFIX_RELEASE" \
                        --host arm64-apple-darwin \
                        --with-expat="$stage/packages"
                make -j$AUTOBUILD_CPU_COUNT
                make install

                rm $stage/packages/lib/*.a
            popd

            mkdir -p "$stage/include/xmlrpc-epi"
            mkdir -p "$stage/lib/release"

            # create fat libs
            lipo -create ${stage}/release_x86/lib/libxmlrpc-epi.a ${stage}/release_arm64/lib/libxmlrpc-epi.a -output ${stage}/lib/release/libxmlrpc-epi.a

            # copy includes
            cp -a $X86_PREFIX_RELEASE/include/* $stage/include/xmlrpc-epi/
        ;;
        linux*)
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
            unset DISTCC_HOSTS CFLAGS CPPFLAGS CXXFLAGS

            # Default target per --address-size
            opts_c="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE_CFLAGS}"
            opts_cxx="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE_CXXFLAGS}"


            PREFIX_RELEASE="$stage/temp_release"

            mkdir -p $PREFIX_RELEASE

            autoreconf -fvi

            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$opts_c -I$stage/packages/include/expat" CXXFLAGS="$opts_cxx" LDFLAGS="-L$stage/packages/lib/release" LIBS="-lexpat" \
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

            cp -a $PREFIX_RELEASE/lib/*.a $stage/lib/release

            cp -a $PREFIX_RELEASE/include/* $stage/include/xmlrpc-epi/
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp "COPYING" "$stage/LICENSES/xmlrpc-epi.txt"
popd

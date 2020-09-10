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

build=${AUTOBUILD_BUILD_ID:=0}
echo "${XMLRPCEPI_VERSION}.${build}" > "${stage}/VERSION.txt"

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
                cp Debug/xmlrpcepi.{lib,dll,exp,pdb} "$stage/lib/debug/"
                cp Release/xmlrpcepi.{lib,dll,exp,pdb} "$stage/lib/release/"
            else 
                cp x64/Debug/xmlrpcepi.{lib,dll,exp,pdb} "$stage/lib/debug/"
                cp x64/Release/xmlrpcepi.{lib,dll,exp,pdb} "$stage/lib/release/"
            fi

            
            mkdir -p "$stage/include/xmlrpc-epi"
            copy_headers "$stage/include/xmlrpc-epi"
        ;;
        darwin*)
            opts="-arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD_RELEASE"
            CFLAGS="$opts" CXXFLAGS="$opts" LDFLAGS="$opts" ./configure --prefix="$stage" \
                --with-expat=no \
                --with-expat-lib="$stage/packages/lib/release/libexpat.dylib" \
                --with-expat-inc="$stage/packages/include/expat"
            make
            make install
            mkdir -p "$stage/include/xmlrpc-epi"
            mv "$stage/include/"*.h "$stage/include/xmlrpc-epi/"
            mkdir -p "$stage/lib/release"
            mv "$stage/lib/"*.a "$stage/lib/release"
            mv "$stage/lib/"*.dylib "$stage/lib/release"
            rm "$stage/lib/"*.la
            # The expat build manages to get these paths right automatically,
            # but this one doesn't; whatever, just update the paths here:
            install_name_tool -id "@executable_path/../Resources/libxmlrpc-epi.0.dylib" "$stage/lib/release/libxmlrpc-epi.0.dylib"
            install_name_tool -change "/usr/lib/libexpat.1.dylib" "@executable_path/../Resources/libexpat.1.dylib" "$stage/lib/release/libxmlrpc-epi.0.dylib"
        ;;
        linux*)
            opts="-m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE"
            CFLAGS="$opts" CXXFLAGS="$opts" ./configure --prefix="$stage" \
                --with-expat=no \
                --with-expat-lib="$stage/packages/lib/release/libexpat.so" \
                --with-expat-inc="$stage/packages/include/expat"
            make
            make install
            mkdir -p "$stage/include/xmlrpc-epi"
            mv "$stage/include/"*.h "$stage/include/xmlrpc-epi/"

            mv "$stage/lib" "$stage/release"
            mkdir -p "$stage/lib"
            mv "$stage/release" "$stage/lib"
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp "COPYING" "$stage/LICENSES/xmlrpc-epi.txt"
popd

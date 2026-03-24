#!/bin/bash

# Compile script for Aqua kernel

# Remove out directory
rm -rf out/arch/arm64/boot

# Prebuild hacks
rm -rf .config .config.old .tmp_versions
rm -rf include/generated include/config
rm -rf arch/arm64/include/generated
rm -rf vmlinux* System.map modules.builtin*
rm -f Module.symvers modules.order
rm -rf scripts/kconfig/.tmp*

# Date/Time
SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')

# Toolchain
TC_DIR="$HOME/toolchains/neutron-clang"
CURRENT_DIR=$(pwd)

# Device Configs
DEVICE="everpal"
DEFCONFIG="${DEVICE}_defconfig"
ZIPNAME="AquaKernel-${DATE}.zip"

# Ensure the toolchain is available
if [ ! -d "$TC_DIR" ]; then
    mkdir -p "$TC_DIR" && cd "$TC_DIR" || exit
    bash <(curl -s "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman") -S=05012024
    bash <(curl -s "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman") --patch=glibc
    cd "$CURRENT_DIR" || exit
fi

export PATH="$TC_DIR/bin:$PATH"
export CC=clang
export LD=ld.lld

echo 
echo "Using compiler:"
clang --version
echo 

# Process options
CLEAN_BUILD=false
INCLUDE_KSU=false

for arg in "$@"; do
    case $arg in
        --clean)
            CLEAN_BUILD=true
            ;;
        --with-ksu)
            INCLUDE_KSU=true
            ;;
        --redo-ksu)
            rm -f .ksu_applied
            INCLUDE_KSU=true
            ;; 
    esac
done

# Perform clean build if specified
[ "$CLEAN_BUILD" = true ] && rm -rf out

[ -f .ksu_applied ] && echo "Including KernelSU Next!"

# Include KernelSU if specified
if [[ "$INCLUDE_KSU" = true && ! -f .ksu_applied ]]; then
    echo "Including KernelSU Next!"
    git clone https://github.com/Addster09/EverpalPatches --depth=1
    for patch in EverpalPatches/KSUPatches/000*.patch; do
        patch -p1 < "$patch"
    done
    rm -rf EverpalPatches
    curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s legacy_susfs
    touch .ksu_applied
fi

# Compilation process
mkdir -p out
make O=out ARCH=arm64 "$DEFCONFIG"

echo -e "\nStarting compilation...\n"

if \
	make -j$(nproc --all) O=out \
	ARCH=arm64 \
	CC="ccache clang" \
	LLVM=1 \
	LLVM_IAS=1 \
	CROSS_COMPILE=aarch64-linux-gnu- \
	CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
	Image.gz dtbs; \
	then

    echo -e "\nKernel compiled successfully! Zipping up...\n"

    # Clone AnyKernel3 and create zip
    git clone -q --depth=1 https://github.com/Addster09/AnyKernel3 AnyKernel3
    cp out/arch/arm64/boot/Image.gz AnyKernel3
    (cd AnyKernel3 && zip -r9 "../$ZIPNAME" * -x '*.git*' README.md '*placeholder')
    rm -rf AnyKernel3 

    echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!"
    echo "Zip: $ZIPNAME"
else
    echo -e "\nCompilation failed!"
fi

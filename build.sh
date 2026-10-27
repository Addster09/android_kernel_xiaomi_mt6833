#!/bin/bash

# Compile script for Aqua kernel

# Date/Time
SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')

# Toolchain
TC_DIR="$HOME/toolchains/ZyC-clang-22.0.0"
CURRENT_DIR=$(pwd)

# Device Configs
DEVICE="everpal"
DEFCONFIG="${DEVICE}_defconfig"
ZIPNAME="AquaKernel-${DATE}.zip"

# Ensure the toolchain is available
if [ ! -d "$TC_DIR" ]; then
    mkdir -p "$TC_DIR" && cd "$TC_DIR" || exit
    wget https://github.com/ZyCromerZ/Clang/releases/download/22.0.0git-20250928-release/Clang-22.0.0git-20250928.tar.gz \
    && tar xvf Clang-22.0.0git-20250928.tar.gz \
    && rm -rf Clang-22.0.0git-20250928.tar.gz
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
            rm -f .ksu_applied KernelSU* SU_patch
            git restore .
            INCLUDE_KSU=true
            ;;
    esac
done

# Perform clean build if specified
[ "$CLEAN_BUILD" = true ] && rm -rf out KernelSU* .ksu_applied && git clean -fd && git restore .

[ -f .ksu_applied ] && echo "Including KernelSU Next!"

# Include KernelSU if specified
if [[ "$INCLUDE_KSU" = true && ! -f .ksu_applied ]]; then
    echo "Including KernelSU Next!"
    curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash
    git clone https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd.git --depth=1 SU_patch
    for patch in SU_patch/Patches/*sh; do
        bash $patch
    done
    patch -p1 -N --batch < SU_patch/Patches/Patch/susfs_patch_to_4.14.patch
    wget https://raw.githubusercontent.com/Addster09/EverpalPatches/main/KSUPatches/defconfig-Enable-KSU-and-SUSFS.patch
    wget https://raw.githubusercontent.com/Addster09/EverpalPatches/main/KSUPatches/susfs_patch_taskmmu.patch
    patch -p1 -N --batch < defconfig-Enable-KSU-and-SUSFS.patch
    patch -p1 -N --batch < susfs_patch_taskmmu.patch
    rm -rf defconfig-Enable-KSU-and-SUSFS.patch susfs_patch_taskmmu.patch
    rm -rf SU_patch
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
	KCFLAGS="-Wno-error=default-const-init-var-unsafe" \
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

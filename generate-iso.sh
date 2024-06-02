#!/bin/bash

# *****************************************************************************
# CREDIT: This script is a slimmed down version of cloudymax's pxeless project.
# I needed a specialized script to generate the ISO for my main homelab server.
# All options that aren't appropriate for my application are removed for
# reliability and ease of future maintenance. Max based his script on one by
# covertsh. Many thanks to both of them as their work was instrumental in the
# creation of mine.
# https://github.com/cloudymax/pxeless
# https://github.com/covertsh/ubuntu-autoinstall-generator
# *****************************************************************************

set -Eeuo pipefail

trap cleanup SIGINT SIGTERM ERR EXIT
[[ ! -x "$(command -v date)" ]] && echo "💥 date command not found." && exit 1

# export initial variables
export_metadata() {
  export ORIGINAL_ISO="ubuntu-original.iso"
  export EFI_IMAGE="ubuntu-original.efi"
  export MBR_IMAGE="ubuntu-original.mbr"
  export DESTINATION_ISO="ubuntu-autoinstall.iso"
  export DEFAULT_TIMEOUT="30"
  export TIMEOUT="${DEFAULT_TIMEOUT}"
  export UBUNTU_GPG_KEY_ID="843938DF228D22F7B3742BC0D94AA3F0EFE21092"
  export ALL_IN_ONE=0
  export USE_HWE_KERNEL=0
  export USE_RELEASE_ISO=0
  export CODE_NAME="noble" # ubuntu 24
}

# Create temporary directories for fie download and expansion
create_tmp_dirs() {
  export TMP_DIR=$(mktemp -d)
  if [[ ! "${TMP_DIR}" || ! -d "${TMP_DIR}" ]]; then
    die "💥 Could not create temporary working directory."
  else
    log "📁 Created temporary working directory ${TMP_DIR}"
  fi

  export BUILD_DIR=$(mktemp -d)
  if [[ ! "${BUILD_DIR}" || ! -d "${BUILD_DIR}" ]]; then
    die "💥 Could not create temporary build directory."
  else
    log "📁 Created temporary build directory ${BUILD_DIR}"
  fi
}

# verify that system dependancies are in-place
verify_deps() {
  log "🔎 Checking for required utilities..."
  [[ ! -x "$(command -v xorriso)" ]] && die "💥 xorriso is not installed. On Ubuntu, install  the 'xorriso' package."
  [[ ! -x "$(command -v sed)" ]] && die "💥 sed is not installed. On Ubuntu, install the 'sed' package."
  [[ ! -x "$(command -v curl)" ]] && die "💥 curl is not installed. On Ubuntu, install the 'curl' package."
  [[ ! -x "$(command -v gpg)" ]] && die "💥 gpg is not installed. On Ubuntu, install the 'gpg' package."
  [[ ! -x "$(command -v fdisk)" ]] && die "💥 fdisk is not installed. On Ubuntu, install the 'fdisk' package."

  log "👍 All required utilities are installed."
}

# get the url and iso info for the latest release
latest_release() {
  BASE_URL="https://releases.ubuntu.com/${CODE_NAME}/"
  log "🔎 Checking for latest ${CODE_NAME} release..."
  ISO_FILE_NAME=$(curl -sSL "${BASE_URL}" | grep -oP "ubuntu-.*-server-amd64.iso" | head -n 1)
  IMAGE_NAME=$(curl -sSL ${BASE_URL} | grep -o 'Ubuntu .* .*)' | head -n 1)
  CURRENT_RELEASE=$(echo "${ISO_FILE_NAME}" | cut -f2 -d-)
  SHA_SUFFIX="${CURRENT_RELEASE}"
  SOURCE_ISO="${ISO_FILE_NAME}" # request the release iso
  ORIGINAL_ISO="${ISO_FILE_NAME}" # set it as the filename for the download
  log "✅ Latest release is ${CURRENT_RELEASE}"
}

# download the specified ISO
download_iso() {

  if [ ! -f "${SOURCE_ISO}" ]; then
    log "🌎 Downloading ISO image for ${IMAGE_NAME} ..."
    wget --no-verbose \
      --show-progress \
      --progress=bar:force:noscroll \
      -O "${ORIGINAL_ISO}" "${BASE_URL}/${ISO_FILE_NAME}"

    log "👍 Downloaded and saved to ${ORIGINAL_ISO}"
  else
    log "☑️ Using existing ${SOURCE_ISO} file."
  fi
}

# Verify iso GPG keys
verify_gpg() {
  export GNUPGHOME=${TMP_DIR}
  if [ ! -f "${TMP_DIR}/SHA256SUMS-${SHA_SUFFIX}" ]; then
    log "🌎 Downloading SHA256SUMS & SHA256SUMS.gpg files..."
    curl -NsSL "${BASE_URL}/SHA256SUMS" -o "${TMP_DIR}/SHA256SUMS-${SHA_SUFFIX}"
    curl -NsSL "${BASE_URL}/SHA256SUMS.gpg" -o "${TMP_DIR}/SHA256SUMS-${SHA_SUFFIX}.gpg"
  else
    log "☑️ Using existing SHA256SUMS-${SHA_SUFFIX} & SHA256SUMS-${SHA_SUFFIX}.gpg files."
  fi

  if [ ! -f "${TMP_DIR}/${UBUNTU_GPG_KEY_ID}.keyring" ]; then
    log "🌎 Downloading and saving Ubuntu signing key..."
    gpg -q --no-default-keyring --keyring "${TMP_DIR}/${UBUNTU_GPG_KEY_ID}.keyring" --keyserver "hkp://keyserver.ubuntu.com" --recv-keys "${UBUNTU_GPG_KEY_ID}" 2>/dev/null
    log "👍 Downloaded and saved to ${TMP_DIR}/${UBUNTU_GPG_KEY_ID}.keyring"
  else
    log "☑️ Using existing Ubuntu signing key saved in ${TMP_DIR}/${UBUNTU_GPG_KEY_ID}.keyring"
  fi

  log "🔐 Verifying ${SOURCE_ISO} integrity and authenticity..."
  gpg -q --keyring "${TMP_DIR}/${UBUNTU_GPG_KEY_ID}.keyring" --verify "${TMP_DIR}/SHA256SUMS-${SHA_SUFFIX}.gpg" "${TMP_DIR}/SHA256SUMS-${SHA_SUFFIX}" 2>/dev/null
  if [ $? -ne 0 ]; then
    rm -f "${TMP_DIR}/${UBUNTU_GPG_KEY_ID}.keyring~"
    die "👿 Verification of SHA256SUMS signature failed."
  fi

  rm -f "${TMP_DIR}/${UBUNTU_GPG_KEY_ID}.keyring~"
  digest=$(sha256sum "${SOURCE_ISO}" | cut -f1 -d ' ')
  set +e
  grep -Fq "$digest" "${TMP_DIR}/SHA256SUMS-${SHA_SUFFIX}"
  if [ $? -eq 0 ]; then
    log "👍 Verification succeeded."
    set -e
  else
    die "👿 Verification of ISO digest failed."
  fi
}

# extract the EFI and disk image formt the ISO
extract_images() {
  log "🔧 Extracting ISO image..."
  xorriso -osirrox on -indev "${SOURCE_ISO}" -extract / "${BUILD_DIR}" &>/dev/null
  chmod -R u+w "${BUILD_DIR}"
  rm -rf "${BUILD_DIR}/"'[BOOT]'
  log "👍 Extracted to ${BUILD_DIR}"

  log "🔧 Extracting MBR image..."
  dd if="${SOURCE_ISO}" bs=1 count=446 of="${TMP_DIR}/${MBR_IMAGE}" &>/dev/null
  log "👍 Extracted to ${TMP_DIR}/${MBR_IMAGE}"

  log "🔧 Extracting EFI image..."
  START_BLOCK=$(fdisk -l "${SOURCE_ISO}" | fgrep '.iso2 ' | awk '{print $2}')
  SECTORS=$(fdisk -l "${SOURCE_ISO}" | fgrep '.iso2 ' | awk '{print $4}')
  dd if="${SOURCE_ISO}" bs=512 skip="${START_BLOCK}" count="${SECTORS}" of="${TMP_DIR}/${EFI_IMAGE}" &>/dev/null
  log "👍 Extracted to ${TMP_DIR}/${EFI_IMAGE}"
}

# add the auto-install kerel param
set_kernel_autoinstall() {
  log "🧩 Adding autoinstall parameter to kernel command line..."
  sed -i -e 's/---/ autoinstall  ---/g' "${BUILD_DIR}/boot/grub/grub.cfg"
  sed -i -e 's/---/ autoinstall  ---/g' "${BUILD_DIR}/boot/grub/loopback.cfg"

  if [[ "${TIMEOUT}" != "${DEFAULT_TIMEOUT}" ]]; then
    log "🧩 Setting grub timeout to ${TIMEOUT} sec ..."
    sed -i -e "s/set timeout=30/set timeout=${TIMEOUT}/g" "${BUILD_DIR}/boot/grub/grub.cfg"
    sed -i -e "s/set timeout=30/set timeout=${TIMEOUT}/g" "${BUILD_DIR}/boot/grub/loopback.cfg"
    log "👍 Set grub timeout to ${TIMEOUT} sec."
  fi

  log "👍 Added parameter to UEFI and BIOS kernel command lines."

  if [ ${ALL_IN_ONE} -eq 1 ]; then
    log "🧩 Adding user-data and meta-data files..."
    mkdir -p "${BUILD_DIR}/nocloud"
    cp "$USER_DATA_FILE" "${BUILD_DIR}/nocloud/user-data"

    if [ -n "${META_DATA_FILE}" ]; then
      cp "$META_DATA_FILE" "${BUILD_DIR}/nocloud/meta-data"
    else
      touch "${BUILD_DIR}/nocloud/meta-data"
    fi

    sed -i -e 's,---, ds=nocloud\\\;s=/cdrom/nocloud/  ---,g' "${BUILD_DIR}/boot/grub/grub.cfg"
    sed -i -e 's,---, ds=nocloud\\\;s=/cdrom/nocloud/  ---,g' "${BUILD_DIR}/boot/grub/loopback.cfg"
    log "👍 Added data and configured kernel command line."
  fi
}

# re-create the MD5 checksum data
md5_checksums() {
  log "👷 Updating ${BUILD_DIR}/md5sum.txt with hashes of modified files..."
  md5=$(md5sum "${BUILD_DIR}/boot/grub/grub.cfg" | cut -f1 -d ' ')
  sed -i -e 's,^.*[[:space:]] ./boot/grub/grub.cfg,'"$md5"'  ./boot/grub/grub.cfg,' "${BUILD_DIR}/md5sum.txt"
  md5=$(md5sum "${BUILD_DIR}/boot/grub/loopback.cfg" | cut -f1 -d ' ')
  sed -i -e 's,^.*[[:space:]] ./boot/grub/loopback.cfg,'"$md5"'  ./boot/grub/loopback.cfg,' "${BUILD_DIR}/md5sum.txt"
  log "👍 Updated hashes."
  md5=$(md5sum "${BUILD_DIR}/.disk/info" | cut -f1 -d ' ')
  sed -i -e 's,^.*[[:space:]] .disk/info,'"$md5"'  .disk/info,' "${BUILD_DIR}/md5sum.txt"
}

# add the MBR, EFI, Disk Image, and Cloud-Init back to the ISO
reassemble_iso() {

  if [ "${SOURCE_ISO}" != "${BUILD_DIR}/${ORIGINAL_ISO}" ]; then
    [[ ! -f "${SOURCE_ISO}" ]] && die "💥 Source ISO file could not be found."
  fi

  log "📦 Repackaging extracted files into an ISO image (using El Torito method)..."

  xorriso -as mkisofs \
    -r -V "ubuntu-autoinstall" -J -joliet-long -l \
    -iso-level 3 \
    -partition_offset 16 \
    --grub2-mbr "${TMP_DIR}/${MBR_IMAGE}" \
    --mbr-force-bootable \
    -append_partition 2 0xEF "${TMP_DIR}/${EFI_IMAGE}" \
    -appended_part_as_gpt \
    -c boot.catalog \
    -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
    -eltorito-alt-boot \
    -e '--interval:appended_partition_2:all::' \
    -no-emul-boot \
    -o "${DESTINATION_ISO}" "${BUILD_DIR}" &>/dev/null

  log "👍 Repackaged into ${DESTINATION_ISO}"
  die "✅ Completed." 0
}

# Cleanup folders we created
cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  if [ -n "${TMP_DIR+x}" ]; then
    #rm -rf "${TMP_DIR}"
    #rm -rf "${BUILD_DIR}"
    log "🚽 Deleted temporary working directory ${TMP_DIR}"
  fi
}

# Log with datestamp
log() {
  echo >&2 -e "[$(date +"%Y-%m-%d %H:%M:%S")] ${1-}"
}

# kill on error
die() {
  local MSG=$1
  local CODE=${2-1} # Bash parameter expansion - default exit status 1. See https://wiki.bash-hackers.org/syntax/pe#use_a_default_value
  log "${MSG}"
  exit "${CODE}"
}


main() {
  export_metadata
  create_tmp_dirs
  verify_deps
  latest_release
  download_iso
  verify_gpg
  extract_images
  set_kernel_autoinstall
  md5_checksums
  reassemble_iso
  cleanup
}

main "$@"

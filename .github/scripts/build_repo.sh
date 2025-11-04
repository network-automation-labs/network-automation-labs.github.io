#!/bin/bash
# Credit @JonTheNiceGuy
# https://jon.sprig.gs/blog/post/2835
# https://github.com/terminate-notice/terminate-notice.github.io/blob/188c38acde86ee727662c57ac40270f536a3d23d/.github/scripts/build_repos.sh

generate_hashes() {
  HASH_TYPE="$1"
  HASH_COMMAND="$2"
  echo "${HASH_TYPE}:"
  find "${COMPONENTS:-main}" -type f | while read -r file
  do
    echo " $(${HASH_COMMAND} "$file" | cut -d" " -f1) $(wc -c "$file")"
  done
}

main() {
  GOT_DEB=0
  DEB_POOL="public/deb/pool/${COMPONENTS:-main}"
  DEB_DISTS="dists/${SUITE:-stable}"
  DEB_DISTS_COMPONENTS="${DEB_DISTS}/${COMPONENTS:-main}/binary-all"
  GPG_TTY="$(tty)"
  export GPG_TTY
  echo "Parsing the repo list"
  while IFS= read -r repo ; do
    if release=$(curl -fqs https://api.github.com/repos/${repo}/releases/latest) ; then
      tag="$(echo "$release" | jq -r '.tag_name')"
      deb_files="$(echo "$release" | jq -r '.assets[] | select(.name | endswith(".deb")) | .name')"
      echo "Parsing repo $repo at $tag"
      if [ -n "$deb_files" ] ; then
        GOT_DEB=1
        mkdir -p "$DEB_POOL"
        pushd "$DEB_POOL" >/dev/null
        for deb_file in $deb_files ; do
          echo "Getting DEB ${deb_file}"
          wget -q "https://github.com/${repo}/releases/download/${tag}/${deb_file}"
        done
        popd >/dev/null
      fi
    fi
  done < .github/config/package_list.txt

  if [ $GOT_DEB -eq 1 ] ; then
    pushd public/deb >/dev/null
    mkdir -p "${DEB_DISTS_COMPONENTS}"
    echo "Scanning all downloaded DEB Packages and creating Packages file."
    dpkg-scanpackages --multiversion pool/ > "${DEB_DISTS_COMPONENTS}/Packages"
    gzip -9 > "${DEB_DISTS_COMPONENTS}/Packages.gz" < "${DEB_DISTS_COMPONENTS}/Packages"
    bzip2 -9 > "${DEB_DISTS_COMPONENTS}/Packages.bz2" < "${DEB_DISTS_COMPONENTS}/Packages"
    popd >/dev/null
    pushd "public/deb/${DEB_DISTS}" >/dev/null
    echo "Making Release file"
    {
      echo "Origin: ${ORIGIN}"
      echo "Label: ${REPO_OWNER}"
      echo "Suite: ${SUITE:-stable}"
      echo "Codename: ${SUITE:-stable}"
      echo "Version: 1.0"
      echo "Architectures: all"
      echo "Components: ${COMPONENTS:-main}"
      echo "Description: ${DESCRIPTION:-A repository for packages released by ${REPO_OWNER}}"
      echo "Date: $(date -Ru)"
      generate_hashes MD5Sum md5sum
      generate_hashes SHA1 sha1sum
      generate_hashes SHA256 sha256sum
    } > Release
    echo "Signing Release file"
    gpg --detach-sign --armor --sign > Release.gpg < Release
    gpg --detach-sign --armor --sign --clearsign > InRelease < Release
    echo "DEB repo built"
    popd >/dev/null
  fi
}
main
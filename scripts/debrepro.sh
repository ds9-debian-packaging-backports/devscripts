#!/bin/sh

# debrepro: a reproducibility tester for Debian packages
#
# © 2016 Antonio Terceiro <terceiro@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

set -eu

first_banner=y
banner() {
  if [ "$first_banner" = n ]; then
    echo
  fi
  echo "$@" | sed -e 's/./=/g'
  echo "$@"
  echo "$@" | sed -e 's/./=/g'
  echo
  first_banner=n
}

variation() {
  echo
  echo "# Variation:" "$@"
}

vary() {
  local first="$1"
  local second="${2:-}"
  if [ -z "$second" ]; then
    second="$first"
    first=''
  fi
  if [ "$which_build" = 'first' ]; then
    if [ -n "$first" ]; then
      echo "$first"
    fi
  else
    echo "$second"
  fi
}

create_build_script() {
  echo 'set -eu'

  echo
  echo "# this script must be run from inside an unpacked Debian source"
  echo "# package"
  echo

  echo 'export SOURCE_DATE_EPOCH=$(date -d "$(dpkg-parsechangelog -SDate)" +%s)'

  variation PATH
  vary 'export PATH="$PATH":/i/capture/the/path'

  variation USER
  vary 'export USER=user1' 'export USER=user2'

  variation umask
  vary 'umask 0022' 'umask 0002'

  variation locale
  vary 'export LC_ALL=C.UTF-8 LANG=C.UTF-8' \
    'export LC_ALL=pt_BR.UTF-8 LANG=pt_BR.UTF-8'

  variation timezone
  vary 'export TZ=UTC' \
    'export TZ=Asia/Tokyo'

  if which disorderfs >/dev/null; then
    variation filesystem ordering
    echo 'mkdir ../disorderfs'
    echo 'disorderfs --shuffle-dirents=yes $(pwd) ../disorderfs'
    echo 'trap "cd .. && fusermount -u disorderfs && rmdir disorderfs" INT TERM EXIT'
    echo 'cd ../disorderfs'
  fi

  echo
  echo 'dpkg-source --before-build .'
  echo 'fakeroot debian/rules clean'

  variation date
  vary 'fakeroot debian/rules binary' \
    'faketime "+213days +7hours +13minutes" fakeroot debian/rules binary'
}


build() {
  export which_build="$1"
  mkdir "$tmpdir/$which_build"
  cp -r "$SOURCE" "$tmpdir/$which_build/source"
  cd "$tmpdir/$which_build/source"

  create_build_script > ../build.sh

  sh ../build.sh

  cd -
}

binmatch() {
  cmp --silent "$1" "$2"
}

compare() {
  rc=0
  for first_deb in "$tmpdir"/first/*.deb; do
    deb="$(basename "$first_deb")"
    second_deb="$tmpdir"/second/"$deb"
    if binmatch "$first_deb" "$second_deb"; then
      echo "✓ $deb: binaries match"
    else
      echo ""
      rc=1
      if which diffoscope >/dev/null; then
        diffoscope "$first_deb" "$second_deb" || true
      else
        echo "✗ $deb: binaries don't match"
      fi
    fi
  done
  if [ "$rc" -ne 0 ]; then
    echo "E: package is not reproducible."
    if ! which diffoscope >/dev/null; then
      echo "I: install diffoscope for a deeper comparison between binaries"
    fi
  fi
  return "$rc"
}

SOURCE="${1:-}"
if [ -z "$SOURCE" ]; then
  SOURCE="$(pwd)"
fi
if [ ! -f "$SOURCE/debian/changelog" ]; then
  echo "E: $SOURCE does not look like a Debian source package"
  exit 2
fi

tmpdir=$(mktemp --directory --tmpdir debrepro.XXXXXXXXXX)
trap "echo; echo 'I: artifacts left in $tmpdir'" INT TERM EXIT

banner "First build"
build first

banner "Second build"
build second

banner "Comparing binaries"
compare first second

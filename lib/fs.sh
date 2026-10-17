#!/usr/bin/env bash
# fs.sh — bounded loopback filesystems for the resource-exhaustion challenges.
#
# A break that fills a disk must not be able to fill the wrong disk, and a reset
# must not cost more than the drill. So each of those challenges gets its own
# fixed-size image, formatted and mounted under LAB_SCRATCH_MNT, and resets by
# being thrown away rather than traversed.
#
# Every destructive function refuses to act on anything that is not one of our
# own loop mounts. That check is the whole safety story of this file.
set -euo pipefail
# errexit does not reach inside $(...) unless this is set, so a function that
# fails mid-way would otherwise return its partial output with status 0.
shopt -s inherit_errexit

# The parent directory images live in, and the parent of every mount point.
lab_fs_root()     { printf '%s\n' "${LAB_SCRATCH_DIR:-/var/lib/breakfix-lab}"; }
lab_fs_mnt_root() { printf '%s\n' "${LAB_SCRATCH_MNT:-/srv/lab-scratch}"; }

lab_fs_img()  { printf '%s/%s.img\n' "$(lab_fs_root)" "$1"; }
lab_fs_mnt()  { printf '%s/%s\n' "$(lab_fs_mnt_root)" "$1"; }

# True only for a mounted filesystem backed by a loop device whose backing file
# is one of ours. Nothing else is ever formatted, filled or unmounted.
lab_fs_is_ours() {
  local mnt="$1" src backing
  mountpoint -q "$mnt" 2>/dev/null || return 1
  src="$(findmnt -n -o SOURCE --target "$mnt" 2>/dev/null || true)"
  [[ "$src" == /dev/loop* ]] || return 1
  backing="$(losetup -n -O BACK-FILE "$src" 2>/dev/null || true)"
  [[ "$backing" == "$(lab_fs_root)"/* ]]
}

# lab_fs_make <name> <size_mb> [inode_count]
#
# Every step is checked explicitly rather than left to errexit, and the mount is
# verified afterwards: this function must never return a path it did not mount,
# because the caller is about to fill it.
lab_fs_make() {
  local name="$1" size_mb="$2" inodes="${3:-}"
  local img mnt actual args=()
  img="$(lab_fs_img "$name")"; mnt="$(lab_fs_mnt "$name")"

  lab_as_root mkdir -p "$(lab_fs_root)" "$mnt" || {
    printf 'lab_fs_make: cannot create %s or %s\n' "$(lab_fs_root)" "$mnt" >&2; return 1; }

  if lab_fs_is_ours "$mnt"; then
    printf '%s\n' "$mnt"; return 0
  fi
  if mountpoint -q "$mnt" 2>/dev/null; then
    printf 'lab_fs_make: refusing: %s is already a mount and not one of ours\n' "$mnt" >&2
    return 1
  fi

  lab_as_root rm -f "$img"
  if ! lab_as_root fallocate -l "${size_mb}M" "$img" 2>/dev/null; then
    lab_as_root dd if=/dev/zero of="$img" bs=1M count="$size_mb" status=none || {
      printf 'lab_fs_make: could not create a %sM image at %s\n' "$size_mb" "$img" >&2
      lab_as_root rm -f "$img"; return 1; }
  fi

  # A short image means the filesystem underneath is itself full. Formatting it
  # and carrying on would produce a "bounded" filesystem that is not bounded.
  actual=$(( $(stat -c '%s' "$img") / 1048576 ))
  if (( actual < size_mb )); then
    printf 'lab_fs_make: image is only %sM of %sM; the backing filesystem is full\n' \
      "$actual" "$size_mb" >&2
    lab_as_root rm -f "$img"; return 1
  fi

  [[ -z "$inodes" ]] || args+=(-N "$inodes")
  lab_as_root mkfs.ext4 -q -F "${args[@]+"${args[@]}"}" "$img" >/dev/null || {
    printf 'lab_fs_make: mkfs failed on %s\n' "$img" >&2
    lab_as_root rm -f "$img"; return 1; }

  lab_as_root mount -o loop,rw "$img" "$mnt" || {
    printf 'lab_fs_make: could not mount %s on %s\n' "$img" "$mnt" >&2
    lab_as_root rm -f "$img"; return 1; }

  # The decisive check. Nothing proceeds unless this really is our loop mount.
  if ! lab_fs_is_ours "$mnt"; then
    printf 'lab_fs_make: %s did not become one of our loop mounts; backing out\n' "$mnt" >&2
    lab_as_root umount "$mnt" 2>/dev/null || true
    lab_as_root rm -f "$img"
    return 1
  fi

  lab_as_root chmod 1777 "$mnt"
  printf '%s\n' "$mnt"
}

# lab_fs_require <name> <size_mb> [inodes]
#
# What a break script calls. Returns the mount point only if it is genuinely a
# bounded lab filesystem, and refuses loudly otherwise, so a failed mount can
# never turn into "fill whatever that path happens to be on".
lab_fs_require() {
  local name="$1" mnt=""
  if ! mnt="$(lab_fs_make "$@")" || [[ -z "$mnt" ]] || ! lab_fs_is_ours "$mnt"; then
    printf 'refusing to continue: %s is not a bounded lab filesystem.\n' \
      "$(lab_fs_mnt "$name")" >&2
    printf 'Nothing has been changed. A break that fills a filesystem may only ever\n' >&2
    printf 'fill one of ours, and this one could not be created.\n' >&2
    return 1
  fi
  printf '%s\n' "$mnt"
}

# lab_fs_fill_kb <mount> <percent> <cap_mb>
# How much to write: a share of what is free, hard-capped by the filesystem's
# own configured size, so a wrong mount point cannot become a large write.
lab_fs_fill_kb() {
  local mnt="$1" pct="$2" cap_mb="$3" avail_k fill_k cap_k
  avail_k="$(df -Pk "$mnt" | awk 'NR==2{print $4}')"
  fill_k=$(( avail_k * pct / 100 ))
  cap_k=$(( cap_mb * 1024 ))
  (( fill_k <= cap_k )) || fill_k="$cap_k"
  printf '%s\n' "$fill_k"
}

# lab_fs_destroy <name> — unmount, detach, delete. Harmless if already gone.
lab_fs_destroy() {
  local name="$1" img mnt src
  img="$(lab_fs_img "$name")"; mnt="$(lab_fs_mnt "$name")"

  if mountpoint -q "$mnt" 2>/dev/null; then
    if ! lab_fs_is_ours "$mnt"; then
      printf 'lab_fs_destroy: refusing: %s is not one of our loop mounts\n' "$mnt" >&2
      return 1
    fi
    src="$(findmnt -n -o SOURCE --target "$mnt" 2>/dev/null || true)"
    # Anything still holding a file here would otherwise block the unmount.
    lab_as_root fuser -k -M -m "$mnt" >/dev/null 2>&1 || true
    lab_as_root umount "$mnt" 2>/dev/null || lab_as_root umount -l "$mnt" 2>/dev/null || true
    [[ -z "$src" ]] || lab_as_root losetup -d "$src" 2>/dev/null || true
  fi
  lab_as_root rm -f "$img"
  lab_as_root rmdir "$mnt" 2>/dev/null || true
}

# lab_fs_reformat <name> <size_mb> [inodes] — O(1) reset: throw it away and
# make it again, rather than deleting a million files one at a time.
lab_fs_reformat() {
  lab_fs_destroy "$1" || return 1
  lab_fs_make "$@"
}

lab_fs_pct()       { df -P "$1" 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5+0}'; }
lab_fs_inode_pct() { df -Pi "$1" 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5+0}'; }

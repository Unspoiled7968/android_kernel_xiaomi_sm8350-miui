#!/system/bin/sh

set -eu

SYSFS_DIR="/sys/class/qcom-battery"

if [ "${1:-}" = "" ]; then
  echo "usage: $0 /path/to/profile.conf" >&2
  exit 1
fi

PROFILE_PATH="$1"

if [ ! -f "$PROFILE_PATH" ]; then
  echo "profile not found: $PROFILE_PATH" >&2
  exit 1
fi

# shellcheck source=/dev/null
. "$PROFILE_PATH"

write_node() {
  node="$1"
  value="$2"
  path="$SYSFS_DIR/$node"

  if [ ! -e "$path" ]; then
    echo "missing sysfs node: $path" >&2
    exit 1
  fi

  printf "%s" "$value" > "$path"
}

read_node() {
  node="$1"
  path="$SYSFS_DIR/$node"
  if [ -e "$path" ]; then
    cat "$path"
  fi
}

if [ ! -e "$SYSFS_DIR/capacity_compat_enable" ]; then
  echo "kernel battery compatibility sysfs nodes not found" >&2
  exit 1
fi

if [ "${CAPACITY_COMPAT_ENABLE:-0}" = "1" ]; then
  if [ "${CAPACITY_COMPAT_FULL_UAH:-0}" -le 0 ]; then
    echo "CAPACITY_COMPAT_FULL_UAH must be > 0 before enabling" >&2
    exit 1
  fi
  if [ "${CAPACITY_COMPAT_DESIGN_UAH:-0}" -lt "${CAPACITY_COMPAT_FULL_UAH:-0}" ]; then
    echo "CAPACITY_COMPAT_DESIGN_UAH must be >= CAPACITY_COMPAT_FULL_UAH" >&2
    exit 1
  fi
fi

# Disable first so a half-written profile never becomes active.
write_node "capacity_compat_enable" "0"
write_node "capacity_compat_full_uah" "${CAPACITY_COMPAT_FULL_UAH:-0}"
write_node "capacity_compat_design_uah" "${CAPACITY_COMPAT_DESIGN_UAH:-0}"
write_node "capacity_compat_empty_uv" "${CAPACITY_COMPAT_EMPTY_UV:-3150000}"
write_node "capacity_compat_reserve_pct" "${CAPACITY_COMPAT_RESERVE_PCT:-2}"
write_node "capacity_compat_enable" "${CAPACITY_COMPAT_ENABLE:-0}"

echo "profile applied: ${PROFILE_ID:-unknown}"
echo "profile name: ${PROFILE_NAME:-unknown}"
echo "stage: ${PROFILE_STAGE:-unknown}"
echo "--- status ---"
read_node "capacity_compat_status"

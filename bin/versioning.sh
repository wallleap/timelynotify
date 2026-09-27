#!/usr/bin/env bash
# Shared release-version parser. Source this file from Bash; it does not mutate the repository.
# Published stable tags predating the two-digit scheme keep their historical code only in old artifacts.
# New beta tags use slots 01–98; the stable tag uses slot 99.

version_parse() {
  local value="${1#v}"
  local pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-beta\.([1-9][0-9]*))?$'
  if [[ ! "$value" =~ $pattern ]]; then
    echo "错误: 版本 '$1' 应为 x.y.z 或 x.y.z-beta.n" >&2
    return 1
  fi

  VERSION_MAJOR="${BASH_REMATCH[1]}"
  VERSION_MINOR="${BASH_REMATCH[2]}"
  VERSION_PATCH="${BASH_REMATCH[3]}"
  VERSION_BETA="${BASH_REMATCH[5]:-}"
  if [ "${#VERSION_MAJOR}" -gt 2 ] || [ "${#VERSION_MINOR}" -gt 3 ] ||
     [ "${#VERSION_PATCH}" -gt 3 ] || [ "$VERSION_MINOR" -ge 1000 ] ||
     [ "$VERSION_PATCH" -ge 1000 ]; then
    echo "错误: 版本段越界（major≤21，minor/patch≤999）" >&2
    return 1
  fi

  VERSION_BASE="$VERSION_MAJOR.$VERSION_MINOR.$VERSION_PATCH"
  VERSION_NAME="$value"
  VERSION_TAG="v$value"
  VERSION_STAGE="stable"
  VERSION_SLOT=99
  if [ -n "$VERSION_BETA" ]; then
    if [ "${#VERSION_BETA}" -gt 2 ] || [ "$VERSION_BETA" -gt 98 ]; then
      echo "错误: beta 序号必须在 1–98 之间" >&2
      return 1
    fi
    VERSION_STAGE="beta"
    VERSION_SLOT="$VERSION_BETA"
  fi

  VERSION_CODE=$(( (VERSION_MAJOR * 1000000 + VERSION_MINOR * 1000 + VERSION_PATCH) * 100 + VERSION_SLOT ))
  if [ "$VERSION_CODE" -gt 2147483647 ]; then
    echo "错误: versionCode=$VERSION_CODE 超出 31 位非负整数范围" >&2
    return 1
  fi
}

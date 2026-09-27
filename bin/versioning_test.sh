#!/usr/bin/env bash
# Run with: bash bin/versioning_test.sh. No repository or network changes.
set -euo pipefail

source "$(dirname "$0")/versioning.sh"

assert_version() {
  local name="$1" expected_code="$2" expected_stage="$3"
  version_parse "$name"
  if [ "$VERSION_NAME" != "${name#v}" ] || [ "$VERSION_CODE" != "$expected_code" ] ||
     [ "$VERSION_STAGE" != "$expected_stage" ]; then
    echo "失败: $name → $VERSION_NAME/$VERSION_CODE/$VERSION_STAGE" >&2
    exit 1
  fi
}

assert_invalid() {
  if version_parse "$1" >/dev/null 2>&1; then
    echo "失败: 意外接受无效版本 $1" >&2
    exit 1
  fi
}

assert_version v1.1.2 100100299 stable
assert_version 1.2.0-beta.1 100200001 beta
assert_version 1.2.0-beta.98 100200098 beta
assert_version 1.2.0 100200099 stable
assert_version 21.474.835 2147483599 stable

for invalid in 1.2 01.2.3 1.02.3 1.2.03 1.2.0-beta.0 1.2.0-beta.01 \
  1.2.0-beta.99 1.1000.0 1.2.1000 21.474.836 22.0.0 1.2.0-rc.1; do
  assert_invalid "$invalid"
done

echo "版本解析和编号测试通过"

#!/usr/bin/env bash
# 沉浸光感边界检查：版本/能力判断和原始材质构造只能位于 ImmersiveUtil.ets。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_root="${1:-$repo_root/entry/src/main/ets}"
util_file="$source_root/utils/ImmersiveUtil.ets"

if [[ ! -f "$util_file" ]]; then
  echo "错误：找不到 ImmersiveUtil.ets：$util_file" >&2
  exit 2
fi

# 只扫描 ArkTS 源码。HDS 的材质展示参数允许留在组件中，但能力判断和实例创建不可绕过 util。
forbidden='(^|[^[:alnum:]_])(CURRENT_SDK_VERSION|SUPPORTS_IMMERSIVE_MATERIAL|SUPPORTS_BACKGROUND_BLUR|KEY_MATERIAL_READY|isImmersiveMaterialSupported|getGlobalMaterialLevel)([^[:alnum:]_]|$)|import.*uiMaterial|@ohos\.arkui\.uiMaterial|new[[:space:]]+[^[:space:]]*ImmersiveMaterial|deviceInfo[[:space:]]*\.[[:space:]]*(sdkApiVersion|apiAvailable)'
failed=0

while IFS= read -r -d '' source_file; do
  if [[ "$source_file" == "$util_file" ]]; then
    continue
  fi
  grep_status=0
  matches="$(grep -nE "$forbidden" "$source_file")" || grep_status=$?
  if [[ "$grep_status" -eq 0 ]]; then
    relative_path="${source_file#"$source_root"/}"
    while IFS= read -r match; do
      printf '%s:%s\n' "$relative_path" "$match" >&2
    done <<< "$matches"
    failed=1
  elif [[ "$grep_status" -ne 1 ]]; then
    echo "错误：无法检查 $source_file（grep 退出码 $grep_status）" >&2
    exit 2
  fi
done < <(find "$source_root" -type f -name '*.ets' -print0)

if [[ "$failed" -ne 0 ]]; then
  echo '沉浸光感边界检查失败：请改用 ImmersiveUtil 提供的判断和材质接口。' >&2
  exit 1
fi

echo '沉浸光感边界检查通过'

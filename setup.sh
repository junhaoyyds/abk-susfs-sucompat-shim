#!/usr/bin/env bash
# =============================================================================
# ABK 自定义外部模块 — 阶段: after_patch
# 仓库: junhaoyyds/abk-susfs-sucompat-shim
#
# 解决的问题
# ----------
# SUSFS 的 50_add_susfs_in_gki-android15-6.6.patch 会在 fs/exec.c 的
# do_execveat_common() 中注入对 ksu_handle_post_execveat_sucompat() 的调用
# （这是「官方 KernelSU」的 API 名）。而提供该函数定义的
# 10_enable_susfs_for_ksu.patch 在 ABK 里只有 Official 变体才会被应用，
# SukiSU / ReSukiSU 变体直接跳过 —— 于是变成「调用注入了、定义没注入」，
# 编译末期链接 vmlinux 时报:
#     ld.lld: error: undefined symbol: ksu_handle_post_execveat_sucompat
#
# 为什么给空实现是安全的
# ----------------------
# 该 post-execveat hook 的用途是：在没有 syscall-hook 能力的官方 KernelSU 上，
# 当 su 会话 execveat 成功后就地安装 scoped ksu driver fd。
# SukiSU 走自己的 syscall-hook 路径（ksu_handle_execveat_sucompat），
# 不依赖这个 post hook，所以空实现不损失任何 SukiSU root 能力。
#
# 幂等：文件内存在 MARKER 时直接跳过，重复运行无副作用。
# =============================================================================
set -euo pipefail

MARKER="ABK-SUSFS-SUCOMPAT-SHIM"
FUNC="ksu_handle_post_execveat_sucompat"

log() { printf '[susfs-sucompat-shim] %s\n' "$*"; }

KROOT="${KERNEL_ROOT:-}"
if [ -z "$KROOT" ]; then
  echo "::error::[${MARKER}] 环境变量 KERNEL_ROOT 未设置，无法定位内核源码树"
  exit 1
fi

EXEC_C="$KROOT/common/fs/exec.c"
if [ ! -f "$EXEC_C" ]; then
  echo "::error::[${MARKER}] 找不到内核源码文件: $EXEC_C"
  ls -la "$KROOT" 2>/dev/null || true
  exit 1
fi

log "内核源码树: $KROOT"
log "目标文件  : $EXEC_C"

if grep -qF "$MARKER" "$EXEC_C"; then
  log "检测到 ${MARKER} 标记，已注入过，跳过。"
  exit 0
fi

if grep -q "$FUNC" "$EXEC_C"; then
  log "确认 $FUNC 调用点存在（SUSFS 已按预期注入）。"
else
  log "提示：本文件未见 $FUNC 调用点；SUSFS 实现可能已变化。仍注入定义（无害）。"
fi

cat >> "$EXEC_C" <<'SHIM_EOF'

/* ==== ABK-SUSFS-SUCOMPAT-SHIM (after_patch) ==================================
 * SUSFS 的 50_add_susfs_in_gki-android15-6.6.patch 在 do_execveat_common()
 * 注入了 ksu_handle_post_execveat_sucompat() 调用（官方 KernelSU 的 API），
 * 但提供其定义的 10_enable_susfs_for_ksu.patch 在 ABK 中只有 Official 变体
 * 才会应用，SukiSU/ReSukiSU 变体会跳过 -> 链接期 undefined symbol。
 *
 * SukiSU 走自己的 syscall-hook 路径（ksu_handle_execveat_sucompat），
 * 该 post hook 对它属冗余，故此处提供空实现，仅用于满足链接。
 * 与调用点同处一个编译单元，签名逐参对齐。
 * 未加 CONFIG 守卫：确保任何配置下符号都存在，避免再次出现 undefined。
 * ========================================================================== */
int ksu_handle_post_execveat_sucompat(int *fd, struct filename **filename_ptr,
                                      void *argv_user, void *envp_user,
                                      int *__never_use_flags, int *retval)
{
	(void)fd;
	(void)filename_ptr;
	(void)argv_user;
	(void)envp_user;
	(void)__never_use_flags;
	(void)retval;
	return 0;
}
SHIM_EOF

log "注入完成 -> $EXEC_C"
log "校验: 文件内 '$FUNC' 出现 $(grep -c "$FUNC" "$EXEC_C") 次（调用点 + 定义）"
log "校验: 文件结尾 6 行："
tail -n 6 "$EXEC_C" | sed 's/^/    /'

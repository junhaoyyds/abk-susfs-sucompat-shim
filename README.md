# abk-susfs-sucompat-shim

ABK（Action-Build-Kernel）**自定义外部模块**，阶段固定为 `after_patch`。

## 用途

在 ABK 构建 **SukiSU / ReSukiSU + SUSFS** 组合时，补齐 SUSFS 注入的
`ksu_handle_post_execveat_sucompat()` 符号定义，避免链接期报：

```
ld.lld: error: undefined symbol: ksu_handle_post_execveat_sucompat
>>> referenced by fs/exec.c:2041 in vmlinux.o:(do_execveat_common)
```

## 根因

| 环节 | 事实 |
|---|---|
| SUSFS 侧 | 自 `3f0b811b`(2026-09-06) 起，`50_add_susfs_in_gki-android15-6.6.patch` 在 `fs/exec.c` 的 `do_execveat_common()` 注入对该函数的调用 |
| 定义侧 | 定义在 SUSFS 的 `10_enable_susfs_for_ksu.patch`（patch 到 `kernel/feature/sucompat.c`） |
| ABK 侧 | `build.yml` 的 `case "$ABK_KSU_VARIANT"` 中**只有 `Official` 变体**应用该 patch，`SukiSU` / `ReSukiSU` 分支明确跳过 |
| 结果 | 调用注入了、定义没注入 → undefined symbol |

该符号是**官方 KernelSU 的 API**；SukiSU 用的是 `ksu_handle_execveat_sucompat`（无 `post_` 前缀）。

## 为什么空实现不损失功能

该 post-execveat hook 是给**没有 syscall-hook 能力**的官方 KernelSU 用的：
su 会话 `execveat` 成功后，就地安装 scoped ksu driver fd。
SukiSU 走自己的 syscall-hook 路径，不依赖它，因此空实现只满足链接、不改变行为。

## ABK 中如何启用

`workflow_dispatch` 输入 `custom_external_modules` 填：

```
module:https://github.com/junhaoyyds/abk-susfs-sucompat-shim.git;after_patch
```

## 行为

- 目标文件：`$KERNEL_ROOT/common/fs/exec.c`
- 幂等：文件内含 `ABK-SUSFS-SUCOMPAT-SHIM` 标记时直接跳过
- 失败即报错：`KERNEL_ROOT` 未设置 / `fs/exec.c` 不存在时以非零退出，构建立即暴露问题
- 不修改 ABK fork 的任何现有文件，sync fork 零冲突

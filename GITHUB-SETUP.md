# GitHub 云端编译指南

## 概述

本项目已配置好 GitHub Actions CI 工作流，**无需本地 Linux 环境**，直接在 GitHub 云端自动编译内核。

## 前置条件

- GitHub 账号
- 已 fork 本项目到你的 GitHub 账号
- 能够接收 GitHub Actions 邮件通知（可选）

## 三步完成

### Step 1: 推送代码到 GitHub

```bash
# 如果还没有 clone
git clone https://github.com/你的用户名/k80pro-power-optimizer.git
cd k80pro-power-optimizer

# 修改代码后推送
git add .
git commit -m "你的提交信息"
git push origin main
```

### Step 2: 触发编译

1. 打开你 fork 的 GitHub 仓库页面
2. 点击 **Actions** 标签
3. 左侧选择 **"Build K80 Pro Kernel"** 工作流
4. 点击 **"Run workflow"** 按钮
5. 在弹出的表单中配置：
   - **SukiSU 分支**: `main` (默认)
   - **跳过 SukiSU**: 不勾选
   - **跳过省电补丁**: 不勾选
   - **强制清理**: 不勾选
6. 点击绿色 **"Run workflow"** 按钮

### Step 3: 下载产物

1. 等待编译完成（约 30-45 分钟，页面会实时显示进度）
2. 编译完成后，点击 **Artifacts** 区域中的 **K80Pro-Power-Kernel**
3. 下载 ZIP 文件（约 20-50MB）
4. 传到手机刷入

## 刷入步骤

```bash
# 1. 将 ZIP 传到手机
adb push K80Pro-Power-Kernel-*.zip /sdcard/

# 2. 重启到 recovery (或在 Magisk/KernelSU 中直接刷入)
# 方式一: Magisk Manager
#   - 打开 Magisk → 模块 → 从本地安装 → 选择 ZIP → 重启

# 方式二: Fastboot (如果用 AnyKernel3)
adb reboot bootloader
fastboot flash boot K80Pro-Power-Kernel-*.img
fastboot reboot

# 3. 验证
adb shell su -c 'uname -r'
# → 应包含 "k80pro-optimized"
```

## 常见问题

**Q: 编译需要多长时间？**

A: GitHub Actions 使用 4-core 16GB RAM 的 runner，约 30-45 分钟。

**Q: 可以并行触发多个编译吗？**

A: 可以，但每个编译使用独立的 runner，同时编译多个可能排队等待。

**Q: 编译失败了怎么办？**

A: 在 Actions 页面查看失败的 job，点击展开查看错误日志。常见问题：
- SukiSU 集成失败 → 勾选"跳过 SukiSU"重新编译
- 补丁应用失败 → 检查补丁与内核版本兼容性
- 编译超时（>120分钟）→ 通常是由于死循环或无限等待

**Q: 如何只编译内核不集成 SukiSU？**

A: 触发 workflow 时勾选"跳过 SukiSU"。

**Q: 编译产物保留多久？**

A: 30 天（GitHub Actions 默认保留期）。

## 自动触发

当以下文件变更时，CI 会自动触发编译：
- `kernel-patches/**`
- `kernel-build/**`
- `.github/workflows/build-kernel.yml`

你也可以在推送时添加 `[skip ci]` 来跳过 CI：

```bash
git commit -m "fix: 小修改 [skip ci]"
```
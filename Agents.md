# Agents.md - 多平台 Flutter SDK 容器开发与维护指南

本文档面向开发者与 AI Agent，全面规范本仓库的架构设计、构建流程、QEMU 跨架构支持、CI/CD 自动化流水线及常见维护任务。

---

## 1. 项目概述与核心目标

本项目旨在为 **Linux 平台** 提供开箱即用、轻量且具备高度 ABI 兼容性的 **多平台 Flutter SDK 容器镜像**。

### 核心痛点与解决方案
1. **多架构构建痛点**：
   Flutter Linux 桌面应用直接产出原生二进制，跨平台交叉编译（如 x86_64 宿主机编译 ARM64 Linux 产物）配置非常繁琐且极易因依赖库缺失报错。
   - **方案**：提供同时支持 `linux/amd64` 与 `linux/arm64` 的 Docker 镜像。配合内核 `binfmt_misc` 与 QEMU 模拟，宿主机只需指定 `--platform` 即可透明执行目标架构构建。
2. **Glibc ABI 向后兼容性痛点**：
   在高版本发行版（如 Ubuntu 24.04 / Fedora 40）编译的 Linux 二进制无法在旧版本发行版（如 Ubuntu 20.04/22.04、Debian 10/11、RHEL 8/9 等）上运行，会出现 `version GLIBC_x.xx not found`。
   - **方案**：基础镜像采用 **Fedora 30 (Glibc 2.29)**，在确保 Flutter/Dart 工具链稳定运行的同时，编译出的可执行文件具有广泛的向下兼容性。

---

## 2. 架构设计与容器规范

### 2.1 基础镜像与架构
- **Base Image**: `fedora:30`
- **目标平台 (Multi-Arch)**: `linux/amd64`, `linux/arm64` (AArch64)
- **默认 Flutter 版本**: `3.47.7`（可通过构建参数 `FLUTTER_VERSION` 任意指定）

### 2.2 预装依赖清单
- **编译工具链**: `clang`, `cmake`, `ninja-build`, `pkg-config`
- **Linux 桌面与图形开发库**: `gtk3-devel`, `mesa-libGLU`, `egl-utils`
- **系统基础与解包工具**: `curl`, `git`, `unzip`, `xz`, `zip`, `findutils`, `which`

### 2.3 容器关键配置规范
- **系统级 Git 信任**: `git config --system --add safe.directory '*'`，避免非 root 用户挂载工程时出现 Git 目录权限信任告警。
- **权限兼容性**: `/flutter` 目录预赋予 `a+rwX` 权限，确保任意 UID (`-u $(id -u):$(id -g)`) 挂载执行时正常读写临时缓存和锁文件。
- **CI 加速与静默**: 预置 `flutter config --no-analytics` 与 `dart --disable-analytics`，去除无用遥测开销。
- **预热缓存**: 构建阶段执行 `flutter precache --linux`，避免在开发或 CI 阶段二次联网拉取 Engine。
- **工作目录**: 默认为 `/workspace`。

---

## 3. 使用与构建指南

### 3.1 宿主机启用 QEMU 支持（仅需执行一次）
在 x86_64 或任意 Linux 宿主机上，需确保内核已注册 QEMU binfmt 解释器：
```bash
# 注册全架构 QEMU 模拟器
docker run --privileged --rm tonistiigi/binfmt --install all
```

### 3.2 运行并验证镜像
拉取或运行指定架构镜像：
```bash
# 验证 x86_64
docker run --rm --platform linux/amd64 ghcr.io/<owner>/flutter-sdk-container:3.47.7 flutter --version

# 借助 QEMU 验证 ARM64
docker run --rm --platform linux/arm64 ghcr.io/<owner>/flutter-sdk-container:3.47.7 flutter --version
```

### 3.3 构建实际 Flutter 桌面应用
进入你的 Flutter 项目根目录，执行对应架构的构建命令：

#### 编译 Linux x86_64 (amd64) 版本
```bash
docker run --rm \
  --platform linux/amd64 \
  -v "$(pwd)":/workspace \
  -u "$(id -u):$(id -g)" \
  ghcr.io/<owner>/flutter-sdk-container:3.47.7 \
  flutter build linux --release
```

#### 编译 Linux aarch64 (arm64) 版本（通过 QEMU 模拟）
```bash
docker run --rm \
  --platform linux/arm64 \
  -v "$(pwd)":/workspace \
  -u "$(id -u):$(id -g)" \
  ghcr.io/<owner>/flutter-sdk-container:3.47.7 \
  flutter build linux --release
```
构建产物将分别输出在宿主机本地的：
- `build/linux/x64/release/bundle/`
- `build/linux/arm64/release/bundle/`

---

## 4. 本地镜像构建与多架构测试

如果你需要在本地自行构建并测试多架构镜像，可使用 `docker buildx`：

```bash
# 创建并启用 buildx 构建器
docker buildx create --name multiarch-builder --use
docker buildx inspect --bootstrap

# 构建本地单架构镜像测试（例如本机为 x86_64）
docker build -t flutter-sdk-local:3.47.7 -f dockerfile .

# 构建多架构镜像并推送到自定义镜像仓库
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg FLUTTER_VERSION=3.47.7 \
  -t <your-registry>/flutter-sdk-container:3.47.7 \
  -f dockerfile \
  --push .
```

---

---

## 5. GitHub Actions 自动化流水线规范

工作流文件位于 [`.github/workflows/docker-publish.yml`](file:///.github/workflows/docker-publish.yml)。

### 5.1 如何打包其他 Flutter 版本并触发 CI

打包其他 Flutter 版本有以下 3 种触发方式：

#### 方式一：GitHub 网页手动触发（最推荐，随时打包任意版本）
无需修改任何代码，在 GitHub 网页上即可一键触发：
1. 访问你的 GitHub 仓库页面，点击顶部的 **Actions** 标签。
2. 在左侧工作流列表中点击 **Build and Publish Multi-Platform Flutter SDK Container**。
3. 点击右侧的 **Run workflow** 下拉按钮：
   - 在 **Flutter SDK version to build** 输入框中，填入你想打包的任意版本号（例如 `3.29.0`、`3.27.4`、`stable` 等）。
   - 保持 `Push image to registry` 为勾选状态。
4. 点击绿色的 **Run workflow** 按钮启动构建。

#### 方式二：通过 Git Tag 触发（发布正式版本）
工作流已配置版本号正则匹配，当你推送带有版本号的 Git Tag 时，CI 会自动截取版本号并以此版本拉取 Flutter SDK 进行构建：
```bash
# 例如打包 3.29.0 版本
git tag v3.29.0
git push origin v3.29.0
```
工作流将自动识别版本号为 `3.29.0`，并自动构建、打 Tag 并推送镜像。

#### 方式三：修改仓库默认版本并 Push
如果你想永久升级本仓库的基准版本：
1. 修改 [dockerfile](file:///dockerfile) 中的 `ARG FLUTTER_VERSION=<新版本号>`。
2. 修改 [docker-publish.yml](file:///.github/workflows/docker-publish.yml) 中的 `DEFAULT_FLUTTER_VERSION: '<新版本号>'`。
3. 提交代码并推送至 `main` 或 `master` 分支，CI 会自动以新版本触发构建与发布。

---

### 5.2 如何将镜像推送到 Docker Hub

工作流支持**双通道镜像发布**：默认无缝发布到 GitHub Container Registry (GHCR)；在配置了 Docker Hub 凭据后，将同步自动推送到 Docker Hub。

#### 配置步骤：
1. **获取 Docker Hub Access Token**：
   - 登录 [Docker Hub](https://hub.docker.com/)。
   - 点击右上角头像 -> **Account Settings** -> **Personal access tokens**。
   - 点击 **Generate new token**，权限选择 `Read, Write, Delete` 或 `Read & Write`，生成并复制该 Token。
2. **在 GitHub 仓库添加 Secrets**：
   - 打开本项目的 GitHub 仓库页面 -> 点击 **Settings**。
   - 在左侧菜单中展开 **Secrets and variables** -> 点击 **Actions**。
   - 点击 **New repository secret** 分别添加以下两个密钥：
     - `DOCKERHUB_USERNAME`: 你的 Docker Hub 用户名。
     - `DOCKERHUB_TOKEN`: 刚才生成的 Docker Hub Access Token。
     - *(可选)* `DOCKERHUB_REPO`: 你在 Docker Hub 预创建的仓库名（若不填写，默认使用 `flutter-sdk-container`）。
3. **自动发布**：
   - 配置完成后，下一次无论是分支推送、Tag 触发还是手动触发，CI 流水线都会检测到上述凭据，自动登录 Docker Hub 并把多架构镜像同时推送到：
     - GHCR: `ghcr.io/<github-user>/<repo-name>:<version>`
     - Docker Hub: `<dockerhub-user>/flutter-sdk-container:<version>`

---

### 5.3 自动化流水线流程
```
[Checkout]
   │
[解析目标 Flutter 版本 (Tag / Manual Input / Default)]
   │
[Set up QEMU (amd64, arm64 模拟环境)]
   │
[Set up Docker Buildx]
   │
[Login GHCR (自动) & Docker Hub (根据 Secrets 自动判断)]
   │
[Docker Buildx 多架构并行构建并发布 (amd64, arm64)] ── gha 缓存加速
   │
[QEMU 启动自检 (分别对 amd64 & arm64 运行 flutter --version 验证镜像完整性)]
```

---

## 6. 面向 Agent 的日常维护指南

AI Agent 在协助用户维护或拓展本项目时，请遵循以下原则：

1. **版本升级**：
   - 当需要支持新的 Flutter 默认版本时，修改 [dockerfile](file:///dockerfile) 中的 `ARG FLUTTER_VERSION=...` 默认值，并同步更新 [docker-publish.yml](file:///.github/workflows/docker-publish.yml) 中的 `DEFAULT_FLUTTER_VERSION`。
2. **新增系统库依赖**：
   - 若用户需要针对特定 Flutter Linux 插件添加依赖（例如多媒体、音频、蓝牙相关），在 `dockerfile` 的 `dnf install` 语句中加入对应 `-devel` 开发包。
   - 注意 Fedora 包名规则（例如 lzma 开发库为 `xz-devel`）。
3. **安全与权限保证**：
   - 保持 `git config --system --add safe.directory '*'` 与 `chmod -R a+rwX /flutter`，不得随意移除，以防用户在 CI/CD 或本地以非 root 身份挂载时遭遇权限中断。
4. **保持构建缓存干净**：
   - 任何 `dnf install` 命令后面均需接 `dnf clean all && rm -rf /var/cache/dnf`，控制镜像层体积。



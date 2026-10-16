# MouseInc.SettingsOCR

MouseInc 配置界面，以及使用 Windows 本地识别引擎的图片文字识别工具。

[![Build Status](https://github.com/Lichtung-cahm/MouseInc.SettingsOCR/actions/workflows/build-and-package.yml/badge.svg?branch=main)](https://github.com/Lichtung-cahm/MouseInc.SettingsOCR/actions/workflows/build-and-package.yml)

## 下载与运行

在 [Releases](https://github.com/Lichtung-cahm/MouseInc.SettingsOCR/releases) 下载：

- `MouseInc.Settings.zip`：离线设置界面，保持 ZIP 文件名，将它放在 MouseInc 2.13.0 或更新版本的 `MouseInc.exe` 旁边，不要解压这个 ZIP。设置窗口需要 WebView2 Runtime。
- `MouseInc.SettingsOCR-Windows-Portable.zip`（提供时）：完整便携包，解压后双击 `MouseInc.exe`，双击托盘图标打开设置；无需 Node.js、npm 或 Python。

本仓库编译的是设置界面，不能从这些前端源码编译出 MouseInc 主程序。便携包使用独立提供的上游主程序，来源、版本和校验值见包内 `UPSTREAM.txt`。请先退出其他 MouseInc 实例再运行新包。

便携包的 `OCR-Clipboard.cmd` 可以将剪贴板图片识别成文字：截图并复制图片后双击运行，再粘贴识别结果。它使用 Windows 10/11 的本地 OCR，无需 API key，不上传截图，也不会自动粘贴；需要已安装相应的 Windows OCR 语言。它独立于主程序内原有的在线 OCR 接口，不会自动改写已有热键和手势配置。

完整使用说明见 [portable/README.txt](portable/README.txt)。旧的 `scripts/fix-*.py` 是针对个人路径的维护脚本，请勿直接运行；它们不包含在便携包中。

## 简介

本项目基于 [shuax/MouseInc.Settings](https://github.com/shuax/MouseInc.Settings) 设置界面，依赖 MouseInc 主程序提供本地配置通道。

## 技术栈

- **Vue 3.5.x** - 渐进式 JavaScript 框架
- **Vite 8.x** - 前端构建工具
- **Element Plus 2.x** - 基于 Vue 3 的组件库
- **Vuex 4.x** - 状态管理
- **Vue Router 5.x** - 路由管理
- **Vue I18n 11.x** - 国际化支持

## 功能特性

- 🎨 自适应系统深色/浅色主题
- 📱 响应式现代化卡片设计
- 🌐 多语言支持（简体中文、繁体中文、英文）
- ⚡ 快速的热更新开发体验
- 🖱️ 鼠标手势配置
- ⌨️ 全局热键设置
- 🎯 触发角和边缘滚动配置
- 📋 快捷菜单和按键回显

## 开发环境

### 前置要求

- [Node.js](https://nodejs.org/) 22.13+ 或更新的受支持版本
- npm (随 Node.js 安装)

### 安装步骤

```bash
# 克隆仓库
git clone https://github.com/Lichtung-cahm/MouseInc.SettingsOCR.git
cd MouseInc.SettingsOCR

# 安装依赖
npm ci

# 启动开发服务器（自动打开浏览器）
npm run dev
```

### 调试模式

按住 **SHIFT** 键同时打开 MouseInc 设置，可以打开 localhost 开发版本进行调试。

## 构建命令

```bash
# 开发模式
npm run dev

# 生产构建
npm run build

# 预览生产构建
npm run preview
```

## 代码质量检查

项目集成了 ESLint 进行代码质量检查，帮助维护代码规范和发现潜在问题。

### 运行代码检查

```bash
# 检查代码质量
npm run lint

# 自动修复可修复的问题
npm run lint:fix
```

### ESLint 配置特点

- 基于 Vue 3 和 TypeScript 的最佳实践
- 允许开发环境使用 `console.log` 和 `debugger`
- 对未使用变量提供警告而非错误
- 支持以下划线开头的变量作为有意未使用的标识
- TypeScript 中 `any` 类型使用会给出警告提示

### 代码规范要点

- 使用 2 个空格缩进
- 优先使用单引号
- 组件采用 PascalCase 命名
- 变量和函数采用 camelCase 命名
- 未使用的变量建议添加下划线前缀（如 `_unusedVar`）

## 项目结构

```
src/
├── components/       # 可复用组件
├── view/            # 页面级组件
├── router/          # 路由配置
├── store/           # Vuex 状态管理
├── locale/          # 国际化文件
├── libs/            # 工具库
└── config/          # 配置文件
```

## CI/CD

推送到 main 分支时自动构建设置界面。新增 `Package Windows release` 工作流可手动构建离线包；推送 `v*` 标签会发布离线设置包及校验值。

本地先运行 `npm ci`、`npm run build`，再运行：

```powershell
# 只生成主程序可直接读取的离线 ZIP
./scripts/package-windows.ps1 -SettingsOnly

# 将你独立取得的 MouseInc 主程序与设置界面、本地 OCR 工具组装为便携包
./scripts/package-windows.ps1 -MouseIncExePath 'C:/path/to/MouseInc.exe'
```

输出位于 `artifacts/`。完整便携包的在线构建需要提供主程序的 HTTPS 直链和 SHA-256；主程序下载失败或校验失败会中止构建。发布流程不包含已有个人配置、日志和旧维护脚本。

## 许可证

上游设置界面见 [shuax/MouseInc.Settings](https://github.com/shuax/MouseInc.Settings)。MouseInc 主程序由其作者独立分发；本仓库不声明其源码开放，也不替上游授予新的使用或分发许可。

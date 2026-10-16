MouseInc.SettingsOCR Windows 便携版

使用方法
1. 将整个压缩包解压到有写入权限的文件夹。
2. 双击 MouseInc.exe 启动。若已有其他 MouseInc 实例，请先从其托盘菜单退出，再运行本目录中的程序。
3. 双击系统托盘的 MouseInc 图标打开设置。首次启动由主程序生成本目录的 MouseInc.json。
4. MouseInc.Settings.zip 是离线设置界面，请保留文件名并与 MouseInc.exe 放在同一目录，不要解压这个内层 ZIP。

本地图片文字识别
1. 使用截图工具将图片复制到剪贴板。
2. 双击 OCR-Clipboard.cmd。识别成功后，剪贴板变为文字，可在需要的位置粘贴。
3. 识别失败会显示原因，不会自动粘贴或上传截图。
本地 OCR 独立于 MouseInc 设置中原有的在线 OCR 接口；此包没有改写你现有软件的热键或手势配置。

运行要求
- Windows 10/11；本地 OCR 使用系统自带的 Windows PowerShell 5.1 和已安装的 Windows OCR 语言。
- 设置窗口需要 Microsoft Edge WebView2 Runtime。多数 Windows 10/11 已有该组件；缺少时可从微软官网下载：
  https://developer.microsoft.com/microsoft-edge/webview2/
- 如果提示没有 OCR 语言，在 Windows 的语言设置中安装所需语言及文字识别组件。
- 不需要 Node.js、npm 或 Python。

内容与来源
- MouseInc.exe 是独立的上游主程序，不是本项目从源码编译出的文件。具体来源和 SHA-256 见 UPSTREAM.txt。
- MouseInc.Settings.zip 由本仓库 Vue 设置界面源码构建。
- scripts/ocr-local.ps1 使用 Windows 本地 OCR，不依赖第三方识别接口。
- 此包不含个人 MouseInc.json、旧的固定 D 盘维护脚本、截图或调试日志。

更新现有安装
建议将新便携包解压到新目录试用。只更新设置界面时，可先退出 MouseInc，备份原文件，再将 MouseInc.Settings.zip 放入原主程序目录。
保留和备份自己的 MouseInc.json。请勿将个人配置文件上传到公开仓库。

项目：https://github.com/Lichtung-cahm/MouseInc.SettingsOCR
上游设置界面：https://github.com/shuax/MouseInc.Settings

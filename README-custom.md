# FlClash 自用 fork：在 GitHub Runner 上编译，永远跟上上游

仓库：https://github.com/MARYCOMPLEX/FlClash （fork 自 chen08209/FlClash）

## 这套东西长什么样

```
你的仓库
├─ lib/                     ← 上游原始代码，一行没改
├─ lib/custom/traffic_stats.dart   ← 你加的功能（新文件，不碰上游）
├─ scripts/apply_custom.py         ← 构建前把功能注入 main.dart
└─ .github/workflows/custom-build.yaml  ← 同步上游 + 构建 Windows
```

**关键设计：仓库里的上游代码保持原样**，自定义功能是"新文件 + 构建时注入"，
所以上游怎么改都不会冲突，`git merge upstream/main` 永远干净。

## 工作流做什么

`.github/workflows/custom-build.yaml`：

1. `checkout`（含 submodule）
2. 定时触发时，先 `git merge upstream/main` 再 `git push` —— **每天自动追上上游**
3. `python scripts/apply_custom.py` —— 把 `lib/custom/traffic_stats.dart` 接进 `main.dart`
4. Go 1.27.1 + Rust cache + Flutter 3.47.6（跟上游 build.yaml 完全一致）
5. `dart setup.dart windows --env stable -v` —— 上游自己的打包脚本
6. 产物上传为 artifact `flclash-windows-custom`

触发方式：

| 方式 | 效果 |
|---|---|
| 每天 03:00（北京时间）自动 | 同步上游 → 构建 |
| Actions 页面 → custom-build → Run workflow | 只构建，不同步 |

## 拿产物

GitHub → Actions → 最新一次 `custom-build` → Artifacts → `flclash-windows-custom`

## 现在加的功能

`lib/custom/traffic_stats.dart`：

- 监听内核推送的 `requestTraffic`（每条连接的 upload/download 增量）
  和 `request`（host / process / chains）
- 按 **日期 + 域名 + 进程 + 出口节点** 四级聚合
- 落盘 `homeDir/traffic_stats.json`，保留 90 天，每 15 秒刷一次
- 内置 HTTP 服务 `http://127.0.0.1:18999`，带完整可视化页面

打开 `http://127.0.0.1:18999` 就能看：今日/昨天/近7天/按天/进程/出口，可按任意列排序、导出 CSV。

## 以后加自己的功能怎么做

1. 新功能写成独立文件，比如 `lib/custom/xxx.dart`
2. 需要改上游文件时，锚点写进 `scripts/apply_custom.py`（跟现在注入 main.dart 一个套路）
3. commit push → 自动构建
4. 要调 UI 就改 `lib/views/...`，但记得**在注入脚本里改**，别直接改仓库里的上游文件，
   否则同步上游时会冲突

## 上游同步

- 定时任务已内置（每天 merge 一次）
- 也可以手动：仓库页面 → Sync fork → Update branch
- 冲突时 CI 会 `git merge --abort` 并继续用当前分支构建，不会把构建搞挂

## 需要注意

- 公开仓库的 Actions 免费，Windows runner 一次大约 20~30 分钟
- 上游 `build.yaml` 已在本仓库停用（它只认 `chen08209/FlClash` 这个仓库名），
  避免每次 push 都跑一堆无关 job
- Flutter 版本要跟着上游 `build.yaml` 里的 `FLUTTER_VERSION` 走，上游升级时改一行

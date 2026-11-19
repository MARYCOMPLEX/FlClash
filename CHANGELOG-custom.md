# 自定义功能 Changelog（fork 版本）

本文件只记录 **MARYCOMPLEX/FlClash 相对上游 chen08209/FlClash 加的私货**。
上游同步是每天自动 merge 的，所以这里不需要记录上游变更。

约定：**每次新增/修改自定义功能，必须在这里加一条**，空一格写清"改了什么、怎么用、
数据存在哪、上游基线变了要注意什么"。后续版本迭代继续往下追加。

---

## custom-1.1 — 2026-11-19

### 新增：内核 Hook（工具 → 内核 Hook）

**作用**：给"内核启动/重启"加可编程钩子。每次 FlClash 构建并下发内核配置时
（启动内核、重启内核、切换订阅、改配置、订阅自动更新），按顺序执行所有启用的 JS 脚本。

**调用点**：`lib/providers/actions/setup.dart` 里配置下发给内核之前
（`handleEvaluate` 的 profile 脚本之后），注入一行 `rawConfig = await applyCoreHooks(rawConfig);`。

**脚本约定**：

```javascript
// config = 即将下发的内核配置对象（和 config.yaml 同构）
// 改完必须 return 一个对象
if (!config.rules) config.rules = [];
const r = "DOMAIN,play.googleapis.com,REJECT";
if (config.rules.indexOf(r) < 0) config.rules.unshift(r);
return config;
```

- 引擎：FlClash 自带的 QuickJS（`lib/common/javascript.dart` 的 `handleEvaluate`），不依赖任何外部解释器
- 多个 hook 按 GUI 里的顺序串联执行，每个拿到的是上一个的输出
- 单个脚本抛错只写入执行结果并记日志，**不阻断内核启动**

**GUI**：设置 → 工具 → 内核 Hook。可新建 / 编辑脚本 / 启停 / 上移下移 / 删除，
列表上直接显示「上次 OK 12 ms」或「上次失败：<错误>」。

**存储**：`%APPDATA%\com.follow\clash\core_hooks.json`

**内置默认 hook**：`拦截 Google 遥测上报`

```javascript
if (!config.rules) config.rules = [];
const rule = "DOMAIN,play.googleapis.com,REJECT";
if (config.rules.indexOf(rule) < 0) config.rules.unshift(rule);
return config;
```

> 来历：Antigravity 的 `language_server.exe` 通过 Google Clearcut 往
> `https://play.googleapis.com/log` 上报，日志里累计 10 万次失败重试，
> 一天吃掉 341 MB 上传、只有 2.3 MB 下行。拦掉这个端点后上传归零，AI 功能不受影响。

### 新增：每日流量统计（工具 → 流量统计）

- 监听内核推送的 `requestTraffic`（每条连接的 upload/download 累计值），取差分后
  按 **日期 / 域名 / 进程 / 出口节点** 四级聚合
- 视图：今日域名、近 7 天、今日进程、今日出口，按流量排序带占比条
- 存储：`%APPDATA%\com.follow\clash\traffic_stats.json`，保留 90 天，每 5 秒落盘
- 附带本地网页版 `http://127.0.0.1:18999`（手机连同一 Wi-Fi 也能看）
- 切订阅、重启内核都不影响累计（统计挂在应用级，不挂 profile）

### 变更：构建产物

- `.github/workflows/custom-build.yaml` 现在同时产出
  - `flclash-windows-custom`：完整安装包（约 105 MB）
  - `flclash-hotfiles`：只有 `FlClash.exe` + `data\app.so` + `data\icudtl.dat`（约 7.6 MB）
    —— 就地升级用这个，下载快得多
- 每天 UTC 19:00（北京 03:00）自动 merge 上游并构建

### 注意 / 已知限制

- 内核 Hook 只在**配置真的下发**时执行；如果这次启动的配置和上次完全一样
  （md5 相同且没 force），FlClash 会跳过下发，hook 也就不会跑
- 外部直接改 `database.sqlite` 的 `profiles.overrides` 会被 FlClash 启动时覆盖回去，
  所以"补规则"这类需求应该写成 hook 脚本，不要再改库
- 上游若改了 `setup.dart` 里 `handleEvaluate` 那两行，`scripts/apply_custom.py` 的锚点
  会报错并让 CI 失败（不会静默跳过），届时按报错调整锚点即可

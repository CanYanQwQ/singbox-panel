# Sing-box 多用户与管理脚本（6.1.9-lowmem）

这是一个基于原版 Sing-box 逻辑的一键管理脚本，专为多用户管理场景设计，自编译版本支持 v2ray_api 流量统计。

**本分支**：在 v6.1.9 基础上适配 **128MB 内存**的小型 VPS，移除 Telegram Bot 模块，保留全部多用户管理、协议、路由、中转、WARP 与导出功能。详见下文「6.1.9-lowmem」一节。

**仓库**：https://github.com/CanYanQwQ/singbox-panel

## 快速开始

**root 用户一键安装：**

```bash
curl -fsSL https://raw.githubusercontent.com/CanYanQwQ/singbox-panel/main/sb.sh -o /root/sb.sh && bash /root/sb.sh
```

**非 root 用户：**

```bash
curl -fsSL https://raw.githubusercontent.com/CanYanQwQ/singbox-panel/main/sb.sh -o sb.sh && sudo bash sb.sh
```

**国内加速（raw 被墙或很慢时用这个）：**

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/CanYanQwQ/singbox-panel/main/sb.sh -o /root/sb.sh && bash /root/sb.sh
```

> **必须下载成文件再执行，不要用 `bash <(curl ...)` 或 `curl ... | bash`。**
> 脚本需要读取自身来安装快捷命令 `s`（见 `lib/80_installer.sh` 的 `resolve_current_script_file`）。管道方式下 `$0` 是 `/dev/fd/63` 指向的匿名管道，读完就没了，脚本无法复制自身，会导致快捷命令安装失败。
> 如果系统没有 curl，把 `curl -fsSL <url> -o 文件` 换成 `wget -qO 文件 <url>` 即可。

* **快捷命令**：安装完成后，在终端输入 `s` 即可唤出管理菜单。
* **避免冲突**：如果当前系统已安装官方版本的 sing-box，推荐先在菜单中执行“8. 卸载 sing-box”（保留数据），再执行“1. 安装/更新 sing-box”进行环境接管。
* **升级注意（6.0.9版本之前）**：定时任务结构有变（4 个 cron 合并为 2 个）。推荐先在菜单中执行 `8. 卸载 sing-box`（保留数据），再执行 `1. 安装/更新 sing-box`，让定时任务干净迁移。如果直接覆盖新脚本，进入 `2. 系统工具` 看到摘要里 `实时同步/日常维护：未安装` 提示后，进 `1. 安装/更新` 按提示补齐组件即可。

---

## 6.1.9：sing-box 1.14 适配与可靠性修复

需要 sing-box **1.14.0 或更新版本**，当前验证版本为 **1.14.2**。旧内核应先从安装/更新菜单升级，再使用管理功能。

- 远程规则集迁移到 `http_client`，保留自定义下载出站；默认拒绝改为末尾的 `action: reject`，不放开停用用户。
- 用户投影与路由重建减少重复子进程，已有凭证和顺序保持不变；4 节点 / 40 用户的 VPS 对照测试从 10.5 秒降至 1.0 秒。
- 修复 Shadowsocks UDP 端口冲突漏检、SS2022 相同双密钥导出遗漏，以及 WS 导出 early-data 字段层级。


- 更新内核前用候选二进制检查现有配置，原子替换后明确重启，并检查新进程和已启用的统计 API。失败恢复旧内核与配置；成功保留 `sing-box.bak` 和 `config.json.bak.upgrade`。
- 流量基线按进程代次和节点用户保存，菜单只合并本次修改的字段；同字段发生并发冲突时提示重新操作。
- 保留不同条件的路由规则；错过重置日后补执行最近应完成的账期。新用户或调整重置日先建立账期，不追溯清零。
- 配置未变化时不重启；需要应用运行配置时执行经过检查的重启，会短暂中断连接。
- 管理写入必须取得文件锁，安装流程会补齐 flock。当前发布架构为 Linux amd64/arm64；旧 Release 不再自动删除。

TG HTTPS/独立节点凭证仍需单独改造；现有公网明文 HTTP 和共享密钥不适合直接暴露于不受信任网络。流量仍是周期采样，进程异常退出前未采样的尾部流量无法恢复；外部短时间连续 HUP 也不能保证精确识别，建议使用脚本的服务操作。

## 6.1.9-lowmem：128MB 内存适配版

本分支针对 128MB 内存的小型 VPS 做了精简，**多用户管理、协议管理、路由、中转、WARP、导出等功能全部保留**。

* **移除 Telegram Bot 模块**（`lib/63_telegram_bot.sh`）。它常驻一个 Python 进程 + 每 3 分钟一次的任务轮询，是低内存机器上最大的非必要开销。移除后主菜单与用户管理菜单都不再出现 TG 入口。
* **内核内存上限**：systemd 单元新增 `Environment=GOMEMLIMIT=48MiB`、`GOGC=50` 与 `OOMScoreAdjust=-500`；OpenRC 的 init 脚本导出同样的 `GOMEMLIMIT` / `GOGC`。这是让 Go 运行时提前回收而非被内核 OOM 杀掉的关键，**若机器内存更大可把 `GOMEMLIMIT` 调到总内存的 40%~50%**。
* **定时任务降频**：`periodic-sync` 从每 3 分钟改为每 5 分钟（账期精度是天，5 分钟足够），减少高频 fork 完整 bash 带来的峰值内存。
* 从旧版本升级时，安装/卸载流程会自动清理遗留的 `sb.sh --tg-agent-sync` cron 与 `sb-tg-bot` 服务；`--tg-agent-sync` 入口保留为静默退出，避免升级瞬间掉进主菜单。
* 代码量从 10023 行降至 7562 行（减少 24.6%），函数数从 447 降至 384。

VPS 验收步骤见 [测试清单](docs/TESTING.md)。

开发验证：`bash tests/check.sh`。CI 在 Ubuntu、Alpine 运行回归，并编译 1.14.2 验证八种协议 TCP/UDP、停用与未授权用户、计费、中转、规则下载，以及独立 systemd 服务的升级回滚。实测范围与限制见 [验证结果](docs/VALIDATION-6.1.9.md)。

## 卸载说明

菜单中的 **`8. 卸载 sing-box`** 是保留数据的运行环境卸载：

* 会停止并移除 sing-box 服务。
* 会清理旧版遗留的 TG Bot 服务与定时任务（本版已无 TG 模块）。
* 默认保留 `/etc/sing-box`、`/etc/sing-box-manager`、日志、脚本和快捷命令，方便后续重新安装或恢复。

如需彻底清理脚本与相关配置，再手动执行：

```bash
rm -f /root/sb.sh
rm -f /usr/local/bin/s
rm -rf /etc/sing-box-manager
rm -rf /etc/sing-box
rm -rf /var/log/sing-box
rm -f /var/lock/singbox-manager.lock
```

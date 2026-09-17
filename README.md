# remote_driving：旧版 Fleet Monitor

本仓库对应 FSM 的 `status_uploader/to_fleetMonitor.py`。云端接收车端上报并推送给网页。

## 一键后台启动

在云端服务器进入本仓库目录：

```bash
bash start_services.sh
```

优先使用当前 `python3`（包括已激活的虚拟环境）；已有兼容的 `websockets` 就直接启动，不创建环境或下载依赖。
当前 Python 不满足要求时，再复用项目里已有且依赖完整的 `.venv`。
只有当前 Python 不满足要求、并且项目中没有 `.venv` 时，才新建项目环境并安装依赖。

脚本不会给系统 Python 或任何已有环境安装、升级包，也不会覆盖或重建已有 `.venv`。
如果已有 `.venv` 残缺或不兼容，且当前 Python 也不可用，会保留原目录并报错；
可以先激活已有的兼容 Python 环境后再运行。依赖要求见 `requirements.txt`。

仅新建环境时需要 venv；若提示缺少它，在 Ubuntu/Debian 上先执行
`sudo apt install python3-venv`。

启动成功后会打印两个服务的 PID。关闭 SSH 不影响运行；服务器重启后需要重新启动。
再次执行相同命令会重启本仓库的两个服务；其他程序占用端口时会报错，不会杀掉其他程序。

| 用途 | 地址 |
| --- | --- |
| 网页入口 | `http://103.172.135.10:8003/fleet_monitor.html` |
| 车端状态上传 / 网页 WebSocket | `ws://103.172.135.10:8004` |

网页通过所在服务器的 `8004` 接收状态；直接打开 HTML 文件时默认连接 `103.172.135.10:8004`。
车端 `to_fleetMonitor.py` 的连接地址也需使用上述新 IP。
云平台安全组和主机防火墙需允许客户端访问 `8003/TCP` 和 `8004/TCP`。

## 查看和停止

```bash
bash start_services.sh status
bash start_services.sh logs
bash start_services.sh stop
```

日志保存在 `logs/http.log` 和 `logs/ws.log`，PID 文件在 `.run/`。
每个连接首次合法上报会记录 `收到车端数据`；网页收到车辆状态后更新。
没有车端上报时不会生成模拟车辆数据。

## 服务文件

- `start_services.sh`：后台启动网页与真实数据中转。
- `cloud_ws_server.py`：`8004` 端口的旧协议中转，接受 `{车辆ID: {状态字段}}`。
- `fleet_monitor.html`：实车监控主页面。
- `ws_server.py`：原有的本地模拟数据程序（`localhost:8888`），不由云端启动脚本运行。
- 其他 HTML 和 `script.js` 保留原有演示用途。

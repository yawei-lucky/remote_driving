#!/usr/bin/env bash
# Legacy Fleet Monitor: HTTP 8003 + vehicle-state WebSocket 8004.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$ROOT"
mkdir -p logs .run
ACTION="${1:-start}"

owned_pid() {
  local service="$1" pid args
  [[ -f ".run/$service.pid" ]] || return 1
  read -r pid < ".run/$service.pid"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  [[ "$(readlink -f "/proc/$pid/cwd" 2>/dev/null)" == "$ROOT" ]] || return 1
  args="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)" || return 1
  case "$service:$args" in
    http:*" -m http.server 8003 --bind 0.0.0.0 "*) ;;
    ws:*" -u cloud_ws_server.py "*) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$pid"
}

stop_service() {
  local service="$1" pid
  if pid="$(owned_pid "$service")"; then
    echo "停止 $service，PID=$pid"
    kill "$pid" 2>/dev/null || true
    for _ in {1..50}; do
      if ! owned_pid "$service" >/dev/null; then break; fi
      sleep 0.1
    done
    if owned_pid "$service" >/dev/null; then
      echo "错误：$service 未退出，请检查 logs/$service.log。" >&2
      return 1
    fi
  fi
  rm -f ".run/$service.pid"
}

stop_services() {
  local failed=0
  stop_service http || failed=1
  stop_service ws || failed=1
  return "$failed"
}

listening() {
  ss -H -ltn "sport = :$1" | grep -q .
}

case "$ACTION" in
  logs) exec tail -n 50 -F logs/http.log logs/ws.log ;;
  status)
    failed=0
    for service in http ws; do
      if pid="$(owned_pid "$service")"; then
        echo "$service: 运行中，PID=$pid，日志=$ROOT/logs/$service.log"
      else
        echo "$service: 未运行"
        failed=1
      fi
    done
    exit "$failed"
    ;;
  start|restart|stop) ;;
  *) echo "用法：bash start_services.sh [start|restart|status|logs|stop]" >&2; exit 2 ;;
esac

for command in flock readlink tr; do
  command -v "$command" >/dev/null || { echo "缺少命令：$command" >&2; exit 1; }
done
exec 9>.run/services.lock
flock -n 9 || { echo "另一个启动/停止操作正在执行，请稍后重试。" >&2; exit 1; }

if [[ "$ACTION" == stop ]]; then
  stop_services
  echo "云端服务已停止。"
  exit 0
fi

for command in python3 nohup ss; do
  command -v "$command" >/dev/null || { echo "缺少命令：$command" >&2; exit 1; }
done
[[ -f cloud_ws_server.py && -f fleet_monitor.html ]] || {
  echo "缺少 cloud_ws_server.py 或 fleet_monitor.html，请先更新完整仓库。" >&2
  exit 1
}

PYTHON="$ROOT/.venv/bin/python"
if [[ ! -x "$PYTHON" ]]; then
  echo "首次启动：创建 Python 虚拟环境 .venv"
  python3 -m venv .venv || {
    echo "无法创建虚拟环境；Ubuntu/Debian 请先安装：sudo apt install python3-venv" >&2
    exit 1
  }
fi
if ! "$PYTHON" -c 'import websockets; assert 14 <= int(websockets.__version__.split(".")[0]) < 18' >/dev/null 2>&1; then
  echo "安装云端依赖；已满足要求的依赖会跳过。"
  "$PYTHON" -m pip install -r requirements.txt
fi

echo "[cloud] host=$(hostname) directory=$ROOT branch=$(git branch --show-current 2>/dev/null || echo unknown)"
echo "[cloud] HTTP=8003 WebSocket=8004"
stop_services
for port in 8003 8004; do
  if listening "$port"; then
    echo "错误：端口 $port 已被其他程序占用，未启动；请先确认占用程序。" >&2
    ss -ltnp "sport = :$port" >&2
    exit 1
  fi
done

trap 'stop_services; exit 130' INT TERM
nohup "$PYTHON" -u -m http.server 8003 --bind 0.0.0.0 >>logs/http.log 2>&1 </dev/null 9>&- &
echo "$!" > .run/http.pid
nohup "$PYTHON" -u cloud_ws_server.py >>logs/ws.log 2>&1 </dev/null 9>&- &
echo "$!" > .run/ws.pid

ready=0
for _ in {1..50}; do
  if owned_pid http >/dev/null && owned_pid ws >/dev/null &&
     listening 8003 && listening 8004; then ready=1; break; fi
  sleep 0.1
done
if [[ "$ready" != 1 ]]; then
  echo "错误：服务启动失败，停止本次启动的进程。" >&2
  stop_services || true
  tail -n 20 logs/http.log logs/ws.log >&2
  exit 1
fi
trap - INT TERM
echo "后台启动成功：HTTP PID=$(owned_pid http)，WebSocket PID=$(owned_pid ws)"
echo "网页：http://<云端IP>:8003/fleet_monitor.html"
echo "车端：ws://<云端IP>:8004"
echo "状态：bash start_services.sh status"
echo "日志：bash start_services.sh logs"
echo "停止：bash start_services.sh stop"

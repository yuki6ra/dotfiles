#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
モック Zabbix API サーバー（api_jsonrpc.php 相当）。

実 Zabbix が無い環境で CLI の通しテスト（HTTP 経路 + dry-run + レポート出力）を
行うために使う。tests/test_zbx_bulk_host.py の FakeAPI をそのまま HTTP で公開する。

    python3 tests/mock_zabbix_server.py 18080 &
    export ZABBIX_URL=http://127.0.0.1:18080
    export ZABBIX_TOKEN=dummy
    ./zbx_bulk_host.py apply samples/hosts.example.csv --create-groups
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from test_zbx_bulk_host import FakeAPI  # noqa: E402
import zbx_bulk_host as z               # noqa: E402

STATE = FakeAPI(
    version=os.environ.get("MOCK_ZABBIX_VERSION", "7.0.9"),
    groups={"Linux servers": "4", "Network devices": "5", "Zabbix servers": "6"},
    templates={
        "Linux by Zabbix agent": "10001",
        "MySQL by Zabbix agent": "10002",
        "Network Generic Device by SNMP": "10003",
        "HTTP Service": "10004",
    },
    proxies={"proxy-osaka": "20001"},
    # MOCK_FAIL_HOSTS="a,b" で特定ホストの host.create を必ず失敗させる（切り分け検証用）
    fail_hosts=[h for h in os.environ.get("MOCK_FAIL_HOSTS", "").split(",") if h],
)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length).decode("utf-8"))
        rid = body.get("id")
        try:
            result = STATE.call(body["method"], body.get("params"))
            payload = {"jsonrpc": "2.0", "result": result, "id": rid}
        except z.ZabbixAPIError as exc:
            payload = {"jsonrpc": "2.0", "id": rid,
                       "error": {"code": exc.code or -32602,
                                 "message": "Invalid params.", "data": exc.data or str(exc)}}
        except Exception as exc:  # noqa: BLE001
            payload = {"jsonrpc": "2.0", "id": rid,
                       "error": {"code": -32500, "message": "Application error.",
                                 "data": str(exc)}}
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self, fmt, *args):   # 静かにする
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18080
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()

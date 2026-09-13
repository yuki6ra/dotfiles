#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
zbx_bulk_host.py — Zabbix ホスト一括登録／更新ツール

CSV または YAML で書いたホスト定義を Zabbix API へ冪等に流し込む。

設計の要点（docs/02_design.md 参照）
  1. 認証は UI 発行の API トークン（Bearer）。パスワードを持たない
  2. ホストグループ → ホストの順で作成する
  3. グループ／テンプレート名 → ID の変換は「入力全体を 1 リクエストで一括解決」
  4. host.get で既存突合し CREATE / UPDATE / NOOP を判定（再実行可能）
  5. host.create はチャンク配列投入。失敗チャンクは 1 件ずつ再投入して切り分ける
  6. 書き込み前に全件バリデーション（部分適用を作らない）

使い方:
    export ZABBIX_URL=https://zabbix.example.jp
    export ZABBIX_TOKEN=xxxxxxxx
    ./zbx_bulk_host.py plan  hosts.csv --create-groups
    ./zbx_bulk_host.py apply hosts.csv --create-groups --report apply.json
"""

from __future__ import annotations

import argparse
import csv
import getpass
import io
import ipaddress
import json
import os
import re
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

try:  # 実行時のみ必要（単体テストは requests 無しでも通る）
    import requests
except ImportError:  # pragma: no cover
    requests = None

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None

__version__ = "1.0.0"

# --------------------------------------------------------------------------
# 定数
# --------------------------------------------------------------------------

IFACE_TYPES = {"agent": 1, "snmp": 2, "ipmi": 3, "jmx": 4, "1": 1, "2": 2, "3": 3, "4": 4}
IFACE_TYPE_NAMES = {1: "agent", 2: "snmp", 3: "ipmi", 4: "jmx"}
DEFAULT_PORTS = {1: "10050", 2: "161", 3: "623", 4: "12345"}

STATUS_MAP = {"enabled": 0, "enable": 0, "monitored": 0, "0": 0,
              "disabled": 1, "disable": 1, "unmonitored": 1, "1": 1}
INVENTORY_MAP = {"disabled": -1, "manual": 0, "automatic": 1, "auto": 1,
                 "-1": -1, "0": 0, "1": 1}
MACRO_TYPE_MAP = {"text": 0, "secret": 1, "vault": 2, "0": 0, "1": 1, "2": 2}

MACRO_RE = re.compile(r"^\{\$[A-Z0-9_.]+(:.*)?\}$")
MACRO_PLACEHOLDER = re.compile(r"^\{\$[A-Z0-9_.]+(:.*)?\}$")
SECRET_MASK = "***"

CSV_COLUMNS = {
    "host", "name", "groups", "templates",
    "interface_type", "interface_useip", "interface_ip", "interface_dns",
    "interface_port", "interface_main",
    "snmp_version", "snmp_community", "snmp_bulk",
    "tags", "macros", "status", "description", "inventory_mode",
    "proxy", "proxy_group",
}

EXIT_OK = 0
EXIT_APPLY_FAILED = 1
EXIT_VALIDATION = 2
EXIT_CONNECT = 3
EXIT_INTERRUPTED = 130


# --------------------------------------------------------------------------
# 例外
# --------------------------------------------------------------------------

class ZabbixAPIError(Exception):
    """Zabbix API がエラーレスポンスを返した（再試行しない）。"""

    def __init__(self, message: str, code: Optional[int] = None, data: str = ""):
        self.code = code
        self.data = data
        detail = f"{message} {data}".strip() if data else message
        super().__init__(detail)


class ZabbixAPITransportError(Exception):
    """接続不能・タイムアウト・5xx（再試行後も失敗）。"""


class InputError(Exception):
    """入力ファイルの読み込み失敗。"""


# --------------------------------------------------------------------------
# API クライアント
# --------------------------------------------------------------------------

class ZabbixAPI:
    """requests のみに依存する最小の JSON-RPC 2.0 クライアント。"""

    def __init__(self, url: str, token: Optional[str] = None,
                 user: Optional[str] = None, password: Optional[str] = None,
                 timeout: int = 30, verify: bool = True, retries: int = 3,
                 sleep: float = 0.0, verbose: bool = False):
        if requests is None:  # pragma: no cover
            raise RuntimeError("requests が必要です: pip install requests")
        self.url = self._normalize_url(url)
        self.token = token
        self.user = user
        self.password = password
        self.timeout = timeout
        self.verify = verify
        self.retries = retries
        self.sleep = sleep
        self.verbose = verbose
        self.version = ""
        self.major = 0
        self.minor = 0
        self.session_login = False   # user.login で取得したセッションかどうか
        self.call_count = 0
        self._req_id = 0
        self.session = requests.Session()

    # -- 公開 API ----------------------------------------------------------

    def connect(self) -> str:
        """バージョン検出と（必要なら）ログインを行う。"""
        self.version = str(self.call("apiinfo.version", {}, auth=False))
        parts = self.version.split(".")
        self.major = int(parts[0]) if parts and parts[0].isdigit() else 0
        self.minor = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0

        if not self.token:
            if not (self.user and self.password):
                raise ZabbixAPIError(
                    "認証情報がありません。ZABBIX_TOKEN もしくは --user + ZABBIX_PASSWORD を指定してください。")
            # 6.0 以降はパラメータ名が user → username に変わっている
            key = "username" if (self.major, self.minor) >= (6, 0) else "user"
            result = self.call("user.login",
                               {key: self.user, "password": self.password},
                               auth=False)
            # userData 指定なしなら文字列（セッション ID）が返る
            self.token = result["sessionid"] if isinstance(result, dict) else result
            self.session_login = True
        # 認証確認（権限不足やトークン失効をここで検出する）
        self.call("host.get", {"countOutput": True, "limit": 1})
        return self.version

    def close(self) -> None:
        """user.login で取得したセッションを無効化する（API トークンには触らない）。"""
        if not self.session_login or not self.token:
            return
        try:
            self.call("user.logout", {})
        except (ZabbixAPIError, ZabbixAPITransportError) as exc:
            _log("警告: user.logout に失敗しました（セッションは有効期限まで残ります）: %s" % exc)
        finally:
            self.token = None
            self.session_login = False

    @property
    def auth_method(self) -> str:
        if self.session_login:
            return "user.login(session)"
        return "api-token"

    @property
    def use_bearer(self) -> bool:
        """Authorization: Bearer が使えるか（6.4 以降）。"""
        return (self.major, self.minor) >= (6, 4)

    @property
    def supports_monitored_by(self) -> bool:
        """monitored_by / proxyid 方式か（7.0 以降）。"""
        return self.major >= 7

    @property
    def select_groups_key(self) -> str:
        return "selectHostGroups" if (self.major, self.minor) >= (6, 2) else "selectGroups"

    def call(self, method: str, params: Any = None, auth: bool = True) -> Any:
        self._req_id += 1
        self.call_count += 1
        payload: Dict[str, Any] = {
            "jsonrpc": "2.0",
            "method": method,
            "params": {} if params is None else params,
            "id": self._req_id,
        }
        headers = {"Content-Type": "application/json-rpc"}
        if auth and self.token:
            if self.use_bearer:
                headers["Authorization"] = "Bearer %s" % self.token
            else:
                payload["auth"] = self.token

        if self.verbose:
            _log("API -> %s %s" % (method, _brief(payload["params"])))

        last: Optional[str] = None
        for attempt in range(self.retries + 1):
            if self.sleep and self.call_count > 1:
                time.sleep(self.sleep)
            try:
                resp = self.session.post(
                    self.url,
                    data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                    headers=headers, timeout=self.timeout, verify=self.verify)
            except Exception as exc:  # requests.RequestException 相当
                last = "transport: %s" % exc
            else:
                if resp.status_code >= 500:
                    last = "HTTP %d" % resp.status_code
                elif resp.status_code >= 400:
                    raise ZabbixAPIError("HTTP %d: %s" % (resp.status_code, resp.text[:300]))
                else:
                    try:
                        body = resp.json()
                    except ValueError:
                        raise ZabbixAPIError(
                            "JSON でないレスポンス: %s" % resp.text[:300])
                    if "error" in body:
                        err = body["error"]
                        raise ZabbixAPIError(err.get("message", "API error"),
                                             err.get("code"), err.get("data", ""))
                    if self.verbose:
                        _log("API <- %s ok" % method)
                    return body.get("result")
            if attempt < self.retries:
                backoff = 2 ** attempt
                _log("再試行 %d/%d (%s) — %ds 待機" % (attempt + 1, self.retries, last, backoff))
                time.sleep(backoff)
        raise ZabbixAPITransportError("%s の呼び出しに失敗しました: %s" % (method, last))

    # -- 内部 --------------------------------------------------------------

    @staticmethod
    def _normalize_url(url: str) -> str:
        url = (url or "").strip()
        if not url:
            raise ZabbixAPIError("Zabbix URL が指定されていません（--url / ZABBIX_URL）")
        if not url.startswith(("http://", "https://")):
            url = "https://" + url
        if url.endswith("api_jsonrpc.php"):
            return url
        return url.rstrip("/") + "/api_jsonrpc.php"

    def __repr__(self) -> str:  # トークンを絶対に出さない
        return "<ZabbixAPI url=%s version=%s token=%s>" % (
            self.url, self.version or "?", SECRET_MASK if self.token else None)


# --------------------------------------------------------------------------
# データモデル
# --------------------------------------------------------------------------

@dataclass
class InterfaceSpec:
    type: int = 1
    main: int = 1
    useip: int = 1
    ip: str = ""
    dns: str = ""
    port: str = ""
    details: Dict[str, Any] = field(default_factory=dict)

    def to_api(self) -> Dict[str, Any]:
        obj: Dict[str, Any] = {
            "type": self.type, "main": self.main, "useip": self.useip,
            "ip": self.ip, "dns": self.dns,
            "port": self.port or DEFAULT_PORTS.get(self.type, "10050"),
        }
        if self.type == 2:
            details = dict(self.details or {})
            details.setdefault("version", 2)
            details.setdefault("community", "{$SNMP_COMMUNITY}")
            details.setdefault("bulk", 1)
            obj["details"] = details
        return obj

    def key(self) -> Tuple[int, int]:
        return (self.type, self.main)


@dataclass
class HostSpec:
    host: str = ""
    name: str = ""
    groups: List[str] = field(default_factory=list)
    templates: List[str] = field(default_factory=list)
    interfaces: List[InterfaceSpec] = field(default_factory=list)
    tags: List[Dict[str, str]] = field(default_factory=list)
    macros: List[Dict[str, Any]] = field(default_factory=list)
    status: int = 0
    description: str = ""
    inventory_mode: Optional[int] = None
    proxy: Optional[str] = None
    proxy_group: Optional[str] = None
    source: str = ""

    @property
    def visible_name(self) -> str:
        return self.name or self.host


@dataclass
class Plan:
    creates: List[Tuple[HostSpec, Dict[str, Any]]] = field(default_factory=list)
    updates: List[Tuple[HostSpec, Dict[str, Any], Dict[str, Any]]] = field(default_factory=list)
    noops: List[Tuple[HostSpec, str]] = field(default_factory=list)


# --------------------------------------------------------------------------
# 入力ローダ
# --------------------------------------------------------------------------

def _split_list(value: Any) -> List[str]:
    """`;` 区切りの文字列をリストにする（記事 A の区切り文字方針）。"""
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return [str(v).strip() for v in value if str(v).strip()]
    return [part.strip() for part in str(value).split(";") if part.strip()]


def _split_pairs(value: Any) -> List[Tuple[str, str]]:
    """`k=v;k=v` 形式を [(k, v), ...] にする。"""
    pairs: List[Tuple[str, str]] = []
    for item in _split_list(value):
        if "=" in item:
            k, v = item.split("=", 1)
            pairs.append((k.strip(), v.strip()))
        else:
            pairs.append((item, ""))
    return pairs


def _dedup(items: Iterable[str]) -> List[str]:
    seen, out = set(), []
    for it in items:
        if it not in seen:
            seen.add(it)
            out.append(it)
    return out


def _as_int_flag(value: Any, default: int) -> int:
    if value is None or str(value).strip() == "":
        return default
    text = str(value).strip().lower()
    if text in ("1", "true", "yes", "y", "on"):
        return 1
    if text in ("0", "false", "no", "n", "off"):
        return 0
    raise ValueError("0/1 で指定してください: %r" % value)


def _parse_iface_type(value: Any, default: int = 1) -> int:
    if value is None or str(value).strip() == "":
        return default
    key = str(value).strip().lower()
    if key not in IFACE_TYPES:
        raise ValueError("インターフェース種別が不正です: %r（agent/snmp/ipmi/jmx）" % value)
    return IFACE_TYPES[key]


def _parse_status(value: Any, default: int = 0) -> int:
    if value is None or str(value).strip() == "":
        return default
    key = str(value).strip().lower()
    if key not in STATUS_MAP:
        raise ValueError("status が不正です: %r（enabled/disabled）" % value)
    return STATUS_MAP[key]


def _parse_inventory(value: Any) -> Optional[int]:
    if value is None or str(value).strip() == "":
        return None
    key = str(value).strip().lower()
    if key not in INVENTORY_MAP:
        raise ValueError("inventory_mode が不正です: %r（disabled/manual/automatic）" % value)
    return INVENTORY_MAP[key]


def _parse_macro_type(value: Any) -> int:
    if value is None or str(value).strip() == "":
        return 0
    key = str(value).strip().lower()
    if key not in MACRO_TYPE_MAP:
        raise ValueError("マクロ種別が不正です: %r（text/secret/vault）" % value)
    return MACRO_TYPE_MAP[key]


def _iface_from_dict(data: Dict[str, Any]) -> InterfaceSpec:
    itype = _parse_iface_type(data.get("type"), 1)
    details = dict(data.get("details") or {})
    for src, dst in (("snmp_version", "version"), ("community", "community"),
                     ("snmp_community", "community"), ("bulk", "bulk"),
                     ("snmp_bulk", "bulk"), ("version", "version")):
        if data.get(src) not in (None, ""):
            details[dst] = data[src]
    if "version" in details:
        details["version"] = int(details["version"])
    if "bulk" in details:
        details["bulk"] = _as_int_flag(details["bulk"], 1)
    return InterfaceSpec(
        type=itype,
        main=_as_int_flag(data.get("main"), 1),
        useip=_as_int_flag(data.get("useip"), 1),
        ip=str(data.get("ip") or "").strip(),
        dns=str(data.get("dns") or "").strip(),
        port=str(data.get("port") or DEFAULT_PORTS.get(itype, "10050")).strip(),
        details=details if itype == 2 else {},
    )


def _spec_from_row(row: Dict[str, Any], source: str) -> HostSpec:
    """CSV の 1 行を HostSpec に変換する。"""
    get = lambda k: (row.get(k) or "").strip() if isinstance(row.get(k), str) else row.get(k)

    iface_data = {
        "type": get("interface_type"),
        "main": get("interface_main") or 1,
        "useip": get("interface_useip"),
        "ip": get("interface_ip"),
        "dns": get("interface_dns"),
        "port": get("interface_port"),
        "snmp_version": get("snmp_version"),
        "snmp_community": get("snmp_community"),
        "snmp_bulk": get("snmp_bulk"),
    }
    has_iface = any(iface_data.get(k) for k in
                    ("type", "ip", "dns", "port", "snmp_version", "snmp_community"))
    interfaces = [_iface_from_dict(iface_data)] if has_iface else []

    tags = [{"tag": k, "value": v} for k, v in _split_pairs(get("tags"))]
    macros = [{"macro": k, "value": v, "type": 0} for k, v in _split_pairs(get("macros"))]

    return HostSpec(
        host=get("host") or "",
        name=get("name") or "",
        groups=_dedup(_split_list(get("groups"))),
        templates=_dedup(_split_list(get("templates"))),
        interfaces=interfaces,
        tags=tags,
        macros=macros,
        status=_parse_status(get("status")),
        description=get("description") or "",
        inventory_mode=_parse_inventory(get("inventory_mode")),
        proxy=get("proxy") or None,
        proxy_group=get("proxy_group") or None,
        source=source,
    )


def _load_csv(path: str) -> Tuple[List[HostSpec], List[str], List[str]]:
    specs: List[HostSpec] = []
    errors: List[str] = []
    warnings: List[str] = []
    label = os.path.basename(path)
    # utf-8-sig: Excel が付ける BOM を吸収する
    with open(path, "r", encoding="utf-8-sig", newline="") as fh:
        raw_lines = fh.read().splitlines(True)

    # ヘッダ行より前のコメント（# 始まり）も許容するため、先に落としておく。
    # 元ファイルの行番号はエラー報告のために保持する。
    kept: List[Tuple[int, str]] = [
        (no, line) for no, line in enumerate(raw_lines, start=1)
        if not line.lstrip().startswith("#")
    ]
    if not kept:
        raise InputError("%s: ヘッダ行が読めません" % label)
    linenos = [no for no, _ in kept[1:]]           # データ行の元行番号
    reader = csv.DictReader(io.StringIO("".join(line for _, line in kept)))
    fields = [f for f in (reader.fieldnames or []) if f]
    if not fields:
        raise InputError("%s: ヘッダ行が読めません" % label)
    if "host" not in fields:
        raise InputError("%s: 必須列 'host' がありません（ヘッダ: %s）"
                         % (label, ", ".join(fields)))
    unknown = [f for f in fields if f not in CSV_COLUMNS]
    if unknown:
        warnings.append("%s: 未知の列を無視します: %s" % (label, ", ".join(unknown)))

    for idx, row in enumerate(reader):
        values = [v for v in row.values() if isinstance(v, str)]
        if not any(v.strip() for v in values):
            continue
        lineno = linenos[idx] if idx < len(linenos) else idx + 2
        source = "%s:%d" % (label, lineno)
        try:
            specs.append(_spec_from_row(row, source))
        except ValueError as exc:
            errors.append("%s: %s" % (source, exc))
    return specs, errors, warnings


def _merge_interfaces(defaults: List[Dict[str, Any]],
                      overrides: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    ホスト側のインターフェース定義で defaults を置き換える。
    ただし省略されたキーは「同じ type の defaults」から引き継ぐ
    （defaults で type/port を、ホスト側で ip だけ書く運用を成立させる）。
    """
    if not overrides:
        return [dict(d) for d in defaults]
    by_type: Dict[int, Dict[str, Any]] = {}
    for d in defaults:
        try:
            by_type[_parse_iface_type(d.get("type"), 1)] = d
        except ValueError:
            continue
    merged: List[Dict[str, Any]] = []
    for ov in overrides:
        itype = _parse_iface_type(ov["type"]) if ov.get("type") else None
        fallback = defaults[0] if defaults else {}
        base = dict(by_type.get(itype, fallback) if itype is not None else fallback)
        base.update({k: v for k, v in ov.items() if v is not None})
        merged.append(base)
    return merged


def _merge_tags(defaults: List[Dict[str, str]],
                overrides: List[Dict[str, str]]) -> List[Dict[str, str]]:
    """
    タグをマージする。Zabbix のタグは同名で複数値を持てるため、
    「ホスト側が同じタグ名を書いたら、その名前については defaults を置き換える」
    という規則にする（env=prod を env=staging で上書きできるようにするため）。
    """
    overridden = {str(t.get("tag", "")) for t in overrides}
    merged = [dict(t) for t in defaults if str(t.get("tag", "")) not in overridden]
    merged += [dict(t) for t in overrides]
    out: List[Dict[str, str]] = []
    seen = set()
    for t in merged:
        ident = (str(t.get("tag", "")), str(t.get("value", "") or ""))
        if ident not in seen:
            seen.add(ident)
            out.append(t)
    return out


def _merge_macros(defaults: List[Dict[str, Any]],
                  overrides: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """マクロはマクロ名で一意。ホスト側の指定が defaults を上書きする。"""
    merged: Dict[str, Dict[str, Any]] = {}
    for item in list(defaults) + list(overrides):
        merged[str(item.get("macro", ""))] = dict(item)
    return list(merged.values())


def _load_yaml(path: str) -> Tuple[List[HostSpec], List[str], List[str]]:
    if yaml is None:
        raise InputError("YAML 入力には PyYAML が必要です: pip install PyYAML")
    label = os.path.basename(path)
    with open(path, "r", encoding="utf-8") as fh:
        doc = yaml.safe_load(fh) or {}
    if not isinstance(doc, dict):
        raise InputError("%s: トップレベルはマッピングにしてください" % label)
    defaults = doc.get("defaults") or {}
    hosts = doc.get("hosts") or []
    if not isinstance(hosts, list):
        raise InputError("%s: hosts はリストにしてください" % label)

    specs: List[HostSpec] = []
    errors: List[str] = []
    for idx, raw in enumerate(hosts, start=1):
        source = "%s#hosts[%d]" % (label, idx)
        if not isinstance(raw, dict):
            errors.append("%s: マッピングにしてください" % source)
            continue
        try:
            iface_dicts = _merge_interfaces(defaults.get("interfaces") or [],
                                            raw.get("interfaces") or [])
            tags = _merge_tags(_normalize_tags(defaults.get("tags")),
                               _normalize_tags(raw.get("tags")))
            macros = _merge_macros(_normalize_macros(defaults.get("macros")),
                                   _normalize_macros(raw.get("macros")))
            pick = lambda k, dflt=None: raw.get(k, defaults.get(k, dflt))
            specs.append(HostSpec(
                host=str(raw.get("host") or "").strip(),
                name=str(raw.get("name") or "").strip(),
                groups=_dedup(_split_list(defaults.get("groups")) + _split_list(raw.get("groups"))),
                templates=_dedup(_split_list(defaults.get("templates"))
                                 + _split_list(raw.get("templates"))),
                interfaces=[_iface_from_dict(d) for d in iface_dicts],
                tags=tags,
                macros=macros,
                status=_parse_status(pick("status")),
                description=str(pick("description", "") or ""),
                inventory_mode=_parse_inventory(pick("inventory_mode")),
                proxy=(str(pick("proxy")).strip() or None) if pick("proxy") else None,
                proxy_group=(str(pick("proxy_group")).strip() or None) if pick("proxy_group") else None,
                source=source,
            ))
        except ValueError as exc:
            errors.append("%s: %s" % (source, exc))
    return specs, errors, []


def _normalize_tags(raw: Any) -> List[Dict[str, str]]:
    out: List[Dict[str, str]] = []
    if not raw:
        return out
    if isinstance(raw, dict):
        raw = [{"tag": k, "value": v} for k, v in raw.items()]
    for item in raw:
        if isinstance(item, str):
            k, _, v = item.partition("=")
            out.append({"tag": k.strip(), "value": v.strip()})
        else:
            out.append({"tag": str(item.get("tag", "")).strip(),
                        "value": str(item.get("value", "") or "")})
    return out


def _normalize_macros(raw: Any) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    if not raw:
        return out
    if isinstance(raw, dict):
        raw = [{"macro": k, "value": v} for k, v in raw.items()]
    for item in raw:
        if isinstance(item, str):
            k, _, v = item.partition("=")
            out.append({"macro": k.strip(), "value": v.strip(), "type": 0})
        else:
            out.append({
                "macro": str(item.get("macro", "")).strip(),
                "value": str(item.get("value", "") if item.get("value") is not None else ""),
                "type": _parse_macro_type(item.get("type")),
                "description": str(item.get("description", "") or ""),
            })
    return out


def load_specs(paths: Sequence[str]) -> Tuple[List[HostSpec], List[str], List[str]]:
    specs: List[HostSpec] = []
    errors: List[str] = []
    warnings: List[str] = []
    for path in paths:
        if not os.path.isfile(path):
            errors.append("入力ファイルがありません: %s" % path)
            continue
        ext = os.path.splitext(path)[1].lower()
        if ext in (".yaml", ".yml"):
            s, e, w = _load_yaml(path)
        elif ext in (".csv", ".tsv", ".txt"):
            s, e, w = _load_csv(path)
        else:
            errors.append("対応していない拡張子です（.csv / .yaml）: %s" % path)
            continue
        specs.extend(s)
        errors.extend(e)
        warnings.extend(w)
    return specs, errors, warnings


# --------------------------------------------------------------------------
# バリデーション
# --------------------------------------------------------------------------

def _valid_address(value: str) -> bool:
    if MACRO_PLACEHOLDER.match(value):
        return True
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return False


def validate_specs(specs: Sequence[HostSpec]) -> List[str]:
    """書き込み前に全件検査してエラーを列挙する（部分適用を作らないため）。"""
    errors: List[str] = []
    seen: Dict[str, str] = {}

    for spec in specs:
        src = spec.source or spec.host or "?"
        if not spec.host:
            errors.append("%s: host（技術名）は必須です" % src)
            continue
        if spec.host in seen:
            errors.append("%s: host が入力内で重複しています（%s と重複）: %s"
                          % (src, seen[spec.host], spec.host))
        else:
            seen[spec.host] = src
        if not spec.groups:
            errors.append("%s: groups（ホストグループ）は 1 つ以上必要です" % src)

        main_seen: Dict[int, int] = {}
        for iface in spec.interfaces:
            tname = IFACE_TYPE_NAMES.get(iface.type, str(iface.type))
            if iface.useip == 1:
                if not iface.ip:
                    errors.append("%s: useip=1 なので interface_ip が必要です（%s）" % (src, tname))
                elif not _valid_address(iface.ip):
                    errors.append("%s: IP アドレスが不正です: %s" % (src, iface.ip))
            else:
                if not iface.dns:
                    errors.append("%s: useip=0 なので interface_dns が必要です（%s）" % (src, tname))
            port = iface.port or ""
            if not (port.isdigit() and 1 <= int(port) <= 65535) and not MACRO_PLACEHOLDER.match(port):
                errors.append("%s: ポートが不正です: %s" % (src, port))
            if iface.main == 1:
                main_seen[iface.type] = main_seen.get(iface.type, 0) + 1
                if main_seen[iface.type] > 1:
                    errors.append("%s: %s インターフェースの main=1 が複数あります" % (src, tname))
            if iface.type == 2 and iface.details.get("version") not in (None, 1, 2, 3):
                errors.append("%s: snmp_version は 1/2/3 です: %s"
                              % (src, iface.details.get("version")))

        for macro in spec.macros:
            name = str(macro.get("macro", ""))
            if not MACRO_RE.match(name):
                errors.append("%s: マクロ名は {$NAME} 形式にしてください: %s" % (src, name))
        macro_names = [m.get("macro") for m in spec.macros]
        dupes = {n for n in macro_names if macro_names.count(n) > 1}
        for name in sorted(dupes):
            errors.append("%s: マクロ名が重複しています: %s" % (src, name))

        for tag in spec.tags:
            if not str(tag.get("tag", "")).strip():
                errors.append("%s: タグ名が空です" % src)

        if spec.proxy and spec.proxy_group:
            errors.append("%s: proxy と proxy_group は同時に指定できません" % src)

    return errors


# --------------------------------------------------------------------------
# 名前解決（ホストグループ → ホストの順序を保証する）
# --------------------------------------------------------------------------

class Resolver:
    def __init__(self, api: ZabbixAPI, create_groups: bool = False, dry_run: bool = False):
        self.api = api
        self.create_groups = create_groups
        self.dry_run = dry_run
        self.groups: Dict[str, str] = {}
        self.templates: Dict[str, str] = {}
        self.proxies: Dict[str, str] = {}
        self.proxy_groups: Dict[str, str] = {}
        self.created_groups: List[str] = []

    def resolve(self, specs: Sequence[HostSpec]) -> List[str]:
        """入力全体の名前を「まとめて 1 回」解決する（N+1 回避）。"""
        errors: List[str] = []
        group_names = _dedup([g for s in specs for g in s.groups])
        tmpl_names = _dedup([t for s in specs for t in s.templates])
        proxy_names = _dedup([s.proxy for s in specs if s.proxy])
        pgroup_names = _dedup([s.proxy_group for s in specs if s.proxy_group])

        if group_names:
            rows = self.api.call("hostgroup.get", {
                "output": ["groupid", "name"], "filter": {"name": group_names}})
            self.groups = {r["name"]: r["groupid"] for r in rows}
            missing = [n for n in group_names if n not in self.groups]
            if missing:
                if not self.create_groups:
                    errors.append("存在しないホストグループがあります（--create-groups で自動作成できます）: %s"
                                  % ", ".join(missing))
                elif self.dry_run:
                    self.created_groups = list(missing)
                    for i, name in enumerate(missing):
                        self.groups[name] = "dry-run-group-%d" % (i + 1)
                else:
                    # 記事 A ポイント 2: ホストグループはホストより先に作る
                    res = self.api.call("hostgroup.create",
                                        [{"name": n} for n in missing]) or {}
                    ids = res.get("groupids", [])
                    if len(ids) == len(missing):
                        self.groups.update(dict(zip(missing, ids)))
                    else:  # 念のため引き直す
                        rows = self.api.call("hostgroup.get", {
                            "output": ["groupid", "name"], "filter": {"name": missing}})
                        self.groups.update({r["name"]: r["groupid"] for r in rows})
                    self.created_groups = list(missing)

        if tmpl_names:
            rows = self.api.call("template.get", {
                "output": ["templateid", "host"], "filter": {"host": tmpl_names}})
            self.templates = {r["host"]: r["templateid"] for r in rows}
            missing = [n for n in tmpl_names if n not in self.templates]
            if missing:
                errors.append("存在しないテンプレートがあります: %s" % ", ".join(missing))

        if proxy_names:
            if self.api.supports_monitored_by:
                rows = self.api.call("proxy.get", {
                    "output": ["proxyid", "name"], "filter": {"name": proxy_names}})
                self.proxies = {r["name"]: r["proxyid"] for r in rows}
            else:  # 6.x のプロキシは host 名で持つ
                rows = self.api.call("proxy.get", {
                    "output": ["proxyid", "host"], "filter": {"host": proxy_names}})
                self.proxies = {r.get("host", ""): r["proxyid"] for r in rows}
            missing = [n for n in proxy_names if n not in self.proxies]
            if missing:
                errors.append("存在しないプロキシがあります: %s" % ", ".join(missing))

        if pgroup_names:
            if not self.api.supports_monitored_by:
                errors.append("proxy_group は Zabbix 7.0 以降でのみ使用できます（現在 %s）"
                              % self.api.version)
            else:
                rows = self.api.call("proxygroup.get", {
                    "output": ["proxy_groupid", "name"], "filter": {"name": pgroup_names}})
                self.proxy_groups = {r["name"]: r["proxy_groupid"] for r in rows}
                missing = [n for n in pgroup_names if n not in self.proxy_groups]
                if missing:
                    errors.append("存在しないプロキシグループがあります: %s" % ", ".join(missing))

        return errors


# --------------------------------------------------------------------------
# 差分計算
# --------------------------------------------------------------------------

def _norm_iface(obj: Dict[str, Any]) -> Tuple:
    details = obj.get("details") or {}
    if not isinstance(details, dict):
        details = {}
    if int(obj.get("type", 1)) != 2:
        details = {}
    dt = tuple(sorted((k, str(v)) for k, v in details.items()
                      if k in ("version", "community", "bulk")))
    return (int(obj.get("type", 1)), int(obj.get("main", 1)), int(obj.get("useip", 1)),
            str(obj.get("ip", "") or ""), str(obj.get("dns", "") or ""),
            str(obj.get("port", "") or ""), dt)


class Planner:
    def __init__(self, api: ZabbixAPI, resolver: Resolver,
                 prune: bool = False, force_secret: bool = False,
                 fetch_chunk: int = 500):
        self.api = api
        self.resolver = resolver
        self.prune = prune
        self.force_secret = force_secret
        self.fetch_chunk = fetch_chunk

    # -- 既存ホスト取得 -----------------------------------------------------

    def fetch_existing(self, hostnames: Sequence[str]) -> Dict[str, Dict[str, Any]]:
        existing: Dict[str, Dict[str, Any]] = {}
        gkey = self.api.select_groups_key
        base_output = ["hostid", "host", "name", "status", "description", "inventory_mode"]
        if self.api.supports_monitored_by:
            base_output += ["monitored_by", "proxyid", "proxy_groupid"]
        else:
            base_output += ["proxy_hostid"]
        for i in range(0, len(hostnames), self.fetch_chunk):
            batch = list(hostnames[i:i + self.fetch_chunk])
            params = {
                "output": base_output,
                "filter": {"host": batch},
                gkey: ["groupid", "name"],
                "selectParentTemplates": ["templateid", "host"],
                "selectInterfaces": ["interfaceid", "type", "main", "useip",
                                     "ip", "dns", "port", "details"],
                "selectTags": ["tag", "value"],
                "selectMacros": ["hostmacroid", "macro", "value", "type", "description"],
            }
            for row in self.api.call("host.get", params) or []:
                row["_groups"] = row.get("hostgroups") or row.get("groups") or []
                existing[row["host"]] = row
        return existing

    # -- パラメータ組み立て -------------------------------------------------

    def _group_ids(self, spec: HostSpec) -> List[str]:
        return [self.resolver.groups[g] for g in spec.groups if g in self.resolver.groups]

    def _template_ids(self, spec: HostSpec) -> List[str]:
        return [self.resolver.templates[t] for t in spec.templates if t in self.resolver.templates]

    def _monitor_params(self, spec: HostSpec) -> Dict[str, Any]:
        if self.api.supports_monitored_by:
            if spec.proxy:
                return {"monitored_by": 1, "proxyid": self.resolver.proxies[spec.proxy]}
            if spec.proxy_group:
                return {"monitored_by": 2,
                        "proxy_groupid": self.resolver.proxy_groups[spec.proxy_group]}
            return {"monitored_by": 0}
        if spec.proxy:  # 6.x 互換
            return {"proxy_hostid": self.resolver.proxies[spec.proxy]}
        return {}

    def create_params(self, spec: HostSpec) -> Dict[str, Any]:
        params: Dict[str, Any] = {
            "host": spec.host,
            "groups": [{"groupid": gid} for gid in self._group_ids(spec)],
            "status": spec.status,
        }
        if spec.visible_name != spec.host:
            params["name"] = spec.visible_name
        if spec.interfaces:
            params["interfaces"] = [i.to_api() for i in spec.interfaces]
        if spec.templates:
            params["templates"] = [{"templateid": t} for t in self._template_ids(spec)]
        if spec.tags:
            params["tags"] = [{"tag": t["tag"], "value": t.get("value", "")} for t in spec.tags]
        if spec.macros:
            params["macros"] = [_macro_api(m) for m in spec.macros]
        if spec.description:
            params["description"] = spec.description
        if spec.inventory_mode is not None:
            params["inventory_mode"] = spec.inventory_mode
        params.update(self._monitor_params(spec))
        return params

    def update_params(self, spec: HostSpec,
                      cur: Dict[str, Any]) -> Tuple[Dict[str, Any], Dict[str, Any]]:
        params: Dict[str, Any] = {"hostid": cur["hostid"]}
        changes: Dict[str, Any] = {}

        if str(cur.get("name", "")) != spec.visible_name:
            params["name"] = spec.visible_name
            changes["name"] = {"from": cur.get("name"), "to": spec.visible_name}
        if int(cur.get("status", 0)) != spec.status:
            params["status"] = spec.status
            changes["status"] = {"from": int(cur.get("status", 0)), "to": spec.status}
        if spec.description and str(cur.get("description", "")) != spec.description:
            params["description"] = spec.description
            changes["description"] = {"from": cur.get("description"), "to": spec.description}
        if spec.inventory_mode is not None and \
                int(cur.get("inventory_mode", 0)) != spec.inventory_mode:
            params["inventory_mode"] = spec.inventory_mode
            changes["inventory_mode"] = {"from": int(cur.get("inventory_mode", 0)),
                                         "to": spec.inventory_mode}

        # --- ホストグループ ---
        cur_g = {g["groupid"] for g in cur.get("_groups", [])}
        want_g = set(self._group_ids(spec))
        final_g = want_g if self.prune else (cur_g | want_g)
        if final_g != cur_g and final_g:
            params["groups"] = [{"groupid": g} for g in sorted(final_g)]
            changes["groups"] = {"added": sorted(final_g - cur_g),
                                 "removed": sorted(cur_g - final_g)}

        # --- テンプレート ---
        cur_t = {t["templateid"] for t in cur.get("parentTemplates", [])}
        want_t = set(self._template_ids(spec))
        final_t = want_t if self.prune else (cur_t | want_t)
        if final_t != cur_t:
            params["templates"] = [{"templateid": t} for t in sorted(final_t)]
            removed = sorted(cur_t - final_t)
            if removed and self.prune:
                # アイテム・履歴ごと削除されるため prune のみ
                params["templates_clear"] = [{"templateid": t} for t in removed]
            changes["templates"] = {"added": sorted(final_t - cur_t), "removed": removed}

        # --- タグ ---
        cur_tags = {(t.get("tag", ""), t.get("value", "")) for t in cur.get("tags", [])}
        want_tags = {(t.get("tag", ""), t.get("value", "")) for t in spec.tags}
        final_tags = want_tags if self.prune else (cur_tags | want_tags)
        if final_tags != cur_tags:
            params["tags"] = [{"tag": t, "value": v} for t, v in sorted(final_tags)]
            changes["tags"] = {
                "added": [{"tag": t, "value": v} for t, v in sorted(final_tags - cur_tags)],
                "removed": [{"tag": t, "value": v} for t, v in sorted(cur_tags - final_tags)]}

        # --- マクロ（hostmacroid を引き継いで置換する）---
        macro_params, macro_changes = self._macro_diff(spec, cur)
        if macro_changes:
            params["macros"] = macro_params
            changes["macros"] = macro_changes

        # --- インターフェース（interfaceid を引き継ぐ）---
        iface_params, iface_changes = self._interface_diff(spec, cur)
        if iface_changes:
            params["interfaces"] = iface_params
            changes["interfaces"] = iface_changes

        # --- 監視元 ---
        mon = self._monitor_params(spec)
        if self.api.supports_monitored_by:
            if spec.proxy or spec.proxy_group or int(cur.get("monitored_by", 0)) != 0:
                cur_mon = (int(cur.get("monitored_by", 0)),
                           str(cur.get("proxyid", "0") or "0"),
                           str(cur.get("proxy_groupid", "0") or "0"))
                new_mon = (mon.get("monitored_by", 0),
                           str(mon.get("proxyid", "0")), str(mon.get("proxy_groupid", "0")))
                if cur_mon != new_mon:
                    params.update(mon)
                    changes["monitored_by"] = {"from": cur_mon[0], "to": new_mon[0]}
        elif mon and str(cur.get("proxy_hostid", "0")) != str(mon.get("proxy_hostid")):
            params.update(mon)
            changes["proxy_hostid"] = {"from": cur.get("proxy_hostid"),
                                       "to": mon.get("proxy_hostid")}

        return params, changes

    def _macro_diff(self, spec: HostSpec,
                    cur: Dict[str, Any]) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
        cur_macros = {m["macro"]: m for m in cur.get("macros", [])}
        want = {m["macro"]: m for m in spec.macros}
        final: List[Dict[str, Any]] = []
        added, changed, removed = [], [], []

        keep_order = list(cur_macros.keys()) if not self.prune else []
        for name in keep_order:
            if name in want:
                continue
            final.append({"hostmacroid": cur_macros[name]["hostmacroid"]})
        if self.prune:
            removed = [n for n in cur_macros if n not in want]

        for name, macro in want.items():
            api_obj = _macro_api(macro)
            if name in cur_macros:
                existing = cur_macros[name]
                api_obj["hostmacroid"] = existing["hostmacroid"]
                is_secret = int(macro.get("type", 0)) == 1
                if is_secret and not self.force_secret:
                    # secret の値は API から取得できないため比較不能。既定では触らない
                    final.append({"hostmacroid": existing["hostmacroid"]})
                    continue
                same = (str(existing.get("value", "")) == str(api_obj.get("value", ""))
                        and int(existing.get("type", 0)) == int(api_obj.get("type", 0))
                        and str(existing.get("description", "")) ==
                        str(api_obj.get("description", "")))
                final.append(api_obj)
                if not same:
                    changed.append(name)
            else:
                final.append(api_obj)
                added.append(name)

        if not (added or changed or removed):
            return [], {}
        return final, {"added": added, "changed": changed, "removed": removed}

    def _interface_diff(self, spec: HostSpec,
                        cur: Dict[str, Any]) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
        if not spec.interfaces:
            return [], {}
        cur_ifaces = cur.get("interfaces", []) or []
        by_key: Dict[Tuple[int, int], Dict[str, Any]] = {}
        for existing in cur_ifaces:
            by_key[(int(existing.get("type", 1)), int(existing.get("main", 1)))] = existing

        final: List[Dict[str, Any]] = []
        matched_ids = set()
        for iface in spec.interfaces:
            obj = iface.to_api()
            existing = by_key.get(iface.key())
            if existing:
                obj["interfaceid"] = existing["interfaceid"]
                matched_ids.add(existing["interfaceid"])
            final.append(obj)
        if not self.prune:
            for existing in cur_ifaces:
                if existing["interfaceid"] not in matched_ids:
                    final.append({k: existing[k] for k in
                                  ("interfaceid", "type", "main", "useip", "ip", "dns", "port")
                                  if k in existing})

        before = sorted(_norm_iface(i) for i in cur_ifaces)
        after = sorted(_norm_iface(i) for i in final)
        if before == after:
            return [], {}
        return final, {"from": [_iface_label(i) for i in cur_ifaces],
                       "to": [_iface_label(i) for i in final]}

    # -- プラン生成 ---------------------------------------------------------

    def plan(self, specs: Sequence[HostSpec]) -> Plan:
        existing = self.fetch_existing([s.host for s in specs])
        plan = Plan()
        for spec in specs:
            cur = existing.get(spec.host)
            if cur is None:
                plan.creates.append((spec, self.create_params(spec)))
                continue
            params, changes = self.update_params(spec, cur)
            if changes:
                params_with = dict(params)
                plan.updates.append((spec, params_with, changes))
            else:
                plan.noops.append((spec, cur["hostid"]))
        return plan


def _macro_api(macro: Dict[str, Any]) -> Dict[str, Any]:
    obj: Dict[str, Any] = {"macro": macro["macro"], "value": str(macro.get("value", "") or "")}
    mtype = int(macro.get("type", 0) or 0)
    if mtype:
        obj["type"] = mtype
    if macro.get("description"):
        obj["description"] = macro["description"]
    return obj


def _iface_label(iface: Dict[str, Any]) -> str:
    tname = IFACE_TYPE_NAMES.get(int(iface.get("type", 1)), "?")
    addr = iface.get("ip") if int(iface.get("useip", 1)) == 1 else iface.get("dns")
    return "%s://%s:%s" % (tname, addr or "-", iface.get("port", "-"))


# --------------------------------------------------------------------------
# 適用
# --------------------------------------------------------------------------

@dataclass
class Result:
    host: str
    action: str                       # CREATE / UPDATE / NOOP / FAIL
    hostid: Optional[str] = None
    changes: Dict[str, Any] = field(default_factory=dict)
    error: str = ""
    source: str = ""


class Executor:
    def __init__(self, api: ZabbixAPI, chunk_size: int = 50,
                 dry_run: bool = False, verify: bool = False):
        self.api = api
        self.chunk_size = max(1, chunk_size)
        self.dry_run = dry_run
        self.verify = verify

    def apply(self, plan: Plan) -> List[Result]:
        results: List[Result] = []
        for i in range(0, len(plan.creates), self.chunk_size):
            results.extend(self._create_chunk(plan.creates[i:i + self.chunk_size]))
        for spec, params, changes in plan.updates:
            results.append(self._update_one(spec, params, changes))
        for spec, hostid in plan.noops:
            results.append(Result(spec.host, "NOOP", hostid, source=spec.source))
        if self.verify and not self.dry_run:
            self._verify(results)
        return results

    # host.create はオブジェクト配列を受け付ける（1 リクエストで N 件）。
    # ただしバルクは all-or-nothing なので、失敗したら 1 件ずつに割って犯人を特定する。
    def _create_chunk(self, items: List[Tuple[HostSpec, Dict[str, Any]]],
                      depth: int = 0) -> List[Result]:
        if not items:
            return []
        if self.dry_run:
            return [Result(s.host, "CREATE", None, {"params": _mask(p)}, source=s.source)
                    for s, p in items]
        payload = [p for _, p in items]
        try:
            res = self.api.call("host.create", payload) or {}
        except ZabbixAPITransportError as exc:
            if depth >= 2:
                return [Result(s.host, "FAIL", error="通信エラー: %s" % exc, source=s.source)
                        for s, _ in items]
            # 通信が切れただけで作成済みの可能性がある。実態を確認して二重作成を防ぐ
            done = self._lookup([s.host for s, _ in items])
            results = [Result(s.host, "CREATE", done[s.host], source=s.source)
                       for s, _ in items if s.host in done]
            rest = [(s, p) for s, p in items if s.host not in done]
            return results + self._create_chunk(rest, depth + 1)
        except ZabbixAPIError as exc:
            if len(items) == 1:
                spec = items[0][0]
                return [Result(spec.host, "FAIL", error=str(exc), source=spec.source)]
            out: List[Result] = []
            for item in items:
                out.extend(self._create_chunk([item], depth))
            return out

        ids = res.get("hostids") or []
        if len(ids) == len(items):
            return [Result(s.host, "CREATE", hid, source=s.source)
                    for (s, _), hid in zip(items, ids)]
        # 返却件数が合わない場合は引き直す
        done = self._lookup([s.host for s, _ in items])
        return [Result(s.host, "CREATE" if s.host in done else "FAIL",
                       done.get(s.host),
                       error="" if s.host in done else "作成結果を確認できませんでした",
                       source=s.source)
                for s, _ in items]

    def _update_one(self, spec: HostSpec, params: Dict[str, Any],
                    changes: Dict[str, Any]) -> Result:
        if self.dry_run:
            return Result(spec.host, "UPDATE", params.get("hostid"), changes,
                          source=spec.source)
        try:
            self.api.call("host.update", params)
        except (ZabbixAPIError, ZabbixAPITransportError) as exc:
            return Result(spec.host, "FAIL", params.get("hostid"),
                          error=str(exc), source=spec.source)
        return Result(spec.host, "UPDATE", params.get("hostid"), changes, source=spec.source)

    def _lookup(self, hostnames: Sequence[str]) -> Dict[str, str]:
        if not hostnames:
            return {}
        rows = self.api.call("host.get", {"output": ["hostid", "host"],
                                          "filter": {"host": list(hostnames)}}) or []
        return {r["host"]: r["hostid"] for r in rows}

    def _verify(self, results: List[Result]) -> None:
        targets = [r for r in results if r.action == "CREATE"]
        if not targets:
            return
        found = self._lookup([r.host for r in targets])
        for r in targets:
            if r.host in found:
                r.hostid = found[r.host]
            else:
                r.action = "FAIL"
                r.error = "作成後の検証で見つかりませんでした"


# --------------------------------------------------------------------------
# 出力
# --------------------------------------------------------------------------

def _log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def _brief(obj: Any, limit: int = 200) -> str:
    text = json.dumps(_mask(obj), ensure_ascii=False)
    return text if len(text) <= limit else text[:limit] + "..."


# ログ・レポートに絶対に出してはいけないキー
SENSITIVE_KEYS = frozenset({"password", "token", "auth", "sessionid", "Authorization"})


def _mask(obj: Any) -> Any:
    """認証情報と secret 型マクロの値をレポート・ログから落とす。"""
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if k in SENSITIVE_KEYS:
                out[k] = SECRET_MASK
            elif k == "value" and int(obj.get("type", 0) or 0) == 1:
                out[k] = SECRET_MASK
            else:
                out[k] = _mask(v)
        return out
    if isinstance(obj, list):
        return [_mask(v) for v in obj]
    return obj


def _summarize_changes(changes: Dict[str, Any]) -> str:
    parts: List[str] = []
    for key, val in changes.items():
        if key == "params":
            continue
        if isinstance(val, dict) and ("added" in val or "removed" in val or "changed" in val):
            bits = []
            for label, sign in (("added", "+"), ("changed", "~"), ("removed", "-")):
                items = val.get(label) or []
                if items:
                    bits.append("%s%d" % (sign, len(items)))
            parts.append("%s(%s)" % (key, ",".join(bits)))
        else:
            parts.append(key)
    return " ".join(parts)


class Reporter:
    def __init__(self, quiet: bool = False):
        self.quiet = quiet

    def section(self, title: str) -> None:
        if not self.quiet:
            print("\n=== %s ===" % title)

    def line(self, text: str) -> None:
        if not self.quiet:
            print(text)

    def results(self, results: Sequence[Result]) -> None:
        if self.quiet:
            return
        width = max([len(r.host) for r in results] + [10])
        for r in results:
            if r.action == "FAIL":
                extra = r.error
            elif r.action == "UPDATE":
                extra = _summarize_changes(r.changes)
            elif r.action == "CREATE":
                extra = "hostid=%s" % r.hostid if r.hostid else ""
            else:
                extra = "hostid=%s" % (r.hostid or "-")
            print("[%-6s] %-*s %s" % (r.action, width, r.host, extra))

    @staticmethod
    def summary(results: Sequence[Result]) -> Dict[str, int]:
        counts = {"created": 0, "updated": 0, "noop": 0, "failed": 0}
        for r in results:
            counts[{"CREATE": "created", "UPDATE": "updated",
                    "NOOP": "noop", "FAIL": "failed"}[r.action]] += 1
        return counts

    @staticmethod
    def write_json(path: str, payload: Dict[str, Any]) -> None:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(_mask(payload), fh, ensure_ascii=False, indent=2)


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="zbx-bulk-host",
        description="Zabbix にホストを一括登録／更新する（冪等・dry-run 対応）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="例:\n"
               "  zbx_bulk_host.py plan  hosts.csv --create-groups\n"
               "  zbx_bulk_host.py apply hosts.csv --create-groups --report apply.json\n")
    parser.add_argument("--version", action="version", version=__version__)
    sub = parser.add_subparsers(dest="command", required=True)

    for name, help_text in (("apply", "実際に登録／更新する"),
                            ("plan", "書き込まずに差分だけ表示する（dry-run）")):
        sp = sub.add_parser(name, help=help_text)
        sp.add_argument("inputs", nargs="+", help="入力ファイル（.csv / .yaml、複数指定可）")
        sp.add_argument("--url", default=os.environ.get("ZABBIX_URL", ""),
                        help="Zabbix フロントエンド URL（既定: $ZABBIX_URL）")
        sp.add_argument("--token", default=os.environ.get("ZABBIX_TOKEN"),
                        help="API トークン（既定: $ZABBIX_TOKEN）")
        sp.add_argument("--user", default=os.environ.get("ZABBIX_USER"),
                        help="user.login 方式のユーザー名（PW は $ZABBIX_PASSWORD）")
        sp.add_argument("--timeout", type=int, default=30, help="HTTP タイムアウト秒（既定 30）")
        sp.add_argument("--insecure", action="store_true", help="TLS 証明書検証を無効化")
        sp.add_argument("--create-groups", action="store_true",
                        help="未存在のホストグループを作成する")
        sp.add_argument("--prune", action="store_true",
                        help="ファイルの内容に完全一致させる（既存の余剰設定を削除）")
        sp.add_argument("--force-secret", action="store_true",
                        help="secret 型マクロを毎回送信する")
        sp.add_argument("--chunk-size", type=int, default=50,
                        help="host.create のチャンク件数（既定 50）")
        sp.add_argument("--sleep", type=float, default=0.0, help="API 呼び出し間隔秒")
        sp.add_argument("--verify", action="store_true", help="作成後に host.get で検証する")
        sp.add_argument("--report", help="JSON レポートの出力先")
        sp.add_argument("-v", "--verbose", action="store_true", help="詳細ログ")
        sp.add_argument("-q", "--quiet", action="store_true", help="サマリのみ")
        if name == "apply":
            sp.add_argument("--dry-run", action="store_true", help="書き込まない")
    return parser


def run(args: argparse.Namespace) -> int:
    dry_run = args.command == "plan" or getattr(args, "dry_run", False)
    rep = Reporter(quiet=args.quiet)
    started = datetime.now(timezone.utc).astimezone()

    # ---- 1. 読み込み ----
    rep.section("Load")
    try:
        specs, load_errors, warnings = load_specs(args.inputs)
    except InputError as exc:
        _log("入力エラー: %s" % exc)
        return EXIT_VALIDATION
    for w in warnings:
        rep.line("WARN: %s" % w)
    rep.line("%d hosts loaded from %s" % (len(specs), ", ".join(args.inputs)))

    # ---- 2. 静的バリデーション ----
    errors = list(load_errors) + validate_specs(specs)
    if not specs and not errors:
        errors.append("入力にホストが 1 件もありません")

    # ---- 3. 接続 ----
    rep.section("Connect")
    password = os.environ.get("ZABBIX_PASSWORD")
    if args.user and not args.token and not password:
        # 対話端末なら画面に出さずに聞く（履歴・ps に残さないため）
        if sys.stdin.isatty():
            password = getpass.getpass("Zabbix のパスワード (%s): " % args.user)
        else:
            _log("パスワードがありません。環境変数 ZABBIX_PASSWORD を設定してください。")
            return EXIT_CONNECT
    api = ZabbixAPI(url=args.url, token=args.token, user=args.user, password=password,
                    timeout=args.timeout, verify=not args.insecure,
                    sleep=args.sleep, verbose=args.verbose)
    try:
        version = api.connect()
    except (ZabbixAPIError, ZabbixAPITransportError, RuntimeError) as exc:
        _log("接続／認証に失敗しました: %s" % exc)
        return EXIT_CONNECT
    rep.line("%s (API %s, auth=%s, transport=%s)"
             % (api.url, version, api.auth_method,
                "bearer" if api.use_bearer else "auth-param"))

    try:
        return _pipeline(args, api, rep, specs, errors, started, dry_run)
    finally:
        # user.login で作ったセッションは必ず無効化する（API トークンなら何もしない）
        api.close()


def _pipeline(args: argparse.Namespace, api: "ZabbixAPI", rep: "Reporter",
              specs: List[HostSpec], errors: List[str],
              started: datetime, dry_run: bool) -> int:
    # ---- 4. 名前解決（グループ → ホストの順序を保証）----
    rep.section("Resolve")
    resolver = Resolver(api, create_groups=args.create_groups, dry_run=dry_run)
    errors.extend(resolver.resolve(specs))

    if errors:
        rep.section("Validation failed")
        for e in errors:
            print("ERROR: %s" % e, file=sys.stderr)
        _log("%d 件のエラーがあるため、書き込みを行わずに終了しました。" % len(errors))
        return EXIT_VALIDATION

    created_note = ""
    if resolver.created_groups:
        created_note = ", %d %s (%s)" % (
            len(resolver.created_groups),
            "would create" if dry_run else "created",
            ", ".join(resolver.created_groups))
    rep.line("host groups : %d resolved%s" % (len(resolver.groups), created_note))
    rep.line("templates   : %d resolved" % len(resolver.templates))
    if resolver.proxies or resolver.proxy_groups:
        rep.line("proxies     : %d / proxy groups: %d"
                 % (len(resolver.proxies), len(resolver.proxy_groups)))

    # ---- 5. 差分計算 ----
    rep.section("Plan")
    planner = Planner(api, resolver, prune=args.prune, force_secret=args.force_secret)
    plan = planner.plan(specs)
    rep.line("CREATE %5d" % len(plan.creates))
    rep.line("UPDATE %5d" % len(plan.updates))
    rep.line("NOOP   %5d" % len(plan.noops))
    if args.prune and any("templates_clear" in p for _, p, _ in plan.updates):
        rep.line("WARN: --prune によりテンプレートのリンク解除（アイテム・履歴の削除）が発生します")

    # ---- 6. 適用 ----
    rep.section("Apply (dry-run)" if dry_run else "Apply")
    executor = Executor(api, chunk_size=args.chunk_size, dry_run=dry_run, verify=args.verify)
    interrupted = False
    try:
        results = executor.apply(plan)
    except KeyboardInterrupt:
        _log("中断されました。")
        results, interrupted = [], True
    rep.results(results)

    # ---- 7. レポート ----
    counts = Reporter.summary(results)
    finished = datetime.now(timezone.utc).astimezone()
    rep.section("Summary")
    print("created=%d updated=%d noop=%d failed=%d  api_calls=%d  elapsed=%.1fs%s"
          % (counts["created"], counts["updated"], counts["noop"], counts["failed"],
             api.call_count, (finished - started).total_seconds(),
             "  (dry-run)" if dry_run else ""))

    if args.report:
        Reporter.write_json(args.report, {
            "started_at": started.isoformat(),
            "finished_at": finished.isoformat(),
            "tool_version": __version__,
            "zabbix": {"url": api.url, "api_version": api.version},
            "options": {"command": args.command, "dry_run": dry_run, "prune": args.prune,
                        "create_groups": args.create_groups, "chunk_size": args.chunk_size,
                        "inputs": list(args.inputs)},
            "summary": counts,
            "created_host_groups": resolver.created_groups,
            "results": [{"host": r.host, "action": r.action, "hostid": r.hostid,
                         "changes": r.changes, "error": r.error, "source": r.source}
                        for r in results],
        })
        rep.line("report: %s" % args.report)

    if interrupted:
        return EXIT_INTERRUPTED
    return EXIT_APPLY_FAILED if counts["failed"] else EXIT_OK


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return run(args)
    except KeyboardInterrupt:
        _log("中断されました。")
        return EXIT_INTERRUPTED


if __name__ == "__main__":
    sys.exit(main())

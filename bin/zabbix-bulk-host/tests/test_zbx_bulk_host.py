#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""zbx_bulk_host の単体／結合テスト（実 Zabbix 不要・requests 不要）。

実行:
    cd zabbix-bulk-host && python -m unittest discover -s tests -v
"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import zbx_bulk_host as z  # noqa: E402


# --------------------------------------------------------------------------
# モック API（インメモリの Zabbix）
# --------------------------------------------------------------------------

class FakeAPI:
    """ZabbixAPI と同じ call() インターフェースを持つインメモリ実装。"""

    def __init__(self, version="7.0.9", groups=None, templates=None,
                 proxies=None, hosts=None, fail_hosts=None):
        self.version = version
        parts = version.split(".")
        self.major, self.minor = int(parts[0]), int(parts[1])
        self.groups = dict(groups or {})            # name -> groupid
        self.templates = dict(templates or {})      # name -> templateid
        self.proxies = dict(proxies or {})          # name -> proxyid
        self.hosts = {h["host"]: h for h in (hosts or [])}
        self.fail_hosts = set(fail_hosts or [])
        self.calls = []                             # 呼び出し履歴（回数検証用）
        self._seq = 20000
        self.admin_user = "Admin"
        self.admin_password = "zabbix"
        self.sessions = set()                       # user.login で払い出したセッション

    # -- ZabbixAPI 互換プロパティ -----------------------------------------
    @property
    def supports_monitored_by(self):
        return self.major >= 7

    @property
    def select_groups_key(self):
        return "selectHostGroups" if (self.major, self.minor) >= (6, 2) else "selectGroups"

    @property
    def use_bearer(self):
        return (self.major, self.minor) >= (6, 4)

    @property
    def call_count(self):
        return len(self.calls)

    def count(self, method):
        return sum(1 for m, _ in self.calls if m == method)

    # -- ディスパッチ ------------------------------------------------------
    def call(self, method, params=None, auth=True):
        self.calls.append((method, params))
        handler = getattr(self, "_" + method.replace(".", "_"), None)
        if handler is None:
            raise AssertionError("未実装のモックメソッド: %s" % method)
        return handler(params or {})

    def _next_id(self):
        self._seq += 1
        return str(self._seq)

    # -- メソッド実装 ------------------------------------------------------
    def _apiinfo_version(self, params):
        return self.version

    def _user_login(self, params):
        # 6.0 以降は username、5.x 以前は user
        name = params.get("username") or params.get("user")
        if name != self.admin_user or params.get("password") != self.admin_password:
            raise z.ZabbixAPIError("Incorrect user name or password or account is "
                                   "temporarily blocked.", -32602, "")
        self.sessions.add("sess-%d" % (len(self.sessions) + 1))
        return sorted(self.sessions)[-1]

    def _user_logout(self, params):
        self.sessions.clear()
        return True

    def _hostgroup_get(self, params):
        names = (params.get("filter") or {}).get("name") or list(self.groups)
        return [{"groupid": self.groups[n], "name": n} for n in names if n in self.groups]

    def _hostgroup_create(self, params):
        items = params if isinstance(params, list) else [params]
        ids = []
        for it in items:
            gid = self._next_id()
            self.groups[it["name"]] = gid
            ids.append(gid)
        return {"groupids": ids}

    def _template_get(self, params):
        names = (params.get("filter") or {}).get("host") or list(self.templates)
        return [{"templateid": self.templates[n], "host": n}
                for n in names if n in self.templates]

    def _proxy_get(self, params):
        f = params.get("filter") or {}
        names = f.get("name") or f.get("host") or list(self.proxies)
        key = "name" if self.supports_monitored_by else "host"
        return [{"proxyid": self.proxies[n], key: n} for n in names if n in self.proxies]

    def _proxygroup_get(self, params):
        return []

    def _host_get(self, params):
        names = (params.get("filter") or {}).get("host")
        rows = [h for h in self.hosts.values() if names is None or h["host"] in names]
        if params.get("countOutput"):
            return str(len(rows))
        gkey = self.select_groups_key.replace("select", "").lower()
        gkey = "hostgroups" if gkey == "hostgroups" else "groups"
        out = []
        for h in rows:
            row = {k: h.get(k, "") for k in
                   ("hostid", "host", "name", "status", "description", "inventory_mode")}
            if self.supports_monitored_by:
                row.update({"monitored_by": h.get("monitored_by", 0),
                            "proxyid": h.get("proxyid", "0"),
                            "proxy_groupid": h.get("proxy_groupid", "0")})
            row[gkey] = h.get("groups", [])
            row["parentTemplates"] = h.get("parentTemplates", [])
            row["interfaces"] = h.get("interfaces", [])
            row["tags"] = h.get("tags", [])
            row["macros"] = h.get("macros", [])
            out.append(row)
        return out

    def _host_create(self, params):
        items = params if isinstance(params, list) else [params]
        # バルクは all-or-nothing。1 件でも不正なら全体を失敗させる
        for it in items:
            if it["host"] in self.hosts or it["host"] in self.fail_hosts:
                raise z.ZabbixAPIError("Invalid params.", -32602,
                                       'Host "%s" already exists.' % it["host"])
        ids = []
        for it in items:
            hid = self._next_id()
            rec = dict(it)
            rec["hostid"] = hid
            rec.setdefault("name", it["host"])
            rec["groups"] = [{"groupid": g["groupid"], "name": ""} for g in it.get("groups", [])]
            rec["parentTemplates"] = [{"templateid": t["templateid"], "host": ""}
                                      for t in it.get("templates", [])]
            rec["interfaces"] = [dict(i, interfaceid=self._next_id())
                                 for i in it.get("interfaces", [])]
            rec["macros"] = [dict(m, hostmacroid=self._next_id())
                             for m in it.get("macros", [])]
            rec["tags"] = list(it.get("tags", []))
            rec.setdefault("status", 0)
            rec.setdefault("inventory_mode", 0)
            rec.setdefault("description", "")
            self.hosts[it["host"]] = rec
            ids.append(hid)
        return {"hostids": ids}

    def _host_update(self, params):
        hostid = params["hostid"]
        rec = next(h for h in self.hosts.values() if h["hostid"] == hostid)
        for key in ("name", "status", "description", "inventory_mode",
                    "monitored_by", "proxyid", "proxy_groupid"):
            if key in params:
                rec[key] = params[key]
        if "groups" in params:
            rec["groups"] = [{"groupid": g["groupid"], "name": ""} for g in params["groups"]]
        if "templates" in params:
            rec["parentTemplates"] = [{"templateid": t["templateid"], "host": ""}
                                      for t in params["templates"]]
        if "tags" in params:
            rec["tags"] = list(params["tags"])
        if "interfaces" in params:
            rec["interfaces"] = [dict(i, interfaceid=i.get("interfaceid") or self._next_id())
                                 for i in params["interfaces"]]
        if "macros" in params:
            existing = {m["hostmacroid"]: m for m in rec.get("macros", [])}
            new_list = []
            for m in params["macros"]:
                if m.get("hostmacroid") and len(m) == 1:
                    new_list.append(existing[m["hostmacroid"]])      # 現状維持
                elif m.get("hostmacroid"):
                    merged = dict(existing.get(m["hostmacroid"], {}))
                    merged.update(m)
                    new_list.append(merged)
                else:
                    new_list.append(dict(m, hostmacroid=self._next_id()))
            rec["macros"] = new_list
        return {"hostids": [hostid]}


def make_env(**kwargs):
    api = FakeAPI(**kwargs)
    return api


def write(tmpdir, name, content):
    path = os.path.join(tmpdir, name)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)
    return path


CSV_BASIC = (
    "# コメント行\n"
    "host,name,groups,templates,interface_ip,interface_port,tags,macros\n"
    "web01,Web 01,Linux servers;Prod,Linux by Zabbix agent,192.168.1.11,10050,"
    "env=prod;role=web,{$SITE}=tokyo\n"
    "\n"
    "web02,,Linux servers,Linux by Zabbix agent,192.168.1.12,,,\n"
)


# --------------------------------------------------------------------------
# UT-01 / UT-02: 入力パース
# --------------------------------------------------------------------------

class TestCsvLoader(unittest.TestCase):
    def test_parse_basic(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write(tmp, "hosts.csv", CSV_BASIC)
            specs, errors, warnings = z.load_specs([path])
        self.assertEqual(errors, [])
        self.assertEqual([s.host for s in specs], ["web01", "web02"])
        s = specs[0]
        self.assertEqual(s.visible_name, "Web 01")
        self.assertEqual(s.groups, ["Linux servers", "Prod"])
        self.assertEqual(s.templates, ["Linux by Zabbix agent"])
        self.assertEqual(s.tags, [{"tag": "env", "value": "prod"},
                                  {"tag": "role", "value": "web"}])
        self.assertEqual(s.macros, [{"macro": "{$SITE}", "value": "tokyo", "type": 0}])
        self.assertEqual(s.interfaces[0].type, 1)
        self.assertEqual(s.interfaces[0].port, "10050")
        self.assertEqual(s.source, "hosts.csv:3")
        # 表示名を省略した行は host が表示名になる
        self.assertEqual(specs[1].visible_name, "web02")
        # ポート省略時は種別の既定値
        self.assertEqual(specs[1].interfaces[0].port, "10050")

    def test_bom_and_comment_and_blank(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "bom.csv")
            with open(path, "w", encoding="utf-8-sig") as fh:
                fh.write(CSV_BASIC)
            specs, errors, _ = z.load_specs([path])
        self.assertEqual(errors, [])
        self.assertEqual(len(specs), 2)

    def test_unknown_column_warns(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write(tmp, "h.csv", "host,groups,hostname\nweb01,G,typo\n")
            specs, errors, warnings = z.load_specs([path])
        self.assertEqual(errors, [])
        self.assertTrue(any("hostname" in w for w in warnings))

    def test_snmp_defaults(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write(tmp, "h.csv",
                         "host,groups,interface_type,interface_ip,snmp_version\n"
                         "sw01,Network devices,snmp,10.0.0.1,2\n")
            specs, errors, _ = z.load_specs([path])
        self.assertEqual(errors, [])
        iface = specs[0].interfaces[0]
        self.assertEqual(iface.type, 2)
        self.assertEqual(iface.port, "161")
        self.assertEqual(iface.to_api()["details"]["version"], 2)
        self.assertEqual(iface.to_api()["details"]["community"], "{$SNMP_COMMUNITY}")

    def test_bad_interface_type_becomes_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write(tmp, "h.csv",
                         "host,groups,interface_type,interface_ip\nweb01,G,telnet,1.1.1.1\n")
            specs, errors, _ = z.load_specs([path])
        self.assertEqual(specs, [])
        self.assertEqual(len(errors), 1)
        self.assertIn("インターフェース種別", errors[0])


@unittest.skipIf(z.yaml is None, "PyYAML 未インストール")
class TestYamlLoader(unittest.TestCase):
    YAML = """
defaults:
  groups: [Linux servers]
  templates: [Linux by Zabbix agent]
  interfaces:
    - {type: agent, useip: true, port: 10050}
  tags:
    - {tag: env, value: prod}
    - {tag: managed_by, value: zbx-bulk-host}
  macros:
    - {macro: "{$SITE}", value: tokyo}
    - {macro: "{$CPU_WARN}", value: "80"}
  status: enabled
  inventory_mode: manual
hosts:
  - host: web01
    name: Web 01
    interfaces: [{ip: 192.168.1.11}]
    groups: [Prod]
    tags: [{tag: role, value: web}]
  - host: stg01
    groups: [Staging]
    interfaces: [{ip: 10.0.0.1}]
    tags: [{tag: env, value: staging}]
    macros: [{macro: "{$CPU_WARN}", value: "95"}]
    status: disabled
  - host: sw01
    groups: [Network devices]
    interfaces:
      - {type: snmp, ip: 10.1.1.1, port: 161, details: {version: 2, community: public}}
"""

    def _load(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write(tmp, "hosts.yaml", self.YAML)
            return z.load_specs([path])

    def test_defaults_inherited_and_interface_key_inheritance(self):
        specs, errors, _ = self._load()
        self.assertEqual(errors, [])
        web = specs[0]
        self.assertEqual(web.groups, ["Linux servers", "Prod"])
        self.assertEqual(web.templates, ["Linux by Zabbix agent"])
        # defaults の type/port を引き継ぎ、ip だけホスト側から入る
        self.assertEqual(web.interfaces[0].type, 1)
        self.assertEqual(web.interfaces[0].port, "10050")
        self.assertEqual(web.interfaces[0].ip, "192.168.1.11")
        self.assertEqual(web.inventory_mode, 0)
        self.assertEqual(web.status, 0)

    def test_tag_name_override_replaces_default(self):
        specs, _, _ = self._load()
        stg = specs[1]
        tags = {t["tag"]: t["value"] for t in stg.tags}
        self.assertEqual(tags["env"], "staging")            # defaults の prod は消える
        self.assertEqual(tags["managed_by"], "zbx-bulk-host")  # 無関係なタグは残る
        self.assertEqual(stg.status, 1)

    def test_macro_override_by_name(self):
        specs, _, _ = self._load()
        macros = {m["macro"]: m["value"] for m in specs[1].macros}
        self.assertEqual(macros["{$CPU_WARN}"], "95")
        self.assertEqual(macros["{$SITE}"], "tokyo")

    def test_snmp_interface_replaces_defaults(self):
        specs, _, _ = self._load()
        iface = specs[2].interfaces[0]
        self.assertEqual(iface.type, 2)
        self.assertEqual(iface.to_api()["details"]["community"], "public")


# --------------------------------------------------------------------------
# UT-03: バリデーション
# --------------------------------------------------------------------------

class TestValidation(unittest.TestCase):
    def test_missing_host_and_groups(self):
        specs = [z.HostSpec(host="", groups=["G"], source="f:2"),
                 z.HostSpec(host="a", groups=[], source="f:3")]
        errors = z.validate_specs(specs)
        self.assertTrue(any("host（技術名）は必須" in e for e in errors))
        self.assertTrue(any("groups" in e for e in errors))

    def test_duplicate_host(self):
        specs = [z.HostSpec(host="a", groups=["G"], source="f:2"),
                 z.HostSpec(host="a", groups=["G"], source="f:3")]
        errors = z.validate_specs(specs)
        self.assertTrue(any("重複" in e for e in errors))

    def test_useip_requires_ip(self):
        spec = z.HostSpec(host="a", groups=["G"], source="f:2",
                          interfaces=[z.InterfaceSpec(useip=1, ip="", port="10050")])
        self.assertTrue(any("interface_ip" in e for e in z.validate_specs([spec])))

    def test_useip0_requires_dns(self):
        spec = z.HostSpec(host="a", groups=["G"], source="f:2",
                          interfaces=[z.InterfaceSpec(useip=0, dns="", port="10050")])
        self.assertTrue(any("interface_dns" in e for e in z.validate_specs([spec])))

    def test_bad_ip(self):
        spec = z.HostSpec(host="a", groups=["G"], source="f:2",
                          interfaces=[z.InterfaceSpec(ip="192.168.1.999", port="10050")])
        self.assertTrue(any("IP アドレスが不正" in e for e in z.validate_specs([spec])))

    def test_macro_placeholder_ip_allowed(self):
        spec = z.HostSpec(host="a", groups=["G"], source="f:2",
                          interfaces=[z.InterfaceSpec(ip="{$HOST.IP}", port="10050")])
        self.assertEqual(z.validate_specs([spec]), [])

    def test_bad_port(self):
        spec = z.HostSpec(host="a", groups=["G"], source="f:2",
                          interfaces=[z.InterfaceSpec(ip="1.1.1.1", port="99999")])
        self.assertTrue(any("ポートが不正" in e for e in z.validate_specs([spec])))

    def test_duplicate_main_interface(self):
        spec = z.HostSpec(host="a", groups=["G"], source="f:2", interfaces=[
            z.InterfaceSpec(type=1, main=1, ip="1.1.1.1", port="10050"),
            z.InterfaceSpec(type=1, main=1, ip="1.1.1.2", port="10050")])
        self.assertTrue(any("main=1 が複数" in e for e in z.validate_specs([spec])))

    def test_macro_format(self):
        spec = z.HostSpec(host="a", groups=["G"], source="f:2",
                          macros=[{"macro": "SITE", "value": "x", "type": 0}])
        self.assertTrue(any("{$NAME} 形式" in e for e in z.validate_specs([spec])))

    def test_proxy_and_proxy_group_conflict(self):
        spec = z.HostSpec(host="a", groups=["G"], source="f:2",
                          proxy="p1", proxy_group="pg1")
        self.assertTrue(any("同時に指定できません" in e for e in z.validate_specs([spec])))

    def test_valid_spec_has_no_error(self):
        spec = z.HostSpec(host="a", groups=["G"], source="f:2",
                          interfaces=[z.InterfaceSpec(ip="10.0.0.1", port="10050")],
                          macros=[{"macro": "{$SITE}", "value": "x", "type": 0}],
                          tags=[{"tag": "env", "value": "prod"}])
        self.assertEqual(z.validate_specs([spec]), [])


# --------------------------------------------------------------------------
# UT-04: Resolver（N+1 回避 / 未解決検出 / グループ先行作成）
# --------------------------------------------------------------------------

class TestResolver(unittest.TestCase):
    def _specs(self, n):
        return [z.HostSpec(host="h%d" % i, groups=["Linux servers", "Prod"],
                           templates=["Linux by Zabbix agent"], source="f:%d" % i)
                for i in range(n)]

    def test_single_request_regardless_of_host_count(self):
        api = make_env(groups={"Linux servers": "1", "Prod": "2"},
                       templates={"Linux by Zabbix agent": "100"})
        r = z.Resolver(api)
        self.assertEqual(r.resolve(self._specs(300)), [])
        # ホスト 300 件でも hostgroup.get / template.get は 1 回ずつ
        self.assertEqual(api.count("hostgroup.get"), 1)
        self.assertEqual(api.count("template.get"), 1)
        self.assertEqual(api.call_count, 2)

    def test_missing_group_is_error_without_flag(self):
        api = make_env(groups={"Linux servers": "1"},
                       templates={"Linux by Zabbix agent": "100"})
        r = z.Resolver(api, create_groups=False)
        errors = r.resolve(self._specs(1))
        self.assertTrue(any("Prod" in e and "--create-groups" in e for e in errors))

    def test_missing_group_created_before_hosts(self):
        api = make_env(groups={"Linux servers": "1"},
                       templates={"Linux by Zabbix agent": "100"})
        r = z.Resolver(api, create_groups=True)
        self.assertEqual(r.resolve(self._specs(5)), [])
        self.assertEqual(r.created_groups, ["Prod"])
        self.assertIn("Prod", r.groups)
        methods = [m for m, _ in api.calls]
        # hostgroup.create がホスト作成より前（この時点でホスト系は未呼び出し）
        self.assertIn("hostgroup.create", methods)
        self.assertNotIn("host.create", methods)

    def test_missing_template_is_always_error(self):
        api = make_env(groups={"Linux servers": "1", "Prod": "2"}, templates={})
        errors = z.Resolver(api, create_groups=True).resolve(self._specs(1))
        self.assertTrue(any("テンプレート" in e for e in errors))

    def test_dry_run_does_not_create_groups(self):
        api = make_env(groups={"Linux servers": "1"},
                       templates={"Linux by Zabbix agent": "100"})
        r = z.Resolver(api, create_groups=True, dry_run=True)
        self.assertEqual(r.resolve(self._specs(1)), [])
        self.assertEqual(api.count("hostgroup.create"), 0)
        self.assertEqual(r.created_groups, ["Prod"])


# --------------------------------------------------------------------------
# UT-05: Planner（CREATE/UPDATE/NOOP、マージ、prune、id 引き継ぎ）
# --------------------------------------------------------------------------

def base_api():
    return make_env(groups={"Linux servers": "1", "Prod": "2", "Extra": "9"},
                    templates={"Linux by Zabbix agent": "100", "MySQL by Zabbix agent": "101"})


def spec_web01(**over):
    data = dict(host="web01", name="Web 01", groups=["Linux servers"],
                templates=["Linux by Zabbix agent"],
                interfaces=[z.InterfaceSpec(ip="192.168.1.11", port="10050")],
                tags=[{"tag": "env", "value": "prod"}],
                macros=[{"macro": "{$SITE}", "value": "tokyo", "type": 0}],
                source="f:2")
    data.update(over)
    return z.HostSpec(**data)


def existing_web01(**over):
    rec = {
        "hostid": "500", "host": "web01", "name": "Web 01", "status": 0,
        "description": "", "inventory_mode": 0,
        "monitored_by": 0, "proxyid": "0", "proxy_groupid": "0",
        "groups": [{"groupid": "1", "name": "Linux servers"}],
        "parentTemplates": [{"templateid": "100", "host": "Linux by Zabbix agent"}],
        "interfaces": [{"interfaceid": "700", "type": "1", "main": "1", "useip": "1",
                        "ip": "192.168.1.11", "dns": "", "port": "10050", "details": []}],
        "tags": [{"tag": "env", "value": "prod"}],
        "macros": [{"hostmacroid": "800", "macro": "{$SITE}", "value": "tokyo",
                    "type": "0", "description": ""}],
    }
    rec.update(over)
    return rec


class TestPlanner(unittest.TestCase):
    def _planner(self, api, hosts=None, **kw):
        api.hosts = {h["host"]: h for h in (hosts or [])}
        r = z.Resolver(api)
        # base_api の全グループ／全テンプレートを解決しておく
        r.resolve([spec_web01(groups=list(api.groups),
                              templates=list(api.templates))])
        return z.Planner(api, r, **kw)

    def test_create_when_absent(self):
        api = base_api()
        planner = self._planner(api)
        plan = planner.plan([spec_web01()])
        self.assertEqual(len(plan.creates), 1)
        params = plan.creates[0][1]
        self.assertEqual(params["host"], "web01")
        self.assertEqual(params["groups"], [{"groupid": "1"}])
        self.assertEqual(params["templates"], [{"templateid": "100"}])
        self.assertEqual(params["name"], "Web 01")
        self.assertEqual(params["interfaces"][0]["ip"], "192.168.1.11")
        self.assertEqual(params["monitored_by"], 0)

    def test_noop_when_identical(self):
        api = base_api()
        planner = self._planner(api, [existing_web01()])
        plan = planner.plan([spec_web01()])
        self.assertEqual((len(plan.creates), len(plan.updates), len(plan.noops)), (0, 0, 1))

    def test_update_name_only(self):
        api = base_api()
        planner = self._planner(api, [existing_web01()])
        plan = planner.plan([spec_web01(name="Web サーバー 01")])
        self.assertEqual(len(plan.updates), 1)
        _, params, changes = plan.updates[0]
        self.assertEqual(set(changes), {"name"})
        self.assertEqual(params["name"], "Web サーバー 01")
        self.assertEqual(params["hostid"], "500")

    def test_group_merge_is_additive_by_default(self):
        api = base_api()
        cur = existing_web01(groups=[{"groupid": "1", "name": "Linux servers"},
                                     {"groupid": "9", "name": "Extra"}])
        planner = self._planner(api, [cur])
        plan = planner.plan([spec_web01(groups=["Linux servers", "Prod"])])
        _, params, changes = plan.updates[0]
        gids = {g["groupid"] for g in params["groups"]}
        self.assertEqual(gids, {"1", "2", "9"})           # Extra は残る
        self.assertEqual(changes["groups"]["removed"], [])

    def test_group_prune_removes_extra(self):
        api = base_api()
        cur = existing_web01(groups=[{"groupid": "1", "name": "Linux servers"},
                                     {"groupid": "9", "name": "Extra"}])
        planner = self._planner(api, [cur], prune=True)
        plan = planner.plan([spec_web01(groups=["Linux servers"])])
        _, params, changes = plan.updates[0]
        self.assertEqual([g["groupid"] for g in params["groups"]], ["1"])
        self.assertEqual(changes["groups"]["removed"], ["9"])

    def test_template_prune_sets_templates_clear(self):
        api = base_api()
        cur = existing_web01(parentTemplates=[
            {"templateid": "100", "host": "Linux by Zabbix agent"},
            {"templateid": "101", "host": "MySQL by Zabbix agent"}])
        planner = self._planner(api, [cur], prune=True)
        plan = planner.plan([spec_web01()])
        _, params, changes = plan.updates[0]
        self.assertEqual(params["templates_clear"], [{"templateid": "101"}])

    def test_template_additive_has_no_clear(self):
        api = base_api()
        cur = existing_web01(parentTemplates=[
            {"templateid": "100", "host": "Linux by Zabbix agent"},
            {"templateid": "101", "host": "MySQL by Zabbix agent"}])
        planner = self._planner(api, [cur])
        plan = planner.plan([spec_web01()])
        self.assertEqual((len(plan.updates), len(plan.noops)), (0, 1))

    def test_tag_added(self):
        api = base_api()
        planner = self._planner(api, [existing_web01()])
        plan = planner.plan([spec_web01(tags=[{"tag": "env", "value": "prod"},
                                              {"tag": "role", "value": "web"}])])
        _, params, changes = plan.updates[0]
        self.assertEqual(changes["tags"]["added"], [{"tag": "role", "value": "web"}])
        self.assertEqual(len(params["tags"]), 2)

    def test_macro_value_change_keeps_hostmacroid(self):
        api = base_api()
        planner = self._planner(api, [existing_web01()])
        plan = planner.plan([spec_web01(
            macros=[{"macro": "{$SITE}", "value": "osaka", "type": 0}])])
        _, params, changes = plan.updates[0]
        self.assertEqual(changes["macros"]["changed"], ["{$SITE}"])
        self.assertEqual(params["macros"][0]["hostmacroid"], "800")
        self.assertEqual(params["macros"][0]["value"], "osaka")

    def test_macro_additive_keeps_unlisted(self):
        api = base_api()
        cur = existing_web01(macros=[
            {"hostmacroid": "800", "macro": "{$SITE}", "value": "tokyo", "type": "0",
             "description": ""},
            {"hostmacroid": "801", "macro": "{$MANUAL}", "value": "keep", "type": "0",
             "description": ""}])
        planner = self._planner(api, [cur])
        plan = planner.plan([spec_web01(
            macros=[{"macro": "{$NEW}", "value": "1", "type": 0}])])
        _, params, changes = plan.updates[0]
        ids = [m.get("hostmacroid") for m in params["macros"]]
        self.assertIn("800", ids)
        self.assertIn("801", ids)          # 未記載の既存マクロは維持
        self.assertEqual(changes["macros"]["added"], ["{$NEW}"])

    def test_macro_prune_removes_unlisted(self):
        api = base_api()
        cur = existing_web01(macros=[
            {"hostmacroid": "800", "macro": "{$SITE}", "value": "tokyo", "type": "0",
             "description": ""},
            {"hostmacroid": "801", "macro": "{$MANUAL}", "value": "gone", "type": "0",
             "description": ""}])
        planner = self._planner(api, [cur], prune=True)
        plan = planner.plan([spec_web01()])
        _, params, changes = plan.updates[0]
        self.assertEqual(changes["macros"]["removed"], ["{$MANUAL}"])
        self.assertEqual([m["hostmacroid"] for m in params["macros"]], ["800"])

    def test_secret_macro_not_touched_by_default(self):
        api = base_api()
        cur = existing_web01(macros=[
            {"hostmacroid": "800", "macro": "{$SITE}", "value": "tokyo", "type": "0",
             "description": ""},
            {"hostmacroid": "802", "macro": "{$PW}", "value": "", "type": "1",
             "description": ""}])
        spec = spec_web01(macros=[
            {"macro": "{$SITE}", "value": "tokyo", "type": 0},
            {"macro": "{$PW}", "value": "s3cret", "type": 1}])
        planner = self._planner(api, [cur])
        plan = planner.plan([spec])
        self.assertEqual(len(plan.noops), 1)   # secret は比較不能なので差分にしない

    def test_secret_macro_sent_with_force(self):
        api = base_api()
        cur = existing_web01(macros=[
            {"hostmacroid": "800", "macro": "{$SITE}", "value": "tokyo", "type": "0",
             "description": ""},
            {"hostmacroid": "802", "macro": "{$PW}", "value": "", "type": "1",
             "description": ""}])
        spec = spec_web01(macros=[
            {"macro": "{$SITE}", "value": "tokyo", "type": 0},
            {"macro": "{$PW}", "value": "s3cret", "type": 1}])
        planner = self._planner(api, [cur], force_secret=True)
        plan = planner.plan([spec])
        self.assertEqual(len(plan.updates), 1)
        _, params, _ = plan.updates[0]
        self.assertTrue(any(m.get("value") == "s3cret" for m in params["macros"]))

    def test_interface_ip_change_reuses_interfaceid(self):
        api = base_api()
        planner = self._planner(api, [existing_web01()])
        plan = planner.plan([spec_web01(
            interfaces=[z.InterfaceSpec(ip="192.168.1.99", port="10050")])])
        _, params, changes = plan.updates[0]
        self.assertEqual(params["interfaces"][0]["interfaceid"], "700")
        self.assertEqual(params["interfaces"][0]["ip"], "192.168.1.99")
        self.assertIn("interfaces", changes)

    def test_interface_identical_is_noop(self):
        api = base_api()
        planner = self._planner(api, [existing_web01()])
        plan = planner.plan([spec_web01()])
        self.assertEqual(len(plan.noops), 1)

    def test_fetch_existing_uses_one_request_per_chunk(self):
        api = base_api()
        api.hosts = {}
        r = z.Resolver(api)
        r.resolve([spec_web01()])
        planner = z.Planner(api, r, fetch_chunk=500)
        specs = [spec_web01(host="h%d" % i, source="f:%d" % i) for i in range(600)]
        planner.plan(specs)
        self.assertEqual(api.count("host.get"), 2)   # 600 件 → 500 + 100


# --------------------------------------------------------------------------
# UT-06: Executor（チャンク投入と失敗切り分け）
# --------------------------------------------------------------------------

class TestExecutor(unittest.TestCase):
    def _plan_for(self, api, specs):
        r = z.Resolver(api)
        r.resolve(specs)
        return z.Planner(api, r).plan(specs)

    def test_bulk_create_uses_chunks(self):
        api = base_api()
        specs = [spec_web01(host="h%03d" % i, name="", source="f:%d" % i) for i in range(120)]
        plan = self._plan_for(api, specs)
        results = z.Executor(api, chunk_size=50).apply(plan)
        self.assertEqual(z.Reporter.summary(results),
                         {"created": 120, "updated": 0, "noop": 0, "failed": 0})
        self.assertEqual(api.count("host.create"), 3)   # 50 + 50 + 20
        self.assertTrue(all(r.hostid for r in results))

    def test_failed_chunk_is_isolated_to_one_host(self):
        api = base_api()
        api.fail_hosts = {"h007"}
        specs = [spec_web01(host="h%03d" % i, name="", source="f:%d" % i) for i in range(50)]
        plan = self._plan_for(api, specs)
        results = z.Executor(api, chunk_size=50).apply(plan)
        counts = z.Reporter.summary(results)
        self.assertEqual(counts["created"], 49)
        self.assertEqual(counts["failed"], 1)
        failed = [r for r in results if r.action == "FAIL"]
        self.assertEqual(failed[0].host, "h007")
        self.assertIn("already exists", failed[0].error)
        # バルク 1 回 + 単体 50 回
        self.assertEqual(api.count("host.create"), 51)

    def test_dry_run_writes_nothing(self):
        api = base_api()
        specs = [spec_web01(host="h1", source="f:1")]
        plan = self._plan_for(api, specs)
        results = z.Executor(api, dry_run=True).apply(plan)
        self.assertEqual(results[0].action, "CREATE")
        self.assertEqual(api.count("host.create"), 0)

    def test_transport_error_does_not_double_create(self):
        api = base_api()
        specs = [spec_web01(host="h1", source="f:1")]
        plan = self._plan_for(api, specs)

        real_call = api.call
        state = {"raised": False}

        def flaky(method, params=None, auth=True):
            if method == "host.create" and not state["raised"]:
                state["raised"] = True
                # 実際には作成された後で応答が返らなかった状況を再現する
                real_call("host.create", params)
                raise z.ZabbixAPITransportError("timeout")
            return real_call(method, params, auth)

        api.call = flaky
        results = z.Executor(api, chunk_size=50).apply(plan)
        self.assertEqual(results[0].action, "CREATE")
        self.assertEqual(api.count("host.create"), 1)   # 二重作成されない

    def test_verify_marks_missing_as_fail(self):
        api = base_api()
        specs = [spec_web01(host="h1", source="f:1")]
        plan = self._plan_for(api, specs)
        ex = z.Executor(api, verify=True)
        results = ex.apply(plan)
        self.assertEqual(results[0].action, "CREATE")
        self.assertTrue(results[0].hostid)


# --------------------------------------------------------------------------
# UT-07: レポート／マスク
# --------------------------------------------------------------------------

class TestReporting(unittest.TestCase):
    def test_secret_value_is_masked(self):
        payload = {"macros": [{"macro": "{$PW}", "value": "s3cret", "type": 1},
                              {"macro": "{$SITE}", "value": "tokyo", "type": 0}]}
        masked = z._mask(payload)
        self.assertEqual(masked["macros"][0]["value"], z.SECRET_MASK)
        self.assertEqual(masked["macros"][1]["value"], "tokyo")

    def test_credentials_are_masked_in_logs(self):
        masked = z._mask({"username": "Admin", "password": "zabbix"})
        self.assertEqual(masked["password"], z.SECRET_MASK)
        self.assertEqual(masked["username"], "Admin")
        self.assertNotIn("zabbix", z._brief({"username": "Admin", "password": "zabbix"}))
        for key in ("token", "auth", "sessionid"):
            self.assertEqual(z._mask({key: "leak"})[key], z.SECRET_MASK)

    def test_summary_counts(self):
        results = [z.Result("a", "CREATE"), z.Result("b", "UPDATE"),
                   z.Result("c", "NOOP"), z.Result("d", "FAIL", error="x")]
        self.assertEqual(z.Reporter.summary(results),
                         {"created": 1, "updated": 1, "noop": 1, "failed": 1})

    def test_change_summary_text(self):
        text = z._summarize_changes({"name": {"from": "a", "to": "b"},
                                     "tags": {"added": [1], "removed": []},
                                     "macros": {"added": [], "changed": [1, 2],
                                                "removed": [3]}})
        self.assertIn("name", text)
        self.assertIn("tags(+1)", text)
        self.assertIn("macros(~2,-1)", text)

    def test_api_repr_hides_token(self):
        api = FakeAPI()
        # ZabbixAPI 本体の __repr__ を直接検証する
        obj = z.ZabbixAPI.__new__(z.ZabbixAPI)
        obj.url, obj.version, obj.token = "https://x/api_jsonrpc.php", "7.0.9", "supersecret"
        self.assertNotIn("supersecret", repr(obj))
        self.assertIn(z.SECRET_MASK, repr(obj))


# --------------------------------------------------------------------------
# IT-01 / IT-02: 結合（冪等性）
# --------------------------------------------------------------------------

class TestIdempotency(unittest.TestCase):
    def _apply(self, api, specs, **kw):
        r = z.Resolver(api, create_groups=True)
        errors = r.resolve(specs)
        self.assertEqual(errors, [])
        plan = z.Planner(api, r, **kw).plan(specs)
        results = z.Executor(api, chunk_size=25).apply(plan)
        return z.Reporter.summary(results), results

    def _specs(self):
        return [spec_web01(host="h%02d" % i, name="Host %02d" % i, source="f:%d" % i)
                for i in range(10)]

    def test_second_run_is_all_noop(self):
        api = base_api()
        api.hosts = {}
        counts, _ = self._apply(api, self._specs())
        self.assertEqual(counts["created"], 10)

        counts2, _ = self._apply(api, self._specs())
        self.assertEqual(counts2, {"created": 0, "updated": 0, "noop": 10, "failed": 0})

    def test_single_change_updates_only_that_host(self):
        api = base_api()
        api.hosts = {}
        self._apply(api, self._specs())

        specs = self._specs()
        specs[3].name = "Host 03 (renamed)"
        specs[3].tags = [{"tag": "env", "value": "prod"}, {"tag": "role", "value": "db"}]
        counts, results = self._apply(api, specs)
        self.assertEqual(counts, {"created": 0, "updated": 1, "noop": 9, "failed": 0})
        updated = [r for r in results if r.action == "UPDATE"][0]
        self.assertEqual(updated.host, "h03")
        self.assertEqual(set(updated.changes), {"name", "tags"})

        # さらにもう一度回すと差分は消える
        counts3, _ = self._apply(api, specs)
        self.assertEqual(counts3["noop"], 10)

    def test_zabbix_6x_compat_paths(self):
        api = make_env(version="6.0.30",
                       groups={"Linux servers": "1", "Prod": "2"},
                       templates={"Linux by Zabbix agent": "100"})
        api.hosts = {}
        counts, _ = self._apply(api, self._specs())
        self.assertEqual(counts["created"], 10)
        self.assertEqual(api.select_groups_key, "selectGroups")
        self.assertFalse(api.supports_monitored_by)
        # 6.x では monitored_by を送らない
        create_calls = [p for m, p in api.calls if m == "host.create"]
        for payload in create_calls:
            for obj in payload:
                self.assertNotIn("monitored_by", obj)


class TestAuthentication(unittest.TestCase):
    """ID/PW（user.login）と API トークンの両経路を検証する。"""

    def _api(self, fake, **kw):
        """ZabbixAPI の connect()/close() を FakeAPI の call() に載せて検証する。"""
        api = z.ZabbixAPI.__new__(z.ZabbixAPI)
        api.url = "http://mock/api_jsonrpc.php"
        api.token = kw.get("token")
        api.user = kw.get("user")
        api.password = kw.get("password")
        api.version, api.major, api.minor = "", 0, 0
        api.session_login = False
        api.call_count = 0
        api.call = lambda m, p=None, auth=True: fake.call(m, p, auth)
        return api

    def test_login_with_user_and_password(self):
        fake = FakeAPI()
        api = self._api(fake, user="Admin", password="zabbix")
        self.assertEqual(api.connect(), "7.0.9")
        self.assertTrue(api.token.startswith("sess-"))   # セッション ID を取得している
        self.assertTrue(api.session_login)
        self.assertEqual(api.auth_method, "user.login(session)")
        # 6.0 以降は username パラメータ
        params = dict(fake.calls)["user.login"]
        self.assertIn("username", params)
        self.assertNotIn("user", params)

    def test_login_uses_legacy_user_param_on_5x(self):
        fake = FakeAPI(version="5.0.40")
        api = self._api(fake, user="Admin", password="zabbix")
        api.connect()
        params = dict(fake.calls)["user.login"]
        self.assertIn("user", params)

    def test_wrong_password_raises(self):
        fake = FakeAPI()
        api = self._api(fake, user="Admin", password="wrong")
        with self.assertRaises(z.ZabbixAPIError):
            api.connect()

    def test_missing_credentials_raises(self):
        fake = FakeAPI()
        api = self._api(fake)
        with self.assertRaises(z.ZabbixAPIError) as ctx:
            api.connect()
        self.assertIn("ZABBIX_TOKEN", str(ctx.exception))

    def test_logout_invalidates_session(self):
        fake = FakeAPI()
        api = self._api(fake, user="Admin", password="zabbix")
        api.connect()
        api.close()
        self.assertEqual(fake.count("user.logout"), 1)
        self.assertEqual(fake.sessions, set())
        self.assertIsNone(api.token)

    def test_api_token_does_not_login_or_logout(self):
        fake = FakeAPI()
        api = self._api(fake, token="apitoken123")
        api.connect()
        api.close()
        self.assertEqual(fake.count("user.login"), 0)
        self.assertEqual(fake.count("user.logout"), 0)   # トークンは無効化しない
        self.assertEqual(api.token, "apitoken123")
        self.assertEqual(api.auth_method, "api-token")

    def test_close_is_safe_to_call_twice(self):
        fake = FakeAPI()
        api = self._api(fake, user="Admin", password="zabbix")
        api.connect()
        api.close()
        api.close()
        self.assertEqual(fake.count("user.logout"), 1)


class TestCliParser(unittest.TestCase):
    def test_plan_and_apply_subcommands(self):
        parser = z.build_parser()
        args = parser.parse_args(["plan", "a.csv", "--create-groups"])
        self.assertEqual(args.command, "plan")
        self.assertTrue(args.create_groups)
        args = parser.parse_args(["apply", "a.csv", "b.yaml", "--chunk-size", "10", "--prune"])
        self.assertEqual(args.inputs, ["a.csv", "b.yaml"])
        self.assertEqual(args.chunk_size, 10)
        self.assertTrue(args.prune)
        self.assertFalse(args.dry_run)

    def test_url_normalization(self):
        norm = z.ZabbixAPI._normalize_url
        self.assertEqual(norm("https://z.example.jp"), "https://z.example.jp/api_jsonrpc.php")
        self.assertEqual(norm("z.example.jp/zabbix/"),
                         "https://z.example.jp/zabbix/api_jsonrpc.php")
        self.assertEqual(norm("https://z/api_jsonrpc.php"), "https://z/api_jsonrpc.php")
        with self.assertRaises(z.ZabbixAPIError):
            norm("")


if __name__ == "__main__":
    unittest.main(verbosity=2)

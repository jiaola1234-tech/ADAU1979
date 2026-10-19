#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bd_ports.py —— Vivado Block Design (.bd) 网表合法性检查 / 修复工具

背景
----
Vivado 的 .bd 是 JSON。Netlist 里有一个硬性约束：
    **同一个 port/pin 只能属于一个 net。**

一个顶层"输入"端口同时驱动 IP 引脚和 ILA 探针是完全合法的，
但必须写在【同一个 net】的 ports 列表里，例如：

    "adau1979_capture_0_adau_bclk": {
      "ports": [ "adau1979_capture_0/adau_bclk", "adau_bclk", "ila_i2c_debug/probe4" ]
    },

如果被拆成两个 net 各引用一次，Vivado 在 upgrade_ip / validate_bd_design
触发全量校验时会报：

    [BD 41-149] Port <name> already has a connection

现象常被误判为"工程坏了 / 打不开"。手工或 Tcl 脚本改过 .bd 之后属于高发问题。

用法
----
    # 只检查（默认，不写盘）
    python tools/bd_ports.py
    python tools/bd_ports.py <path-to-design_1.bd>

    # 修复：把同一端口的多个 net 合并成一个（先自动备份 .bd）
    python tools/bd_ports.py --fix
    python tools/bd_ports.py --fix <path-to-design_1.bd>

退出码：0 = 无问题或修复成功；1 = 发现问题（未修复）或修复失败。
"""

import argparse
import io
import json
import shutil
import sys
import time

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

DEFAULT_BD = (
    r"C:\Users\weitong\Desktop\ADAU1979\vivado\ad_slave"
    r"\ad_slave.srcs\sources_1\bd\design_1\design_1.bd"
)


def find_duplicates(nets):
    """返回 {port_or_pin: [net_name, ...]}，只含出现次数 > 1 的。"""
    owner = {}
    for net_name, net in nets.items():
        for p in net.get("ports", []):
            owner.setdefault(p, []).append(net_name)
    return {k: v for k, v in owner.items() if len(v) > 1}


def repair(nets, dups):
    """把每个重复端口的多个 net 合并成一个（保留第一个 net 的名字与位置）。"""
    actions = []
    for name, net_names in dups.items():
        primary, others = net_names[0], net_names[1:]

        members = []
        for n in net_names:                       # 按出现顺序聚合，保持稳定
            for p in nets[n].get("ports", []):
                if p not in members:
                    members.append(p)

        # 合并出来的 net 以「重复的那个端口」开头更贴近 Vivado 自动命名习惯
        if name in members:
            members.remove(name)
            members.insert(0, name)

        old_primary = list(nets[primary].get("ports", []))
        nets[primary]["ports"] = members
        for n in others:
            del nets[n]

        actions.append((name, net_names, primary, old_primary, members))
    return actions


def main():
    ap = argparse.ArgumentParser(description="检查/修复 Vivado .bd 网表中的重复端口连接")
    ap.add_argument("bd", nargs="?", default=DEFAULT_BD, help="design_1.bd 的路径")
    ap.add_argument("--fix", action="store_true", help="执行修复（默认只检查）")
    args = ap.parse_args()

    print("=" * 78)
    print("BD 网表检查：%s" % args.bd)
    print("=" * 78)

    try:
        with open(args.bd, "r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        print("ERROR: 文件不存在")
        return 1
    except Exception as e:
        print("ERROR: JSON 解析失败：%r" % (e,))
        print("       文件可能已被写坏，请从 .bak 备份恢复。")
        return 1

    design = data.get("design", {})
    ports = design.get("ports", {})
    nets = design.get("nets", {})
    print("JSON 合法 | 顶层外部端口 %d 个 | net %d 个" % (len(ports), len(nets)))

    dups = find_duplicates(nets)
    if not dups:
        print("OK：没有被多个 net 引用的端口 —— 不会触发 [BD 41-149]")
        return 0

    print()
    print("发现 %d 个端口被多个 net 引用（会触发 [BD 41-149]）：" % len(dups))
    for name, net_names in sorted(dups.items()):
        tag = "  [顶层外部端口]" if name in ports else ""
        print("  %s%s" % (name, tag))
        for n in net_names:
            print("      <- net '%s' : %s" % (n, nets[n].get("ports")))

    if not args.fix:
        print()
        print("（只检查模式。加 --fix 可自动合并修复）")
        return 1

    print()
    print("-" * 78)
    print("开始修复：合并同一端口的多个 net")
    print("-" * 78)

    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = "%s.bak-%s" % (args.bd, stamp)
    shutil.copy2(args.bd, backup)
    print("已备份 -> %s" % backup)

    actions = repair(nets, dups)
    for name, net_names, primary, old_primary, members in actions:
        print("  %s" % name)
        for n in net_names[1:]:
            print("      删除 net '%s'" % n)
        print("      保留 net '%s' : %s" % (primary, old_primary))
        print("                 -> %s" % members)

    with open(args.bd, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

    # 写盘后复查
    with open(args.bd, "r", encoding="utf-8") as f:
        again = json.load(f)
    left = find_duplicates(again.get("design", {}).get("nets", {}))
    print()
    if left:
        print("ERROR: 修复后仍有 %d 处重复，请检查" % len(left))
        return 1
    print("修复完成并通过复查。恢复原文件请用备份：%s" % backup)
    return 0


if __name__ == "__main__":
    sys.exit(main())

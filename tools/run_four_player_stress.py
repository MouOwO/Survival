"""Run or reconcile the four-player simulation without touching a live game.

Each domain uses the same ten case parameters and its real production modules.
Engine and network boundaries are simulated; this is not four network clients.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output/four_player_stress_20261012"
SEEDS = [12011, 12037, 12071, 12109, 12143]
DIFFICULTIES = [1, 3, 6, 9, 10]
MAP_LEVELS = [[1, 9, 17, 24], [3, 12, 20, 30], [7, 16, 28, 34],
              [8, 18, 25, 32], [10, 19, 26, 33]]
SOURCES = [
    "scripts/vscripts/systems/building_upgrade_system.lua",
    "scripts/vscripts/systems/hero_combat_stat_service.lua",
    "scripts/vscripts/systems/building_health_projection.lua",
    "scripts/vscripts/systems/wave_system.lua",
    "scripts/vscripts/systems/wall_target_service.lua",
    "scripts/vscripts/modifiers/modifier_enemy_wall_ai.lua",
]
NAMES = {"technology": "technology", "waves": "wave_wall", "rewards": "reward"}


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def execute(domain: str):
    lua = os.environ.get("LUA_EXECUTABLE", "C:/Program Files/lua/bin/lua5.1.exe")
    commands = {
        "technology": [lua, "tools/test_four_player_technology_stress.lua", "--phase", "final"],
        "waves": [lua, "tools/test_four_player_wave_wall_stress.lua", "final"],
        "rewards": [sys.executable, "tools/test_four_player_reward_stress.py", "--phase", "final"],
    }
    with (OUTPUT / f"coordinator_{domain}_execution.log").open("wb") as stream:
        result = subprocess.run(commands[domain], cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
    return {"domain": domain, "exit_code": result.returncode}


def index_cases(domain: str, document: dict):
    result = {}
    for row in document["rounds"]:
        key = row.get("case_id", row.get("id"))
        if key is None:
            key = f"{row['scene']}{row['round']}"
        if key in result:
            raise ValueError(f"Duplicate case in {domain}: {key}")
        result[key] = row
    expected = {f"{scene}{round_}" for scene in "AB" for round_ in range(1, 6)}
    if set(result) != expected:
        raise ValueError(f"Incomplete case matrix in {domain}: {set(result)}")
    return result


def counts(domain: str, row: dict):
    if domain == "technology":
        return row["checks"], row["failed"] + len(row.get("engine_errors", []))
    if domain == "waves":
        return row["checks"], len(row["failures"])
    return row["checks"] + row["lua_checks"], len(row["bugs"]) + len(row.get("lua_failures", []))


def reconcile(phase: str, executions: list[dict]):
    documents = {domain: read(OUTPUT / f"{stem}_{phase}.json") for domain, stem in NAMES.items()}
    cases = {domain: index_cases(domain, doc) for domain, doc in documents.items()}
    rounds = []
    for scene in "AB":
        for number in range(1, 6):
            key = f"{scene}{number}"
            offset = number - 1
            expected_seed = SEEDS[offset] + (1000 if scene == "B" else 0)
            per_domain = {}
            for domain, matrix in cases.items():
                row = matrix[key]
                if row["seed"] != expected_seed or row["difficulty"] != f"N{DIFFICULTIES[offset]}":
                    raise ValueError(f"Case parameters diverged: {domain}/{key}")
                check_count, fail_count = counts(domain, row)
                per_domain[domain] = {"checks": check_count, "failures": fail_count,
                                      "passed": fail_count == 0}
            technology, waves, rewards = (cases[name][key] for name in NAMES)
            levels = [item["map_level"] for item in sorted(
                technology["player_matrix"], key=lambda item: item["player_id"])]
            reward_levels = [rewards["oracle"][str(player)]["map_level"] for player in range(4)]
            if levels != MAP_LEVELS[offset] or waves["map_levels"] != levels or reward_levels != levels:
                raise ValueError(f"Personal map levels diverged: {key}")
            account_ids = [item["account_id"] for item in technology["player_matrix"]]
            if len(set(account_ids)) != 4:
                raise ValueError(f"Non-independent player profiles: {key}")
            defender = offset % 4
            if scene == "B":
                actual_towers = [item["player_id"] for item in technology["player_matrix"] if item["tower_count"]]
                if actual_towers != [defender] or waves["tower_owners"] != [defender]:
                    raise ValueError(f"Wall-only teammate role violated: {key}")
            rounds.append({"case_id": key, "scenario": scene, "round": number,
                           "seed": expected_seed, "difficulty": f"N{DIFFICULTIES[offset]}",
                           "map_levels": levels, "sole_defender": defender if scene == "B" else None,
                           "domains": per_domain,
                           "checks": sum(item["checks"] for item in per_domain.values()),
                           "failures": sum(item["failures"] for item in per_domain.values()),
                           "passed": all(item["passed"] for item in per_domain.values())})
    release = read(OUTPUT / "reward_release_gap.json")
    baseline_manifest = {row["path"]: row["sha256"] for row in read(OUTPUT / "baseline_source_manifest.json")}
    source_hashes = {path: (baseline_manifest.get(path) if phase == "baseline" else
                           hashlib.sha256((ROOT / path).read_bytes()).hexdigest()) for path in SOURCES}
    result = {"date": "2026-10-12", "phase": phase,
              "validation_mode": "real_production_modules_with_simulated_engine_and_transport",
              "domain_execution": "same ten parameters; three isolated domain runs per case",
              "four_network_clients": False, "live_account_or_payment_writes": False,
              "rounds": rounds, "checks": sum(row["checks"] for row in rounds),
              "failures": sum(row["failures"] for row in rounds),
              "passed_rounds": sum(row["passed"] for row in rounds),
              "processes": executions,
              "release_pending": release["release_gap"],
              "current_runtime_archive_bundle": release["current_selected_bundle_hash"],
              "production_sha256": source_hashes,
              "boundaries": [
                  "Movement, navigation queries, collisions and delayed phase application use a deterministic engine model.",
                  "No four-client synchronization, real Workshop obstacle routing or GPU/frame-time measurement was performed.",
                  "Reward transport is local stdin/stdout; the Lua settlement worker runs against a local database fixture.",
                  "A/B combat roles limit towers; auxiliary hero/worker property and growth probes are separate from battle participation.",
                  "The tested new reward source bundle is not the currently selected deployed bundle.",
              ]}
    result["simulation_passed"] = result["passed_rounds"] == 10 and not any(p["exit_code"] for p in executions)
    (OUTPUT / f"coordinator_{phase}.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


def write_delivery(result: dict):
    report_path = ROOT / "docs/validation/four_player_stress_20261012.md"
    machine_path = ROOT / "validation/20261012/four_player_stress.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    machine_path.parent.mkdir(parents=True, exist_ok=True)
    baseline = read(OUTPUT / "coordinator_baseline.json")
    release = read(OUTPUT / "reward_release_ready.json")
    delivery = dict(result)
    delivery["baseline"] = {key: baseline[key] for key in ["checks", "failures", "passed_rounds", "production_sha256"]}
    delivery["release_preparation"] = release
    machine_path.write_text(json.dumps(delivery, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# 四人模拟压力测试与修复（2026-10-12）", "",
        f"两种场景各5轮，共10轮；最终{result['checks']:,}项检查通过，失败0。",
        "A为四方独立防守；B为同区四墙、一人造塔，防守者逐轮轮换。每轮使用4份不同档案、个人地图等级和科技数据，交错执行同一时钟下的操作。",
        "科技/档案、出怪/城墙AI、奖励三个域按相同case参数分别运行；不是一次包含四个客户端的完整对局。辅助英雄与工人句柄用于属性及成长归属检查，不将它们当作B场景的额外防守者。", "",
        "## 修复与验证", "",
        "| 问题 | 当前结果 |", "| --- | --- |",
        "| 墙和塔面板遗漏本人存档/地图等级加成 | 正确传递静态投影；实际属性、显示和成长来源分别核对。 |",
        "| 英雄实际攻击漏算智力攻击对应百分比，专属倍率下装备平加不足 | 原生属性接口模型与真实modifier消费者核对；含普通、专属、debug0、换装及大数缩放。 |",
        "| 墙生命因浮点误差少1 | 7541/8138固定数学例及252个Decimal对照通过；合法小数仍向下取整。 |",
        "| 怪物原主墙不可达/越界/死亡后没有改攻其他墙 | 优先可达原主墙，否则选择最近可达真实墙；隐藏、施工、失败玩家墙排除，控制期间延迟重选。 |",
        "| 集中防区仍从四个原始出生口出怪 | 已接入正式路由；每次4通道各一只，集中区使用对应口及错位出生位置，怪物归属/人口不变。 |",
        "| 新目标缓存把不同起点的路径结果混用 | 精确起点键；正反顺序独立负例均复现旧错误，修复后通过。 |",
        "| 当前线上奖励包没有共享基础随机结果 | 最新源码模拟通过；当前运行包未切换，此项仍待发布。 |", "",
        "旧源码负例保留；首轮失败没有通过放宽断言变成成功。正式建造边界之外的传送门箱被独立审查发现并移除，合法墙(256,6656)以及完整footprint边界均已验证。", "",
        "## 10轮结果", "",
        "| 场景 | seed | 全局难度 | 四人个人地图等级 | 检查 | 结果 |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for row in result["rounds"]:
        lines.append(f"| {row['case_id']} | {row['seed']} | {row['difficulty']} | {', '.join(map(str, row['map_levels']))} | {row['checks']:,} | PASS |")
    lines += [
        "", "全局局内难度与个人地图等级分别处理，没有拿队长地图等级覆盖队员。21种正式科技作用域已审阅；个人效果、明确的团队共享效果、当前/新建单位和资源账本都分别检查。",
        "", "## 怪物与奖励数据", "",
        "15组各360个怪物的运动/碰撞模型，共5400体，验证前排实际命中、后排间距及死亡替补。稳定观察期新增order、Stop、坐标修正及寻路查询均为0；墙状态观察共享，不按每只怪扫描全图。",
        "奖励final有1689项检查、1404个本地独立receipt，另160项客户端/数据库typed map核对。四人基础奖励各完整一份，不按人数除四；个人月卡、每日/持有上限、双倍通关和地图等级收益各自处理。重复事件、丢回包、失败重试、晚到档案及合格/不合格队员边界已检查。",
        "", "## 尚待发布", "",
        "当前运行规则包仍为 `310d3063…`。同一虚空之影4事件、4个无月卡账号的旧包本地复现得到不同基础物品，问题属于发布差距。",
        "完整源码测试包 `72cec817…` 通过10轮；只修改共享奖励、保留原经济配置的overlay `ea7babc0…` 另通过19项worker/兼容检查，二者不是同一个包。overlay位于 `output/four_player_stress_20261012/pkg/r-ea7babc0.tar.gz`。",
        "运行指针保持原值。overlay尚需与核实后的完整后端release合并；候选SQL的PostgreSQL回滚验证及线上发布未执行。[接入说明](../../output/four_player_stress_20261012/reward_release_ready.md)。",
        "", "## 验证范围与复跑", "",
        "这是实际生产Lua模块、真实奖励worker驱动的离线模拟；引擎句柄、原生移动/碰撞/寻路和HTTP/数据库边界使用模型。未测四客户端网络同步、Workshop障碍实体绕行或GPU帧耗时，不将模型通过写成实机不卡顿。",
        "相关检查包含12组wave/wall回归与8组通过的技术旧回归。技术域另3项旧检查仍失败，均以修改前源码复现相同失败；完整旧人口测试的外部fixture缺项也保留前后证据，原人口/失败/获胜名单断言单独通过。详见相应日志，不宣称全仓回归全部通过。",
        "", "```powershell",
        "python tools/run_four_player_stress.py --phase final --execute",
        "```", "",
        "上述命令执行同一10轮三个域。只复跑技术和城墙：`--execute technology waves`；仅汇总已保存结果：省略`--execute`。历史baseline只读取，不重写失败证据。",
        "", "[机器汇总](../../validation/20261012/four_player_stress.json)；[技术证据](../../output/four_player_stress_20261012/technology_final.json)；[城墙证据](../../output/four_player_stress_20261012/wave_wall_final.json)；[奖励证据](../../output/four_player_stress_20261012/reward_final.json)。",
        "", "## 修改范围", "",
    ]
    lines += [f"- `{path}`" for path in SOURCES]
    lines += ["", "另有四人测试入口、目标缓存回归、奖励打包工具及测试报告。现有`wall_melee_contact.lua`逐字节保留；本轮没有操作游戏窗口、网络发布、真实存档/支付或Git提交推送。"]
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=["baseline", "final"], default="final")
    parser.add_argument("--execute", nargs="*", choices=list(NAMES), help="Execute selected final domains; otherwise reconcile saved runs")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    executions = []
    if args.execute is not None:
        if args.phase != "final":
            parser.error("The historical baseline is immutable; use saved baseline reports.")
        with ThreadPoolExecutor(max_workers=3) as pool:
            executions = list(pool.map(execute, args.execute or list(NAMES)))
    result = reconcile(args.phase, executions)
    if args.phase == "final" and result["simulation_passed"]:
        write_delivery(result)
    print(json.dumps({key: result[key] for key in ["phase", "passed_rounds", "checks", "failures", "simulation_passed", "release_pending"]}))
    return 0 if result["simulation_passed"] or args.phase == "baseline" else 1


if __name__ == "__main__":
    raise SystemExit(main())

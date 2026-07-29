#!/usr/bin/env python3
"""Regression tests for the aggregate-only Codex decision-brief validator."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parent.parent
VALIDATOR_PATH = ROOT / "Scripts" / "install-codex-review.py"
SPEC = importlib.util.spec_from_file_location("codex_review_validator", VALIDATOR_PATH)
assert SPEC and SPEC.loader
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


def report(*, reliable: bool) -> dict:
    return {
        "schemaVersion": 6,
        "reportID": "focustrace-report",
        "reportDate": "2026-07-25T00:00:00+08:00",
        "reportCivilDate": "2026-07-25",
        "dataQuality": {"isReliableForBehavior": reliable},
        "phaseTwo": {"status": "locked"},
        "recommendation": {"kind": "maintainRound"},
    }


def review(*, status: str, problem: str) -> dict:
    return {
        "schemaVersion": 3,
        "sourceReportID": "focustrace-report",
        "reportDate": "2026-07-25T00:00:00+08:00",
        "generatedAt": "2026-07-25T18:35:00+08:00",
        "status": status,
        "problem": problem,
        "recommendation": "把当前桌面绑定到正在推进的工作流，并连续记录 30 分钟。",
        "evidence": ["工作流归因率 68%", "可靠门槛 70%"],
        "nextCheck": "下一工作日检查归因率是否达到 70%。",
        "analysisAudit": {
            "source": "localRecommendation" if status == "behaviorFinding" else "dataQuality",
            "selectedRoute": None,
            "contextRelation": "notApplicable",
        },
    }


class CodexReviewContractTests(unittest.TestCase):
    def test_current_v6_report_is_accepted(self) -> None:
        payload = review(
            status="behaviorFinding",
            problem="无计划工作流跳转形成了重复返回。",
        )
        self.assertEqual(
            VALIDATOR.validate(report(reliable=True), payload),
            "2026-07-25",
        )

    def test_legacy_v2_report_remains_accepted(self) -> None:
        source = report(reliable=True)
        source["schemaVersion"] = 2
        payload = review(
            status="behaviorFinding",
            problem="无计划工作流跳转形成了重复返回。",
        )
        payload["schemaVersion"] = 2
        payload.pop("analysisAudit")
        self.assertEqual(VALIDATOR.validate(source, payload), "2026-07-25")

    def test_workflow_route_must_exist_twice_in_native_aggregate(self) -> None:
        source = report(reliable=True)
        source["transitionAudit"] = {
            "dataSource": "semanticEvents",
            "routes": [
                {
                    "fromWorkflow": "等待 Agent",
                    "toWorkflow": "处理需求",
                    "reasonCounts": {"waitingForResult": 2},
                }
            ],
        }
        payload = review(
            status="behaviorFinding",
            problem="等待 Agent 到处理需求的交接没有保存返回点。",
        )
        payload["analysisAudit"] = {
            "source": "workflowRoute",
            "selectedRoute": {
                "fromWorkflow": "等待 Agent",
                "toWorkflow": "处理需求",
                "reason": "waitingForResult",
            },
            "contextRelation": "adjacentDeliverables",
        }
        self.assertEqual(VALIDATOR.validate(source, payload), "2026-07-25")

        payload["analysisAudit"]["selectedRoute"]["toWorkflow"] = "不存在的工作流"
        with self.assertRaisesRegex(ValueError, "至少两次聚合证据"):
            VALIDATOR.validate(source, payload)

    def test_partial_reliability_allows_local_action_but_blocks_workflow_route(self) -> None:
        source = report(reliable=True)
        source["dataQuality"]["analysisScopes"] = [
            {"lens": "dataQuality", "isReliable": True, "reason": "可说明范围"},
            {"lens": "fragmentation", "isReliable": True, "reason": "应用记录完整"},
            {"lens": "contextRecovery", "isReliable": True, "reason": "显式动作完整"},
            {"lens": "workflowSemantics", "isReliable": False, "reason": "覆盖不足"},
        ]
        local_payload = review(
            status="behaviorFinding",
            problem="今天还没有形成带结果反馈的专注训练样本。",
        )
        self.assertEqual(
            VALIDATOR.validate(source, local_payload),
            "2026-07-25",
        )

        source["transitionAudit"] = {
            "dataSource": "semanticEvents",
            "routes": [
                {
                    "fromWorkflow": "A",
                    "toWorkflow": "B",
                    "reasonCounts": {"unstructured": 2},
                }
            ],
        }
        route_payload = review(
            status="behaviorFinding",
            problem="A 到 B 的无结构切换形成重复返回。",
        )
        route_payload["analysisAudit"] = {
            "source": "workflowRoute",
            "selectedRoute": {
                "fromWorkflow": "A",
                "toWorkflow": "B",
                "reason": "unstructured",
            },
            "contextRelation": "differentGoals",
        }
        with self.assertRaisesRegex(ValueError, "工作流路线"):
            VALIDATOR.validate(source, route_payload)

    def test_switching_load_requires_a_supported_converging_status(self) -> None:
        source = report(reliable=True)
        source["switchingLoad"] = {
            "status": "elevated",
            "confidence": "medium",
            "boundary": "行为切换负荷估计，不是脑活动或临床测量",
            "evidence": [
                "工作流切换率较个人基线升高 30%",
                "高恢复负担切换 2 次",
            ],
        }
        payload = review(
            status="behaviorFinding",
            problem="跨工作流切换后的恢复负担高于个人近期基线。",
        )
        payload["analysisAudit"] = {
            "source": "switchingLoad",
            "selectedRoute": None,
            "contextRelation": "notApplicable",
        }
        self.assertEqual(VALIDATOR.validate(source, payload), "2026-07-25")

        source["switchingLoad"]["status"] = "calibrating"
        with self.assertRaisesRegex(ValueError, "切换负荷来源缺少收敛证据"):
            VALIDATOR.validate(source, payload)

    def test_v7_longitudinal_trend_can_drive_a_review_on_a_partial_day(self) -> None:
        source = report(reliable=False)
        source["schemaVersion"] = 7
        source["attentionTrend"] = {
            "reliableDimensionCount": 4,
            "includesPartialDay": True,
            "finding": {
                "state": "needsAttention",
                "title": "高碎片工作段正在持续增加",
                "detail": "高碎片工作段增加，并压缩连续工作时长。",
                "evidence": [
                    "近 3 日 50% · 此前典型 10%",
                    "连续工作：近 3 日 10 分钟 · 此前典型 20 分钟",
                ],
            },
            "recommendation": {
                "title": "把下一段高碎片工作改成单一产出块",
            },
        }
        payload = review(
            status="behaviorFinding",
            problem="高碎片工作段正在持续增加，并压缩连续工作时长。",
        )
        payload["recommendation"] = (
            "把下一段高碎片工作改成单一产出块：开始前写下唯一交付结果。"
        )
        payload["evidence"] = source["attentionTrend"]["finding"]["evidence"]
        payload["analysisAudit"] = {
            "source": "attentionTrend",
            "selectedRoute": None,
            "contextRelation": "notApplicable",
        }
        self.assertEqual(VALIDATOR.validate(source, payload), "2026-07-25")

        payload["evidence"] = ["今天切换很多"]
        with self.assertRaisesRegex(ValueError, "偏离了本地唯一问题"):
            VALIDATOR.validate(source, payload)

    def test_v7_stable_trend_blocks_an_invented_daily_problem(self) -> None:
        source = report(reliable=True)
        source["schemaVersion"] = 7
        source["attentionTrend"] = {
            "reliableDimensionCount": 1,
            "finding": {
                "state": "stable",
                "title": "1 个可靠趋势暂未持续恶化",
                "detail": "其余维度仍在校准。",
                "evidence": ["1/5 个维度已形成可比较趋势"],
            },
            "recommendation": {
                "title": "保持当前方法，不增加训练负荷",
            },
        }
        payload = review(
            status="behaviorFinding",
            problem="1 个可靠趋势暂未持续恶化，其余维度仍在校准。",
        )
        payload["recommendation"] = "保持当前方法，不增加训练负荷。"
        payload["evidence"] = ["1/5 个维度已形成可比较趋势"]
        payload["analysisAudit"] = {
            "source": "attentionTrend",
            "selectedRoute": None,
            "contextRelation": "notApplicable",
        }
        self.assertEqual(VALIDATOR.validate(source, payload), "2026-07-25")

        payload["problem"] = "今天应用切换偏多。"
        with self.assertRaisesRegex(ValueError, "偏离了本地唯一问题"):
            VALIDATOR.validate(source, payload)

    def test_v8_active_experiment_keeps_the_confirmed_action(self) -> None:
        source = report(reliable=True)
        source["schemaVersion"] = 8
        source["attentionExperiment"] = {
            "status": "active",
            "title": "把高碎片工作改成单一产出块",
            "hypothesis": "固定一个交付结果可以减少高碎片工作段",
            "nextAction": "下一次开始前写下唯一交付结果，并保持其他条件不变。",
            "nextCheck": "达到 3 个可靠样本后检查同一主指标",
            "evidence": [
                "可靠样本 1/3",
                "未入样：无机会 1、缺反馈 0、质量阻断 0",
            ],
        }
        payload = review(
            status="behaviorFinding",
            problem="把高碎片工作改成单一产出块，目前仍在收集可比样本。",
        )
        payload["recommendation"] = source["attentionExperiment"]["nextAction"]
        payload["evidence"] = source["attentionExperiment"]["evidence"]
        payload["nextCheck"] = source["attentionExperiment"]["nextCheck"]
        payload["analysisAudit"] = {
            "source": "attentionExperiment",
            "selectedRoute": None,
            "contextRelation": "notApplicable",
        }
        self.assertEqual(VALIDATOR.validate(source, payload), "2026-07-25")

        payload["recommendation"] = "今天再尝试一个新的番茄钟方法。"
        with self.assertRaisesRegex(ValueError, "改变了今天的唯一动作"):
            VALIDATOR.validate(source, payload)

    def test_unreliable_report_accepts_one_repair_action(self) -> None:
        payload = review(
            status="dataQualityBlocked",
            problem="工作流归因率只有 68%；当前不能据此判断注意力。",
        )
        self.assertEqual(
            VALIDATOR.validate(report(reliable=False), payload),
            "2026-07-25",
        )

    def test_unreliable_report_rejects_behavior_claim(self) -> None:
        payload = review(
            status="behaviorFinding",
            problem="今天的注意力表现有所下降。",
        )
        with self.assertRaisesRegex(ValueError, "dataQualityBlocked"):
            VALIDATOR.validate(report(reliable=False), payload)

    def test_report_filename_preserves_the_reports_own_civil_date(self) -> None:
        source = report(reliable=False)
        payload = review(
            status="dataQualityBlocked",
            problem="工作流归因率只有 68%；当前不能据此判断注意力。",
        )
        source["reportDate"] = "2026-07-25T00:30:00+14:00"
        payload["reportDate"] = source["reportDate"]

        self.assertEqual(VALIDATOR.validate(source, payload), "2026-07-25")

    def test_explicit_civil_date_survives_utc_json_encoding(self) -> None:
        source = report(reliable=False)
        payload = review(
            status="dataQualityBlocked",
            problem="工作流归因率只有 68%；当前不能据此判断注意力。",
        )
        source["reportDate"] = "2026-07-24T16:00:00Z"
        source["reportCivilDate"] = "2026-07-25"
        payload["reportDate"] = source["reportDate"]

        self.assertEqual(VALIDATOR.validate(source, payload), "2026-07-25")

    def test_repeated_evidence_and_filler_are_rejected(self) -> None:
        repeated = review(
            status="behaviorFinding",
            problem="训练执行是今天最主要的阻塞。",
        )
        repeated["evidence"] = ["今日训练 0 次", "今日训练0次"]
        with self.assertRaisesRegex(ValueError, "不能重复"):
            VALIDATOR.validate(report(reliable=True), repeated)

        filler = review(
            status="behaviorFinding",
            problem="总体来看，训练执行是今天最主要的阻塞。",
        )
        with self.assertRaisesRegex(ValueError, "空泛表达"):
            VALIDATOR.validate(report(reliable=True), filler)

    def test_locked_phase_two_progress_cannot_fill_the_review(self) -> None:
        payload = review(
            status="behaviorFinding",
            problem="阶段 2 尚未解锁。",
        )
        with self.assertRaisesRegex(ValueError, "阶段 2"):
            VALIDATOR.validate(report(reliable=True), payload)


if __name__ == "__main__":
    unittest.main()

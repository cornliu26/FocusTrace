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
        "schemaVersion": 5,
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
    def test_current_v5_report_is_accepted(self) -> None:
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

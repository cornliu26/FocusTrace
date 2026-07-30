#!/usr/bin/env python3
"""Validate and atomically install an aggregate-only Codex review artifact."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
from typing import Any


REVIEW_FIELDS_V2 = {
    "schemaVersion",
    "sourceReportID",
    "reportDate",
    "generatedAt",
    "status",
    "problem",
    "recommendation",
    "evidence",
    "nextCheck",
}
REVIEW_FIELDS_V3 = REVIEW_FIELDS_V2 | {"analysisAudit"}
REVIEW_STATUSES = {"behaviorFinding", "dataQualityBlocked"}
ANALYSIS_SOURCES = {
    "dataQuality",
    "workflowRoute",
    "previousRecommendation",
    "normalizedTrend",
    "attentionTrend",
    "attentionExperiment",
    "switchingLoad",
    "phaseTwo",
    "localRecommendation",
}
CONTEXT_RELATIONS = {
    "sameDeliverableToolChange",
    "adjacentDeliverables",
    "differentGoals",
    "insufficientEvidence",
    "notApplicable",
}
ROUTE_REASONS = {
    "checkpoint",
    "waitingForResult",
    "forcedInterruption",
    "unstructured",
}
RECOMMENDATION_LENSES = {
    "collectData": "dataQuality",
    "repairAttribution": "dataQuality",
    "verifySpaceTracking": "dataQuality",
    "startFocusRound": "fragmentation",
    "recoveryRound": "fragmentation",
    "maintainRound": "fragmentation",
    "agentParkingDrill": "contextRecovery",
}
FILLER_PHRASES = {
    "总体来看",
    "值得注意",
    "建议继续关注",
    "保持当前节奏",
    "FocusTrace 只把",
}


def parse_iso8601(value: str) -> dt.datetime:
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    parsed = dt.datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        raise ValueError("日期必须包含时区")
    return parsed


def require_text(payload: dict[str, Any], key: str, maximum: int) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{key} 必须是非空文本")
    if len(value) > maximum:
        raise ValueError(f"{key} 超过 {maximum} 字符")
    return value


def load_object(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path.name} 必须是 JSON 对象")
    return value


def normalized_text(value: str) -> str:
    return "".join(character.lower() for character in value if character.isalnum())


def report_civil_date(report: dict[str, Any]) -> str:
    explicit = report.get("reportCivilDate")
    if explicit is None:
        return parse_iso8601(require_text(report, "reportDate", 64)).strftime(
            "%Y-%m-%d"
        )
    if not isinstance(explicit, str):
        raise ValueError("reportCivilDate 必须是 yyyy-MM-dd")
    try:
        parsed = dt.date.fromisoformat(explicit)
    except ValueError as error:
        raise ValueError("reportCivilDate 必须是 yyyy-MM-dd") from error
    if parsed.isoformat() != explicit:
        raise ValueError("reportCivilDate 必须是 yyyy-MM-dd")
    return explicit


def lens_is_reliable(report: dict[str, Any], lens: str) -> bool:
    data_quality = report.get("dataQuality")
    if not isinstance(data_quality, dict):
        return False
    scopes = data_quality.get("analysisScopes")
    if isinstance(scopes, list):
        for scope in scopes:
            if (
                isinstance(scope, dict)
                and scope.get("lens") == lens
                and isinstance(scope.get("isReliable"), bool)
            ):
                return scope["isReliable"]
    if lens == "dataQuality":
        return True
    return data_quality.get("isReliableForBehavior") is True


def validate_analysis_audit(
    report: dict[str, Any],
    review: dict[str, Any],
    reliable: bool,
) -> None:
    if review["schemaVersion"] == 2:
        return
    audit = review.get("analysisAudit")
    if not isinstance(audit, dict) or set(audit) != {
        "source",
        "selectedRoute",
        "contextRelation",
    }:
        raise ValueError("analysisAudit 字段不匹配")
    source = audit.get("source")
    relation = audit.get("contextRelation")
    if source not in ANALYSIS_SOURCES:
        raise ValueError("analysisAudit.source 无效")
    if relation not in CONTEXT_RELATIONS:
        raise ValueError("analysisAudit.contextRelation 无效")

    selected_route = audit.get("selectedRoute")
    no_route = selected_route is None and relation == "notApplicable"
    if source == "dataQuality":
        if reliable or not no_route:
            raise ValueError("数据质量结论必须来自不可靠报告且不能选择路线")
        return
    if not reliable:
        raise ValueError("数据不可靠时只能选择 dataQuality")
    if source == "localRecommendation":
        recommendation = report.get("recommendation")
        recommendation_kind = (
            recommendation.get("kind")
            if isinstance(recommendation, dict)
            else None
        )
        lens = RECOMMENDATION_LENSES.get(recommendation_kind)
        if (
            not no_route
            or lens is None
            or lens == "dataQuality"
            or not lens_is_reliable(report, lens)
        ):
            raise ValueError("本地建议来源与聚合报告不匹配")
        return
    if source == "attentionExperiment":
        experiment = report.get("attentionExperiment")
        if (
            not no_route
            or not isinstance(experiment, dict)
            or experiment.get("status") != "active"
            or not isinstance(experiment.get("title"), str)
            or not experiment["title"].strip()
            or not isinstance(experiment.get("hypothesis"), str)
            or not experiment["hypothesis"].strip()
            or not isinstance(experiment.get("nextAction"), str)
            or not experiment["nextAction"].strip()
            or not isinstance(experiment.get("nextCheck"), str)
            or not experiment["nextCheck"].strip()
            or not isinstance(experiment.get("evidence"), list)
            or not experiment["evidence"]
        ):
            raise ValueError("进行中的注意力实验缺少可验证的行动或证据")
        problem_text = normalized_text(review.get("problem", ""))
        title = normalized_text(experiment["title"])
        hypothesis = normalized_text(experiment["hypothesis"])
        if title not in problem_text and hypothesis not in problem_text:
            raise ValueError("实验写回偏离了已确认的唯一问题")
        if (
            normalized_text(experiment["nextAction"])
            not in normalized_text(review.get("recommendation", ""))
        ):
            raise ValueError("实验写回改变了今天的唯一动作")
        if any(
            item not in experiment["evidence"]
            for item in review.get("evidence", [])
        ):
            raise ValueError("实验写回使用了实验之外的证据")
        if (
            normalized_text(experiment["nextCheck"])
            not in normalized_text(review.get("nextCheck", ""))
        ):
            raise ValueError("实验写回改变了验收条件")
        return
    if source == "previousRecommendation":
        previous = report.get("previousRecommendationEvaluation")
        if (
            not no_route
            or not isinstance(previous, dict)
            or previous.get("status") not in {"needsAdjustment", "notRun"}
        ):
            raise ValueError("上一项建议没有可行动的失败证据")
        return
    if source == "normalizedTrend":
        trend = report.get("trend")
        trend_fields = {
            "appSwitchRateDeltaPercent",
            "workflowSwitchRateDeltaPercent",
            "attributedRatioDeltaPoints",
            "medianFocusDeltaMinutes",
        }
        if (
            not no_route
            or not lens_is_reliable(report, "fragmentation")
            or not lens_is_reliable(report, "workflowSemantics")
            or not isinstance(trend, dict)
            or not isinstance(trend.get("baselineDays"), int)
            or trend["baselineDays"] < 2
            or not any(trend.get(field) is not None for field in trend_fields)
        ):
            raise ValueError("标准化趋势缺少两个可比工作日或有效变化")
        return
    if source == "attentionTrend":
        attention_trend = report.get("attentionTrend")
        finding = (
            attention_trend.get("finding")
            if isinstance(attention_trend, dict)
            else None
        )
        recommendation = (
            attention_trend.get("recommendation")
            if isinstance(attention_trend, dict)
            else None
        )
        if (
            not no_route
            or not isinstance(finding, dict)
            or finding.get("state")
            not in {"needsAttention", "stable", "improving"}
            or not isinstance(finding.get("evidence"), list)
            or not finding["evidence"]
            or not isinstance(recommendation, dict)
            or not isinstance(finding.get("title"), str)
            or not finding["title"].strip()
            or not isinstance(recommendation.get("title"), str)
            or not recommendation["title"].strip()
            or attention_trend.get("reliableDimensionCount", 0) < 1
        ):
            raise ValueError("纵向趋势来源缺少可靠结论与下一步")
        finding_evidence = finding["evidence"]
        if (
            normalized_text(finding.get("title", ""))
            not in normalized_text(review.get("problem", ""))
            or normalized_text(recommendation.get("title", ""))
            not in normalized_text(review.get("recommendation", ""))
            or any(
                item not in finding_evidence
                for item in review.get("evidence", [])
            )
        ):
            raise ValueError("纵向趋势写回偏离了本地唯一问题或证据")
        return
    if source == "switchingLoad":
        switching_load = report.get("switchingLoad")
        if (
            not no_route
            or not isinstance(switching_load, dict)
            or switching_load.get("status") not in {"mixedEvidence", "elevated"}
            or not isinstance(switching_load.get("evidence"), list)
            or not switching_load["evidence"]
        ):
            raise ValueError("切换负荷来源缺少收敛证据")
        return
    if source == "phaseTwo":
        phase_two = report.get("phaseTwo")
        if (
            not no_route
            or not lens_is_reliable(report, "workflowSemantics")
            or not isinstance(phase_two, dict)
            or phase_two.get("status") != "ready"
            or not (
                phase_two.get("insights")
                or phase_two.get("suggestionTitle")
            )
        ):
            raise ValueError("阶段 2 尚无可引用洞察")
        return

    if not isinstance(selected_route, dict) or set(selected_route) != {
        "fromWorkflow",
        "toWorkflow",
        "reason",
    }:
        raise ValueError("工作流路线字段不匹配")
    if relation == "notApplicable":
        raise ValueError("工作流路线必须记录上下文关系")
    from_workflow = selected_route.get("fromWorkflow")
    to_workflow = selected_route.get("toWorkflow")
    reason = selected_route.get("reason")
    if (
        not isinstance(from_workflow, str)
        or not from_workflow.strip()
        or not isinstance(to_workflow, str)
        or not to_workflow.strip()
        or reason not in ROUTE_REASONS
    ):
        raise ValueError("工作流路线内容无效")
    transition_audit = report.get("transitionAudit")
    if (
        not lens_is_reliable(report, "workflowSemantics")
        or not isinstance(transition_audit, dict)
        or transition_audit.get("dataSource") not in {"semanticEvents", "mixed"}
    ):
        raise ValueError("工作流路线缺少原生语义事件")
    routes = transition_audit.get("routes")
    if not isinstance(routes, list):
        raise ValueError("聚合报告缺少工作流路线")
    for route in routes:
        if (
            isinstance(route, dict)
            and route.get("fromWorkflow") == from_workflow
            and route.get("toWorkflow") == to_workflow
        ):
            reason_counts = route.get("reasonCounts")
            if (
                isinstance(reason_counts, dict)
                and isinstance(reason_counts.get(reason), int)
                and reason_counts[reason] >= 2
            ):
                return
    raise ValueError("所选工作流路线或理由没有至少两次聚合证据")


def validate(report: dict[str, Any], review: dict[str, Any]) -> str:
    if report.get("schemaVersion") not in {2, 3, 4, 5, 6, 7, 8}:
        raise ValueError("聚合报告 schemaVersion 必须是 2 至 8")
    schema_version = review.get("schemaVersion")
    if schema_version not in {2, 3}:
        raise ValueError("Codex 写回 schemaVersion 必须是 2 或 3")
    expected_fields = REVIEW_FIELDS_V3 if schema_version == 3 else REVIEW_FIELDS_V2
    if set(review) != expected_fields:
        unexpected = sorted(set(review) - expected_fields)
        missing = sorted(expected_fields - set(review))
        raise ValueError(f"Codex 写回字段不匹配；缺少 {missing}，多出 {unexpected}")

    report_id = require_text(report, "reportID", 160)
    source_report_id = require_text(review, "sourceReportID", 160)
    if source_report_id != report_id:
        raise ValueError("Codex 写回不是基于当前聚合报告")

    report_date = require_text(report, "reportDate", 64)
    review_date = require_text(review, "reportDate", 64)
    if review_date != report_date:
        raise ValueError("Codex 写回日期与聚合报告不一致")
    parse_iso8601(report_date)
    generated_at = parse_iso8601(require_text(review, "generatedAt", 64))
    review["generatedAt"] = generated_at.astimezone(dt.timezone.utc).replace(
        microsecond=0
    ).isoformat().replace("+00:00", "Z")

    status = require_text(review, "status", 32)
    if status not in REVIEW_STATUSES:
        raise ValueError("status 必须是 behaviorFinding 或 dataQualityBlocked")

    problem = require_text(review, "problem", 110)
    recommendation = require_text(review, "recommendation", 150)
    next_check = require_text(review, "nextCheck", 80)

    data_quality = report.get("dataQuality")
    if not isinstance(data_quality, dict):
        raise ValueError("聚合报告缺少 dataQuality")
    current_day_reliable = data_quality.get("isReliableForBehavior")
    if not isinstance(current_day_reliable, bool):
        raise ValueError("聚合报告缺少可靠性判断")
    attention_trend = report.get("attentionTrend")
    trend_finding = (
        attention_trend.get("finding")
        if isinstance(attention_trend, dict)
        else None
    )
    trend_reliable = (
        isinstance(trend_finding, dict)
        and trend_finding.get("state")
        in {"needsAttention", "stable", "improving"}
        and isinstance(attention_trend.get("reliableDimensionCount"), int)
        and attention_trend["reliableDimensionCount"] > 0
    )
    reliable = current_day_reliable or trend_reliable
    if reliable and status != "behaviorFinding":
        raise ValueError("数据可靠时 status 必须是 behaviorFinding")
    if not reliable:
        if status != "dataQualityBlocked":
            raise ValueError("数据不可靠时 status 必须是 dataQualityBlocked")
        if "当前不能据此判断注意力" not in problem:
            raise ValueError("数据不可靠时 problem 必须明确拒绝注意力判断")

    evidence = review.get("evidence")
    if not isinstance(evidence, list) or not 1 <= len(evidence) <= 2:
        raise ValueError("evidence 必须包含一至两条聚合证据")
    for index, item in enumerate(evidence):
        if not isinstance(item, str) or not item.strip() or len(item) > 80:
            raise ValueError(f"evidence[{index}] 必须是 1–80 字符的文本")
    normalized_evidence = [normalized_text(item) for item in evidence]
    if len(set(normalized_evidence)) != len(normalized_evidence):
        raise ValueError("evidence 不能重复")

    displayed_text = [problem, recommendation, *evidence, next_check]
    if sum(len(item) for item in displayed_text) > 360:
        raise ValueError("Codex 写回正文超过 360 字符")
    for phrase in FILLER_PHRASES:
        if any(phrase in item for item in displayed_text):
            raise ValueError(f"Codex 写回包含空泛表达：{phrase}")
    if normalized_text(problem) == normalized_text(recommendation):
        raise ValueError("problem 与 recommendation 不能重复")

    phase_two = report.get("phaseTwo")
    if (
        isinstance(phase_two, dict)
        and phase_two.get("status") == "locked"
        and any("阶段 2" in item or "阶段2" in item for item in displayed_text)
    ):
        raise ValueError("阶段 2 未解锁时不能用解锁进度填充每日结论")

    validate_analysis_audit(report, review, reliable)
    return report_civil_date(report)


def write_atomically(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--review", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    arguments = parser.parse_args()

    report = load_object(arguments.report)
    review = load_object(arguments.review)
    date_stamp = validate(report, review)

    dated_path = arguments.output_dir / f"codex-{date_stamp}.json"
    latest_path = arguments.output_dir / "codex-latest.json"
    write_atomically(dated_path, review)
    write_atomically(latest_path, review)
    print(dated_path)


if __name__ == "__main__":
    try:
        main()
    except (OSError, json.JSONDecodeError, ValueError) as error:
        raise SystemExit(f"Codex 写回校验失败：{error}") from None

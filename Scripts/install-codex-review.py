#!/usr/bin/env python3
"""Validate and atomically install an aggregate-only Codex review artifact."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
from typing import Any


REVIEW_FIELDS = {
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
REVIEW_STATUSES = {"behaviorFinding", "dataQualityBlocked"}
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


def validate(report: dict[str, Any], review: dict[str, Any]) -> str:
    if report.get("schemaVersion") != 2:
        raise ValueError("聚合报告 schemaVersion 不是 2")
    if set(review) != REVIEW_FIELDS:
        unexpected = sorted(set(review) - REVIEW_FIELDS)
        missing = sorted(REVIEW_FIELDS - set(review))
        raise ValueError(f"Codex 写回字段不匹配；缺少 {missing}，多出 {unexpected}")
    if review.get("schemaVersion") != 2:
        raise ValueError("Codex 写回 schemaVersion 必须是 2")

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
    reliable = data_quality.get("isReliableForBehavior")
    if not isinstance(reliable, bool):
        raise ValueError("聚合报告缺少可靠性判断")
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

    return parse_iso8601(report_date).astimezone().strftime("%Y-%m-%d")


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

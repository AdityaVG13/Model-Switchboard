from __future__ import annotations

from typing import TypedDict

ProfileEnv = dict[str, str]


class ControllerIntegrationPayload(TypedDict):
    id: str
    display_name: str
    kind: str
    capabilities: list[str]
    sync_label: str
    description: str


class ModelProfileStatusPayloadBase(TypedDict):
    profile: str
    display_name: str
    runtime: str
    host: str
    port: str
    base_url: str
    request_model: str
    server_model_id: str
    pid: int | None
    running: bool
    ready: bool
    server_ids: list[str]
    rss_mb: float | None
    command: str | None
    log_path: str
class ModelProfileStatusPayload(ModelProfileStatusPayloadBase, total=False):
    runtime_label: str
    runtime_tags: list[str]
    launch_mode: str


class BenchmarkPrefillCasePayload(TypedDict):
    """One prefill-scaling measurement (e.g. the 1k/4k/8k cases of the context suite)."""

    label: str
    prompt_est_tokens: int | None
    ttft_ms: float | None
    decode_tokens_per_sec: float | None


class BenchmarkLatestRowPayloadBase(TypedDict):
    profile: str | None
    runtime: str | None
    ttft_ms: float | None
    decode_tokens_per_sec: float | None
    e2e_tokens_per_sec: float | None
    rss_mb: float | int | None


class BenchmarkLatestRowPayload(BenchmarkLatestRowPayloadBase, total=False):
    prefill_cases: list[BenchmarkPrefillCasePayload]


class BenchmarkLatestReportPayload(TypedDict):
    generated_at: str | None
    suite: str | None
    profiles: list[str]
    rows: list[BenchmarkLatestRowPayload]
    json_path: str
    markdown_path: str


class BenchmarkStatusPayload(TypedDict):
    running: bool
    pid: int | None
    log_path: str
    latest: BenchmarkLatestReportPayload | None


class ControllerStatusPayload(TypedDict):
    statuses: list[ModelProfileStatusPayload]
    benchmark: BenchmarkStatusPayload
    integrations: list[ControllerIntegrationPayload]
    profiles_dir: str
    controller_root: str


class CachedControllerStatusPayload(ControllerStatusPayload):
    cached_at: str


class ControllerActionResponsePayloadBase(ControllerStatusPayload):
    ok: bool


class ControllerActionResponsePayload(ControllerActionResponsePayloadBase, total=False):
    error: str


class LaunchAgentStatusPayload(TypedDict):
    plist_path: str
    installed: bool
    running: bool


class ControllerHeartbeatPayload(TypedDict):
    url: str
    reachable: bool
    profiles: int
    integrations: int


class ProfileDiagnosticPayload(TypedDict):
    profile: str
    display_name: str
    runtime: str
    runtime_label: str
    runtime_tags: list[str]
    launch_mode: str
    errors: list[str]
    warnings: list[str]
    running: bool
    ready: bool
    pid: int | None
    base_url: str


class DoctorFindingPayload(TypedDict, total=False):
    id: str
    severity: str
    subsystem: str
    message: str
    evidence: str
    remediation: str
    auto_fixable: bool
    fixer: str | None
    online_required: bool


class DoctorReportPayload(TypedDict, total=False):
    controller: ControllerHeartbeatPayload
    launch_agent: LaunchAgentStatusPayload
    integrations: list[ControllerIntegrationPayload]
    profiles_dir: str
    controller_root: str
    profiles: list[ProfileDiagnosticPayload]
    schema_version: str
    doctor_contract_version: str
    tool_version: str
    generated_at: str
    healthy: bool
    findings: list[DoctorFindingPayload]
    next_steps: list[str]


class PromptSpec(TypedDict):
    name: str
    category: str
    prompt: str
    max_tokens: int


class StreamResultPayloadBase(TypedDict):
    prompt_tokens: int | None
    completion_tokens: int | None
    ttft_ms: float | None
    total_ms: float | None
    decode_tokens_per_sec: float | None
    e2e_tokens_per_sec: float | None
    content: str
    usage_source: str


class StreamResultPayload(StreamResultPayloadBase, total=False):
    error: str


class CategorySummaryPayload(TypedDict):
    category: str
    cases: list[str]
    ttft_ms: float | None
    total_ms: float | None
    decode_tokens_per_sec: float | None
    e2e_tokens_per_sec: float | None


class BenchmarkCaseResultPayload(StreamResultPayload):
    benchmark: str
    category: str
    prompt: str
    prompt_est_tokens: int
    max_tokens: int
    output_preview: str


class BenchmarkAveragesPayload(TypedDict):
    ttft_ms: float | None
    total_ms: float | None
    decode_tokens_per_sec: float | None
    e2e_tokens_per_sec: float | None


class BenchmarkProfilePayload(TypedDict):
    profile: str
    display_name: str
    runtime: str
    request_model: str
    base_url: str
    pid: int | None
    rss_mb: float | None
    warmup: StreamResultPayload
    results: list[BenchmarkCaseResultPayload]
    averages: BenchmarkAveragesPayload
    category_averages: list[CategorySummaryPayload]


class BenchmarkRunReportPayload(TypedDict):
    generated_at: str
    suite: str
    temperature: float
    profiles: list[str]
    isolate: bool
    benchmarks: list[BenchmarkProfilePayload]


def make_controller_status_payload(
    *,
    statuses: list[ModelProfileStatusPayload],
    benchmark: BenchmarkStatusPayload,
    integrations: list[ControllerIntegrationPayload],
    profiles_dir: str,
    controller_root: str,
) -> ControllerStatusPayload:
    return {
        "statuses": statuses,
        "benchmark": benchmark,
        "integrations": integrations,
        "profiles_dir": profiles_dir,
        "controller_root": controller_root,
    }


def make_action_response_payload(
    *,
    statuses: list[ModelProfileStatusPayload],
    benchmark: BenchmarkStatusPayload,
    integrations: list[ControllerIntegrationPayload],
    profiles_dir: str,
    controller_root: str,
    ok: bool = True,
    error: str | None = None,
) -> ControllerActionResponsePayload:
    payload: ControllerActionResponsePayload = {
        "ok": ok,
        "statuses": statuses,
        "benchmark": benchmark,
        "integrations": integrations,
        "profiles_dir": profiles_dir,
        "controller_root": controller_root,
    }
    if error:
        payload["error"] = error
    return payload


def make_cached_status_payload(*, cached_at: str, payload: ControllerStatusPayload) -> CachedControllerStatusPayload:
    return {
        "cached_at": cached_at,
        **payload,
    }

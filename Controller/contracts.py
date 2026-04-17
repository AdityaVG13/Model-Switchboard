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


class ModelProfileStatusPayload(TypedDict):
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


class BenchmarkLatestRowPayload(TypedDict):
    profile: str | None
    runtime: str | None
    ttft_ms: float | None
    decode_tokens_per_sec: float | None
    e2e_tokens_per_sec: float | None
    rss_mb: float | int | None


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
    errors: list[str]
    warnings: list[str]
    running: bool
    ready: bool
    pid: int | None
    base_url: str


class DoctorReportPayload(TypedDict):
    controller: ControllerHeartbeatPayload
    launch_agent: LaunchAgentStatusPayload
    integrations: list[ControllerIntegrationPayload]
    profiles_dir: str
    controller_root: str
    profiles: list[ProfileDiagnosticPayload]


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

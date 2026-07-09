#!/usr/bin/env python3
"""Model Switchboard controller CLI/HTTP entrypoint.

Implementation lives in the `msctl` package. This module remains the stable
import path for tests, launchd, and sibling scripts.

Functions are rebound into this module so `mock.patch.object(MODULE, name)`
affects the same globals the HTTP handler and lifecycle helpers close over.
"""
from __future__ import annotations

import json
import os
import pathlib
import signal
import subprocess
import sys
import threading
import time
import types
import urllib.error
import urllib.parse
import urllib.request
from http.server import ThreadingHTTPServer

from profile_env import ProfileFormatError, load_env_profile, load_json_profile, load_profile

from msctl import agent_contracts as _agent
from msctl import benchmarks as _bench
from msctl import cli as _cli
from msctl import doctor as _doctor
from msctl import mutations as _mutations
from msctl import paths as _paths
from msctl import profiles as _profiles
from msctl import runtimes as _runtimes
from msctl import security as _security
from msctl import web as _web


def _rebind(fn):
    if not isinstance(fn, types.FunctionType):
        return fn
    rebound = types.FunctionType(
        fn.__code__,
        globals(),
        name=fn.__name__,
        argdefs=fn.__defaults__,
        closure=fn.__closure__,
    )
    rebound.__kwdefaults__ = fn.__kwdefaults__
    rebound.__annotations__ = dict(getattr(fn, "__annotations__", {}) or {})
    rebound.__dict__.update(fn.__dict__)
    rebound.__module__ = __name__
    rebound.__doc__ = fn.__doc__
    return rebound


def _unwrap(fn):
    while hasattr(fn, "__wrapped__"):
        fn = fn.__wrapped__
    return fn


def _rebind_class(cls):
    namespace = {
        k: v
        for k, v in cls.__dict__.items()
        if k not in {"__dict__", "__module__", "__weakref__"}
    }
    for key, value in list(namespace.items()):
        if isinstance(value, types.FunctionType):
            namespace[key] = _rebind(value)
        elif isinstance(value, staticmethod) and isinstance(value.__func__, types.FunctionType):
            namespace[key] = staticmethod(_rebind(value.__func__))
        elif isinstance(value, classmethod) and isinstance(value.__func__, types.FunctionType):
            namespace[key] = classmethod(_rebind(value.__func__))
    namespace["__module__"] = __name__
    return type(cls.__name__, cls.__bases__, namespace)


# Non-callable exports first.
for _mod in (_paths, _security, _runtimes, _profiles, _mutations, _bench, _doctor, _agent, _web, _cli):
    for _name, _value in vars(_mod).items():
        if _name.startswith("__"):
            continue
        if isinstance(_value, types.FunctionType):
            continue
        if isinstance(_value, type) and getattr(_value, "__module__", "").startswith("msctl."):
            continue
        globals()[_name] = _value

_MIN_PID_MARKER_LEN = _paths._MIN_PID_MARKER_LEN
_WATCHDOG_SUPPRESS_UNTIL = _paths._WATCHDOG_SUPPRESS_UNTIL
# Rebound security helpers that mutate `_paths._WATCHDOG_SUPPRESS_UNTIL` need this name.
_paths = _paths

# Rebind callables/classes into this module's globals.
for _mod in (_security, _runtimes, _profiles, _mutations, _bench, _doctor, _agent, _web, _cli):
    for _name, _value in vars(_mod).items():
        if _name.startswith("__"):
            continue
        if isinstance(_value, types.FunctionType):
            globals()[_name] = _rebind(_unwrap(_value))
        elif isinstance(_value, type) and getattr(_value, "__module__", "").startswith("msctl."):
            globals()[_name] = _rebind_class(_value)

# Re-apply mutation locks against rebound implementations.
for _name in ("start_profile", "stop_profile", "restart_profile", "stop_all", "switch_profile", "start_benchmark"):
    globals()[_name] = with_mutation_lock(globals()[_name])


def suppress_active_profile_watchdog(seconds: float = 45.0) -> None:
    global _WATCHDOG_SUPPRESS_UNTIL
    _paths._WATCHDOG_SUPPRESS_UNTIL = max(_paths._WATCHDOG_SUPPRESS_UNTIL, time.time() + seconds)
    _WATCHDOG_SUPPRESS_UNTIL = _paths._WATCHDOG_SUPPRESS_UNTIL


def is_active_profile_watchdog_suppressed() -> bool:
    global _WATCHDOG_SUPPRESS_UNTIL
    _paths._WATCHDOG_SUPPRESS_UNTIL = float(_WATCHDOG_SUPPRESS_UNTIL)
    return time.time() < _paths._WATCHDOG_SUPPRESS_UNTIL


DashboardHandler = _rebind_class(_web.DashboardHandler)
serve_web = _rebind(_web.serve_web)
main = _rebind(_cli.main)
build_parser = _rebind(_cli.build_parser)
handle_doctor = _rebind(_cli.handle_doctor)
AgentArgumentParser = _rebind_class(_cli.AgentArgumentParser)

if __name__ == "__main__":
    raise SystemExit(main())

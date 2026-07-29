#!/usr/bin/env bash
# Shared loopback controller endpoint defaults for shell tooling.
# Keep in sync with Sources/ModelSwitchboardCore/ControllerEndpointDefaults.swift.
# shellcheck shell=bash

CONTROLLER_ENDPOINT_HOST="${CONTROLLER_ENDPOINT_HOST:-127.0.0.1}"
CONTROLLER_ENDPOINT_PORT="${CONTROLLER_ENDPOINT_PORT:-8877}"
CONTROLLER_ENDPOINT_BASE_URL="${CONTROLLER_ENDPOINT_BASE_URL:-http://${CONTROLLER_ENDPOINT_HOST}:${CONTROLLER_ENDPOINT_PORT}}"
CONTROLLER_ENDPOINT_USER_DEFAULTS_KEY="${CONTROLLER_ENDPOINT_USER_DEFAULTS_KEY:-controllerBaseURL}"

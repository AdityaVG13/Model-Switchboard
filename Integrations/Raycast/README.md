# Raycast Integration

Model Switchboard ships a small controller CLI plus a few Raycast Script Commands for operators who prefer keyboard-driven local model control.

## What to point Raycast at

Add this directory as a Raycast Script Commands folder:

- `Integrations/Raycast/Script Commands`

Raycast will index the scripts after you add the directory or run `Reload Script Directories`.

## Available commands

- `Model Switchboard Status`
- `Open Model Switchboard`
- `Open Profiles Folder`
- `Stop All Local Models`
- `Quick Bench All Models`

## Environment overrides

These scripts default to `http://127.0.0.1:8877`.

Optional environment variables:

- `MODEL_SWITCHBOARD_URL`
- `MODEL_SWITCHBOARD_APP_PATH`

If you move the controller or app bundle, set those in the script or your shell environment.

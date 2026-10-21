# Upgrading a consuming project

## v3.3.3-rebuild

For an environment that already includes `agy`, update the Claude and Codex
session-start hooks and start a
new agent session. WIP paths containing spaces now keep their task names and
README context. No container rebuild is needed for this hook-only change: the
hooks run from the mounted checkout, not from the image.

### Upgrading from v3.2.0 — container rebuild required

The image adds `agy`; Compose adds `gemini-config` and `antigravity-secrets`
volumes, and the healthcheck runs `agy --version`. This release also corrects
the installer's log prefix display.

1. Merge the template's [.devcontainer/ changes](https://github.com/mememade-github/polyagent-devcontainer/compare/v3.2.0...v3.3.3-rebuild)
   into your project's configuration before rebuilding.
2. Rebuild the image from the merged configuration, then recreate and start the container.
3. Run `agy` inside the started container and complete the [first login](README.md#agents-and-first-login).
4. Update your custom `.claude/rules/` files and regenerate the mirror using the
   [rule registration procedure](REFERENCE.md#registering-deeper-rule-folders).

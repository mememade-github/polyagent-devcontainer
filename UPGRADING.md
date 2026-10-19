# Upgrading a consuming project

## v3.3.1-rebuild — container rebuild required

The image adds `agy`; Compose adds `gemini-config` and `antigravity-secrets`
volumes, and the healthcheck runs `agy --version`.

1. Merge the template's [.devcontainer/ changes](https://github.com/mememade-github/polyagent-devcontainer/compare/v3.2.0...v3.3.1-rebuild)
   into your project's configuration before rebuilding.
2. Rebuild the container.
3. Run `agy` and complete the first login as described in [Quick start](README.md#quick-start).
4. Update your custom `.claude/rules/` files and regenerate the mirror using the
   [rule registration procedure](REFERENCE.md#registering-deeper-rule-folders).

# Upgrading a consuming project

## v3.3.2-rebuild — container rebuild required

The image adds `agy`; Compose adds `gemini-config` and `antigravity-secrets`
volumes, and the healthcheck runs `agy --version`. This release also corrects
the installer's log prefix display.

1. Merge the template's [.devcontainer/ changes](https://github.com/mememade-github/polyagent-devcontainer/compare/v3.2.0...v3.3.2-rebuild)
   into your project's configuration before rebuilding.
2. Rebuild the image from the merged configuration, then recreate and start the container.
3. Run `agy` inside the started container and complete the [first login](README.md#agents-and-first-login).
4. Update your custom `.claude/rules/` files and regenerate the mirror using the
   [rule registration procedure](REFERENCE.md#registering-deeper-rule-folders).

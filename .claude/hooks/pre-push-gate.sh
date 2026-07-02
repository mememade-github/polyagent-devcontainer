#!/bin/bash
# PreToolUse hook (matcher: Bash): git push safety gate
# 3-layer progressive hardening — works from initial state, no declaration needed.
#
# Layer 1: PAT residue in remote URL → BLOCK (exit 2)
# Layer 2: Remote URL drift from baseline → WARN (stderr feedback)
# Layer 3: .push-remote declaration mismatch → BLOCK (exit 2, opt-in)
#
# Uses exit code 2 + stderr for reliable blocking per official docs:
#   "Exit 2 means a blocking error. stderr text is fed back to Claude."
# Reference: https://code.claude.com/docs/en/hooks#exit-code-output

INPUT=$(cat)
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq is required to parse hook input safely." >&2
  exit 2
fi
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

if ! command -v python3 >/dev/null 2>&1; then
  if echo "$COMMAND" | grep -qE '(^|[^A-Za-z0-9_])git([^;&|]*[[:space:]])push([^A-Za-z0-9_]|$)'; then
    echo "Blocked: python3 is required to parse git push commands safely." >&2
    exit 2
  fi
  exit 0
fi

parse_git_push() {
  python3 - "$COMMAND" "$PROJECT_DIR" <<'PY'
import json
import os
import re
import shlex
import sys

command, base_dir = sys.argv[1], sys.argv[2]
separators = {"&&", "||", ";", "|", "&", "(", ")"}
redir_ops = {"<", ">", "<<", ">>", "<>", "<&", ">&", ">|"}
assignment_re = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*")
unsafe_git_env_re = re.compile(
    r"^(GIT_DIR|GIT_WORK_TREE|GIT_COMMON_DIR|GIT_INDEX_FILE|"
    r"GIT_CONFIG|GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM|GIT_CONFIG_NOSYSTEM|"
    r"GIT_CONFIG_NOGLOBAL|GIT_CONFIG_COUNT|GIT_CONFIG_KEY_[0-9]+|"
    r"GIT_CONFIG_VALUE_[0-9]+|GIT_CONFIG_PARAMETERS)="
)
global_value_opts = {
    "-c", "--config", "--config-env", "--git-dir", "--namespace", "--exec-path"
}
global_value_prefixes = (
    "--config=", "--config-env=", "--git-dir=", "--namespace=", "--exec-path="
)
push_value_opts = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}
push_value_prefixes = ("--push-option=", "--repo=", "--receive-pack=", "--exec=")

def abspath(path, cwd):
    return os.path.abspath(path if os.path.isabs(path) else os.path.join(cwd, path))

def normalize_command_separators(value):
    out = []
    single = False
    double = False
    escaped = False
    at_word_start = True
    idx = 0
    while idx < len(value):
        ch = value[idx]
        if escaped:
            if ch == "\n":
                out.append(" ")
                at_word_start = True
            else:
                out.append("\\")
                out.append(ch)
                at_word_start = ch.isspace()
            escaped = False
            idx += 1
            continue
        if ch == "\\" and not single:
            escaped = True
            idx += 1
            continue
        if ch == "'" and not double:
            single = not single
            out.append(ch)
            at_word_start = False
            idx += 1
            continue
        if ch == '"' and not single:
            double = not double
            out.append(ch)
            at_word_start = False
            idx += 1
            continue
        if not single and not double and ch == "#" and at_word_start:
            idx += 1
            while idx < len(value) and value[idx] != "\n":
                idx += 1
            if idx < len(value) and value[idx] == "\n":
                out.append(" ; ")
                at_word_start = True
                idx += 1
            continue
        if not single and not double and ch == "\n":
            out.append(" ; ")
            at_word_start = True
            idx += 1
            continue
        out.append(ch)
        at_word_start = (not single and not double and (ch.isspace() or ch in ";&|()"))
        idx += 1
    if escaped:
        out.append("\\")
    return "".join(out)

def shell_tokens(value):
    lexer = shlex.shlex(value, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    return list(lexer)

def strip_redirections(segment):
    cleaned = []
    idx = 0
    while idx < len(segment):
        tok = segment[idx]
        if tok.isdigit() and idx + 1 < len(segment) and segment[idx + 1] in redir_ops:
            idx += 2
            if idx < len(segment):
                idx += 1
            continue
        if tok in redir_ops or re.match(r"^[0-9]*(<<|>>|<>|<&|>&|>\||<|>).*$", tok):
            idx += 1
            if idx < len(segment):
                idx += 1
            continue
        cleaned.append(tok)
        idx += 1
    return cleaned

def command_segments(tokens):
    start = 0
    for idx, tok in enumerate(tokens + [";"]):
        if tok in separators:
            if start < idx:
                yield strip_redirections(tokens[start:idx])
            start = idx + 1

def skip_option_words(segment, idx, value_opts=(), value_prefixes=()):
    while idx < len(segment):
        opt = segment[idx]
        if opt == "--":
            return idx + 1
        if opt in value_opts:
            idx += 2
            continue
        if any(opt.startswith(prefix) for prefix in value_prefixes):
            idx += 1
            continue
        if opt.startswith("-"):
            idx += 1
            continue
        return idx
    return idx

def command_index(segment):
    idx = 0
    while idx < len(segment):
        while idx < len(segment) and assignment_re.match(segment[idx]):
            idx += 1
        if idx >= len(segment):
            break
        cmd = os.path.basename(segment[idx])
        if cmd in {"command", "exec"}:
            idx += 1
            continue
        if cmd == "time":
            idx += 1
            while idx < len(segment):
                opt = segment[idx]
                if opt in {"-f", "--format", "-o", "--output"}:
                    idx += 2
                    continue
                if opt.startswith("-f") and opt != "-f":
                    idx += 1
                    continue
                if opt.startswith("--format=") or opt.startswith("--output="):
                    idx += 1
                    continue
                if opt.startswith("-"):
                    idx += 1
                    continue
                break
            continue
        if cmd == "timeout":
            idx = skip_option_words(
                segment, idx + 1,
                {"-s", "--signal", "-k", "--kill-after"},
                ("-s", "--signal=", "-k", "--kill-after="),
            )
            if idx < len(segment):
                idx += 1
            continue
        if cmd == "nice":
            idx = skip_option_words(
                segment, idx + 1,
                {"-n", "--adjustment"},
                ("-n", "--adjustment="),
            )
            continue
        if cmd == "nohup":
            idx += 1
            continue
        if cmd == "setsid":
            idx = skip_option_words(segment, idx + 1)
            continue
        if cmd == "stdbuf":
            idx = skip_option_words(
                segment, idx + 1,
                {"-i", "-o", "-e", "--input", "--output", "--error"},
                ("-i", "-o", "-e", "--input=", "--output=", "--error="),
            )
            continue
        if cmd == "ionice":
            idx = skip_option_words(
                segment, idx + 1,
                {"-c", "--class", "-n", "--classdata", "-p", "--pid", "-P", "--pgid", "-u", "--uid"},
                ("-c", "--class=", "-n", "--classdata=", "-p", "--pid=", "-P", "--pgid=", "-u", "--uid="),
            )
            continue
        if cmd == "chrt":
            idx = skip_option_words(
                segment, idx + 1,
                {"-T", "--sched-runtime", "-P", "--sched-period", "-D", "--sched-deadline", "-p", "--pid"},
                ("--sched-runtime=", "--sched-period=", "--sched-deadline=", "--pid="),
            )
            if idx < len(segment) - 1 and re.match(r"^[+-]?[0-9]+$", segment[idx]):
                idx += 1
            continue
        if cmd == "xargs":
            idx = skip_option_words(
                segment, idx + 1,
                {"-a", "--arg-file", "-d", "--delimiter", "-E", "--eof", "-I", "--replace", "-i", "-L", "--max-lines", "-l", "-n", "--max-args", "-P", "--max-procs", "-s", "--max-chars", "--process-slot-var"},
                ("-a", "--arg-file=", "-d", "--delimiter=", "-E", "--eof=", "-I", "--replace=", "-i", "-L", "--max-lines=", "-l", "-n", "--max-args=", "-P", "--max-procs=", "-s", "--max-chars=", "--process-slot-var="),
            )
            continue
        if cmd == "flock":
            if any(
                arg in {"-c", "--command"} or arg.startswith("--command=") or (arg.startswith("-c") and arg != "-c")
                for arg in segment[idx + 1:]
            ):
                break
            idx = skip_option_words(
                segment, idx + 1,
                {"-E", "--conflict-exit-code", "-c", "--command"},
                ("-E", "--conflict-exit-code=", "-c", "--command="),
            )
            if idx < len(segment):
                idx += 1
            continue
        if cmd == "sudo":
            idx += 1
            while idx < len(segment) and segment[idx].startswith("-"):
                opt = segment[idx]
                idx += 1
                if opt in {"-u", "-g", "-h", "-p", "-C", "-T", "-r", "-t"}:
                    idx += 1
            continue
        if cmd == "env":
            idx += 1
            while idx < len(segment):
                if assignment_re.match(segment[idx]):
                    idx += 1
                    continue
                if segment[idx].startswith("-"):
                    opt = segment[idx]
                    idx += 1
                    if opt in {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}:
                        idx += 1
                    continue
                break
            continue
        break
    return idx

def git_argv_from_segment(segment):
    idx = command_index(segment)
    if idx < len(segment) and os.path.basename(segment[idx]) == "git":
        return segment[idx + 1:]
    return None

def git_args_subcommand(git_args):
    pos = 0
    while pos < len(git_args):
        tok = git_args[pos]
        if tok == "-C":
            pos += 2
            continue
        if tok.startswith("-C") and tok != "-C":
            pos += 1
            continue
        if tok == "--work-tree":
            pos += 2
            continue
        if tok.startswith("--work-tree="):
            pos += 1
            continue
        if tok in {"-c", "--config"}:
            pos += 2
            continue
        if tok.startswith("--config="):
            pos += 1
            continue
        if tok in global_value_opts:
            pos += 2
            continue
        if any(tok.startswith(prefix) for prefix in global_value_prefixes):
            pos += 1
            continue
        if tok.startswith("-"):
            pos += 1
            continue
        return tok
    return ""

def git_subcommand_and_args(git_args):
    pos = 0
    while pos < len(git_args):
        tok = git_args[pos]
        if tok == "-C":
            pos += 2
            continue
        if tok.startswith("-C") and tok != "-C":
            pos += 1
            continue
        if tok == "--work-tree":
            pos += 2
            continue
        if tok.startswith("--work-tree="):
            pos += 1
            continue
        if tok in {"-c", "--config"}:
            pos += 2
            continue
        if tok.startswith("--config="):
            pos += 1
            continue
        if tok in global_value_opts:
            pos += 2
            continue
        if any(tok.startswith(prefix) for prefix in global_value_prefixes):
            pos += 1
            continue
        if tok.startswith("-"):
            pos += 1
            continue
        return tok, git_args[pos + 1:]
    return "", []

def flock_shell_command(args):
    pos = 0
    while pos < len(args):
        arg = args[pos]
        if arg in {"-c", "--command"} and pos + 1 < len(args):
            return args[pos + 1]
        if arg.startswith("--command="):
            return arg.split("=", 1)[1]
        if arg.startswith("-c") and arg != "-c":
            return arg[2:]
        if arg in {"-E", "--conflict-exit-code"}:
            pos += 2
            continue
        if arg.startswith("--conflict-exit-code=") or (arg.startswith("-E") and arg != "-E"):
            pos += 1
            continue
        pos += 1
    return ""

def unsafe_cwd_change_before_push(segments):
    cwd_changed = False
    for segment in segments:
        idx = command_index(segment)
        cmd = os.path.basename(segment[idx]) if idx < len(segment) else ""
        if cmd in {"cd", "pushd", "popd"}:
            cwd_changed = True
            continue
        git_args = git_argv_from_segment(segment)
        if git_args and git_args_subcommand(git_args) == "push":
            env_chdir = "env" in segment and any(
                tok in {"-C", "--chdir"} or tok.startswith("--chdir=")
                for tok in segment
            )
            if cwd_changed or env_chdir:
                return True
    return False

def nested_git_push(segment):
    idx = command_index(segment)
    if idx >= len(segment):
        return False
    exe = os.path.basename(segment[idx])
    args = segment[idx + 1:]
    nested = ""
    if exe in {"bash", "sh", "zsh", "dash"}:
        skip = False
        for pos, arg in enumerate(args):
            if skip:
                skip = False
                continue
            if arg == "-c" and pos + 1 < len(args):
                nested = args[pos + 1]
                break
            if arg.startswith("-") and "c" in arg[1:] and pos + 1 < len(args):
                nested = args[pos + 1]
                break
            if arg in {"-o", "--option"}:
                skip = True
    elif exe == "flock":
        nested = flock_shell_command(args)
    elif exe == "eval":
        nested = " ".join(args)
    return bool(re.search(r"(^|[^A-Za-z0-9_])git([^;&|]*[ \t])push([^A-Za-z0-9_]|$)", nested))

def nested_expansion_push(segment):
    idx = command_index(segment)
    if idx >= len(segment):
        return False
    exe = os.path.basename(segment[idx])
    args = segment[idx + 1:]
    nested = ""
    if exe in {"bash", "sh", "zsh", "dash"}:
        for pos, arg in enumerate(args):
            if arg == "-c" and pos + 1 < len(args):
                nested = args[pos + 1]
                break
            if arg.startswith("-") and "c" in arg[1:] and pos + 1 < len(args):
                nested = args[pos + 1]
                break
    elif exe == "flock":
        nested = flock_shell_command(args)
    elif exe == "eval":
        nested = " ".join(args)
    return bool(re.search(r"[$`]", nested) and re.search(r"g.*i.*t", nested) and re.search(r"push", nested))

def command_expansion_push(segment):
    idx = command_index(segment)
    if idx >= len(segment):
        return False
    token = segment[idx]
    next_token = segment[idx + 1] if idx + 1 < len(segment) else ""
    return bool(
        re.search(r"[$`]", token)
        and re.search(r"g.*i.*t", token)
        and (re.search(r"push", token) or next_token == "push")
    )

def substitution_contents(value):
    for match in re.finditer(r"`([^`]*)`", value):
        yield match.group(1)
    idx = 0
    while True:
        start = value.find("$(", idx)
        if start < 0:
            return
        depth = 1
        pos = start + 2
        single = False
        double = False
        escaped = False
        while pos < len(value):
            ch = value[pos]
            if escaped:
                escaped = False
            elif ch == "\\" and not single:
                escaped = True
            elif ch == "'" and not double:
                single = not single
            elif ch == '"' and not single:
                double = not double
            elif not single and not double and value.startswith("$(", pos):
                depth += 1
                pos += 1
            elif not single and not double and ch == ")":
                depth -= 1
                if depth == 0:
                    yield value[start + 2:pos]
                    idx = pos + 1
                    break
            pos += 1
        else:
            return

def expansion_contains_git_subcommand(value, subcommand):
    for content in substitution_contents(value):
        try:
            inner_tokens = shell_tokens(normalize_command_separators(content))
        except ValueError:
            return True
        for segment in command_segments(inner_tokens):
            git_args = git_argv_from_segment(segment)
            if git_args and git_args_subcommand(git_args) == subcommand:
                return True
    return False

def raw_command_expansion_push():
    return bool(
        expansion_contains_git_subcommand(normalized_command, "push")
        or re.search(
            r"(^|[;&|]\s*)(\S*/)?(command|exec|sudo|env|time)\b[^;&|]*?(\$\([^)]*\)|`[^`]*`)[^;&|]*\bpush\b",
            normalized_command,
        )
    )

def raw_env_split_push():
    return bool(
        re.search(
            r"(^|[;&|]\s*)(\S*/)?env\b[^;&|]*\s(-S|--split-string)(=|\s+)[^;&|]*\bgit\s+push\b",
            normalized_command,
        )
    )

def control_wrapped_git_subcommand(segment, subcommand):
    if not segment:
        return False
    control_tokens = {
        "if", "then", "elif", "else", "for", "while", "until", "case",
        "do", "done", "esac", "fi", "function",
    }
    starts = []
    if segment[0] in control_tokens or segment[0] == "{":
        starts.append(1)
    starts.extend(pos + 1 for pos, tok in enumerate(segment) if tok == "{")
    for start in starts:
        git_args = git_argv_from_segment(segment[start:])
        if git_args and git_args_subcommand(git_args) == subcommand:
            return True
    return False

def raw_control_structure_push():
    return any(control_wrapped_git_subcommand(segment, "push") for segment in segments)

def unsafe_git_environment_push(segment):
    idx = command_index(segment)
    if idx >= len(segment) or os.path.basename(segment[idx]) != "git":
        return False
    git_args = segment[idx + 1:]
    if git_args_subcommand(git_args) != "push":
        return False
    if any(unsafe_git_env_re.match(tok) for tok in segment[:idx]):
        return True
    return any(tok == "--bare" or tok == "--git-dir" or tok.startswith("--git-dir=") for tok in git_args)

def config_remote_mutation(args):
    if not any(re.search(r"^(remote\.|url\.|credential\.)", arg) for arg in args):
        return False
    read_only = {
        "--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list",
        "-l", "--name-only", "--show-origin", "--show-scope", "--null", "-z",
    }
    return not any(arg in read_only for arg in args)

def remote_mutation(args):
    for arg in args:
        if arg.startswith("-"):
            continue
        return arg in {"add", "remove", "rm", "rename", "set-url"}
    return False

def unsafe_remote_mutation_before_push(segments):
    mutated = False
    for segment in segments:
        git_args = git_argv_from_segment(segment)
        if not git_args:
            continue
        subcommand, args = git_subcommand_and_args(git_args)
        if subcommand == "push" and mutated:
            return True
        if subcommand == "config" and config_remote_mutation(args):
            mutated = True
        if subcommand == "remote" and remote_mutation(args):
            mutated = True
    return False

def parse_push_remote(args):
    skip = False
    endopt = False
    for pos, arg in enumerate(args):
        if skip:
            skip = False
            continue
        if not endopt and arg == "--":
            endopt = True
            continue
        if not endopt:
            if arg == "--repo":
                return args[pos + 1] if pos + 1 < len(args) else "origin"
            if arg.startswith("--repo="):
                return arg.split("=", 1)[1]
            if arg in push_value_opts:
                skip = True
                continue
            if any(arg.startswith(prefix) for prefix in push_value_prefixes):
                continue
            if arg.startswith("-"):
                continue
        return arg
    return "origin"

def args_have_shell_expansion(args):
    return any("$" in arg or "`" in arg for arg in args)

try:
    normalized_command = normalize_command_separators(command)
    tokens = shell_tokens(normalized_command)
except ValueError:
    print(json.dumps({"found": False, "workdir": os.path.abspath(base_dir)}))
    sys.exit(0)

matches = []
segments = list(command_segments(tokens))
unsafe_nested = any(nested_git_push(seg) for seg in segments)
unsafe_cwd = unsafe_cwd_change_before_push(segments)
unsafe_expansion = any(command_expansion_push(seg) or nested_expansion_push(seg) for seg in segments) or raw_command_expansion_push()
unsafe_git_env = any(unsafe_git_environment_push(seg) for seg in segments)
unsafe_remote_mutation = unsafe_remote_mutation_before_push(segments)
unsafe_env_split = raw_env_split_push()
unsafe_control = raw_control_structure_push()
for git_args in filter(None, (git_argv_from_segment(seg) for seg in segments)):
    cwd = os.path.abspath(base_dir)
    config_values = []
    j = 0
    while j < len(git_args):
        tok = git_args[j]
        if tok in separators:
            break
        if tok == "-C":
            if j + 1 < len(git_args):
                cwd = abspath(git_args[j + 1], cwd)
                j += 2
                continue
            break
        if tok.startswith("-C") and tok != "-C":
            cwd = abspath(tok[2:], cwd)
            j += 1
            continue
        if tok == "--work-tree":
            if j + 1 < len(git_args):
                cwd = abspath(git_args[j + 1], cwd)
                j += 2
                continue
            break
        if tok.startswith("--work-tree="):
            cwd = abspath(tok.split("=", 1)[1], cwd)
            j += 1
            continue
        if tok in {"-c", "--config"}:
            if j + 1 < len(git_args):
                config_values.append(git_args[j + 1])
            j += 2
            continue
        if tok.startswith("--config="):
            config_values.append(tok.split("=", 1)[1])
            j += 1
            continue
        if tok == "--config-env":
            if j + 1 < len(git_args):
                config_values.append("config-env:" + git_args[j + 1])
            j += 2
            continue
        if tok.startswith("--config-env="):
            config_values.append("config-env:" + tok.split("=", 1)[1])
            j += 1
            continue
        if tok in global_value_opts:
            j += 2
            continue
        if any(tok.startswith(prefix) for prefix in global_value_prefixes):
            j += 1
            continue
        if tok.startswith("-"):
            j += 1
            continue

        subcommand = tok
        args = git_args[j + 1:]
        if subcommand == "push":
            if args_have_shell_expansion(args):
                unsafe_expansion = True
            matches.append({"workdir": cwd, "remote": parse_push_remote(args), "config_values": config_values})
        break

if not matches:
    if unsafe_nested or unsafe_cwd or unsafe_expansion or unsafe_git_env or unsafe_remote_mutation or unsafe_env_split or unsafe_control:
        print(json.dumps({
            "found": True,
            "unsafe_nested": unsafe_nested,
            "unsafe_cwd": unsafe_cwd,
            "unsafe_expansion": unsafe_expansion,
            "unsafe_git_env": unsafe_git_env,
            "unsafe_remote_mutation": unsafe_remote_mutation,
            "unsafe_env_split": unsafe_env_split,
            "unsafe_control": unsafe_control,
            "workdir": os.path.abspath(base_dir),
            "remote": "origin",
            "config_values": [],
            "invocations": [],
        }))
        sys.exit(0)
    print(json.dumps({"found": False, "workdir": os.path.abspath(base_dir)}))
    sys.exit(0)

out = matches[0].copy()
out["found"] = True
out["match_count"] = len(matches)
out["invocations"] = matches
out["unsafe_nested"] = unsafe_nested
out["unsafe_cwd"] = unsafe_cwd
out["unsafe_expansion"] = unsafe_expansion
out["unsafe_git_env"] = unsafe_git_env
out["unsafe_remote_mutation"] = unsafe_remote_mutation
out["unsafe_env_split"] = unsafe_env_split
out["unsafe_control"] = unsafe_control
print(json.dumps(out))
PY
}

if ! PUSH_INFO=$(parse_git_push); then
  echo "Blocked: unable to parse git push command safely." >&2
  exit 2
fi

# Only intercept git push
if [ "$(echo "$PUSH_INFO" | jq -r '.found' 2>/dev/null)" != "true" ]; then
  exit 0
fi

if [ "$(echo "$PUSH_INFO" | jq -r '.unsafe_nested // false')" = "true" ]; then
  echo "Blocked: nested shell git push commands are not permitted by the pre-push gate." >&2
  echo "Run git push directly so the gate can inspect the exact target repository and arguments." >&2
  exit 2
fi

if [ "$(echo "$PUSH_INFO" | jq -r '.unsafe_cwd // false')" = "true" ]; then
  echo "Blocked: cwd-changing shell wrappers around git push are not permitted by the pre-push gate." >&2
  echo "Use git -C <repo> push ... so the gate can inspect the exact target repository." >&2
  exit 2
fi

if [ "$(echo "$PUSH_INFO" | jq -r '.unsafe_expansion // false')" = "true" ]; then
  echo "Blocked: shell-expanded git push commands are not permitted by the pre-push gate." >&2
  echo "Run git push directly without constructing the command through shell expansion." >&2
  exit 2
fi

if [ "$(echo "$PUSH_INFO" | jq -r '.unsafe_git_env // false')" = "true" ]; then
  echo "Blocked: Git repository/config environment overrides are not permitted by the pre-push gate." >&2
  echo "Use git -C <repo> push ... without GIT_DIR/GIT_WORK_TREE/GIT_CONFIG overrides so the gate can inspect the exact target." >&2
  exit 2
fi

if [ "$(echo "$PUSH_INFO" | jq -r '.unsafe_remote_mutation // false')" = "true" ]; then
  echo "Blocked: remote URL/config mutations immediately before git push are not permitted by the pre-push gate." >&2
  echo "Run the remote/config change separately, then run git push so the gate can inspect the effective destination." >&2
  exit 2
fi

if [ "$(echo "$PUSH_INFO" | jq -r '.unsafe_env_split // false')" = "true" ]; then
  echo "Blocked: env -S git push commands are not permitted by the pre-push gate." >&2
  echo "Run git push directly so the gate can inspect the exact command." >&2
  exit 2
fi

if [ "$(echo "$PUSH_INFO" | jq -r '.unsafe_control // false')" = "true" ]; then
  echo "Blocked: shell control structures around git push are not permitted by the pre-push gate." >&2
  echo "Run git push directly so the gate can inspect the exact command." >&2
  exit 2
fi

PROJECT_DIR=$(echo "$PUSH_INFO" | jq -r '.workdir')
if command -v git &>/dev/null; then
  REPO_ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)
else
  REPO_ROOT="$PROJECT_DIR"
fi
[ -z "$REPO_ROOT" ] && exit 0

# === LAYER 1: credential residue in ANY remote URL (HARD BLOCK, compound-safe) ===
# A greedy parse of a compound command ('git push A && git push B') would inspect
# only the last push's remote, letting a credentialed 'A' slip by (R1). And a
# leading flag (git push -u/-f/--force-with-lease ...) used to leave the parsed
# remote empty and fail OPEN (H1). Both are closed by scanning EVERY configured
# remote URL here: if the repo can push at all, no remote may carry an inline
# credential — independent of how the command names its target.
CRED_RE='github_pat_[A-Za-z0-9_]+@|ghp_[A-Za-z0-9]+@|glpat-[A-Za-z0-9_]+@|ghs_[A-Za-z0-9]+@|oauth2:[^@]+@|https?://[^/@[:space:]]+@'
CONFIG_REMOTE_OVERRIDE_RE='^(config-env:)?(remote\..*\.(url|pushurl)|url\..*\.(insteadof|pushinsteadof)|credential\..*|include\..*|includeIf\..*)='
CONFIG_REMOTE_STORED_RE='^(remote\..*\.(url|pushurl)|url\..*\.(insteadof|pushinsteadof)|credential\..*)[[:space:]]'
LEAK=""
while IFS= read -r _push; do
  _workdir=$(echo "$_push" | jq -r '.workdir')
  _remote=$(echo "$_push" | jq -r '.remote')
  _url_leak=$(printf '%s\n' "$_remote" | grep -E "$CRED_RE" || true)
  _config_leak=$(echo "$_push" | jq -r '.config_values[]?' | grep -E "$CRED_RE" || true)
  _config_remote_override=$(echo "$_push" | jq -r '.config_values[]?' | grep -Ei "$CONFIG_REMOTE_OVERRIDE_RE" || true)
  _repo_root=$(git -C "$_workdir" rev-parse --show-toplevel 2>/dev/null || true)
  _leak=""
  if [ -n "$_repo_root" ]; then
    _leak=$(git -C "$_repo_root" config --get-regexp '.*' 2>/dev/null | grep -Ei "$CONFIG_REMOTE_STORED_RE" | grep -E "$CRED_RE")
  fi
  if [ -n "$_url_leak" ]; then
    _leak="$_leak
command.remote.url $_url_leak"
  fi
  if [ -n "$_config_leak" ]; then
    _leak="$_leak
command.git-config $_config_leak"
  fi
  if [ -n "$_config_remote_override" ]; then
    _leak="$_leak
command.git-config-remote-override $_config_remote_override"
  fi
  if [ -n "$_leak" ]; then
    LEAK="$LEAK
${_repo_root:-$_workdir}:
$_leak"
  fi
done < <(echo "$PUSH_INFO" | jq -c '.invocations[]')
if [ -n "$LEAK" ]; then
  echo "Push blocked: credential detected or unsafe remote config override detected." >&2
  echo "$LEAK" | sed -E 's#(https?://)[^/@[:space:]]+@#\1***@#g' | sed -E 's/(oauth2:|github_pat_|ghp_|glpat-|ghs_)[^@]*@/***@/g' | sed 's/^/  /' >&2
  echo "Fix: git remote set-url <remote> <url-without-credentials>" >&2
  echo "Do not pass remote/url/credential overrides via git -c or --config-env on push commands." >&2
  exit 2
fi

# Parse each target remote for the drift/declaration layers below. Layer 1 above
# already handled the credential check for every remote in every command target repo.
while IFS= read -r _push; do
  _workdir=$(echo "$_push" | jq -r '.workdir')
  REPO_ROOT=$(git -C "$_workdir" rev-parse --show-toplevel 2>/dev/null || true)
  [ -z "$REPO_ROOT" ] && continue
  PUSH_REMOTE=$(echo "$_push" | jq -r '.remote')
  DIRECT_URL=0
  if printf '%s\n' "$PUSH_REMOTE" | grep -Eq '^[A-Za-z][A-Za-z0-9+.-]*://|^[^/:@]+@[^/:]+:.+|^[^/:]+\.[^/:]+:.+|^[^/:]+:.*/.+'; then
    DIRECT_URL=1
    if git -C "$REPO_ROOT" config --get-regexp '.*' 2>/dev/null | grep -Eiq '^url\..*\.(insteadof|pushinsteadof)[[:space:]]'; then
      echo "Push blocked: direct URL pushes with url.* rewrite config are not permitted by the pre-push gate." >&2
      echo "Use a named remote so Git and the gate agree on the effective push destination." >&2
      exit 2
    fi
    ACTUAL_URL="$PUSH_REMOTE"
  else
    ACTUAL_URL=$(git -C "$REPO_ROOT" remote get-url --push --all "$PUSH_REMOTE" 2>/dev/null)
    [ -z "$ACTUAL_URL" ] && ACTUAL_URL=$(git -C "$REPO_ROOT" config "remote.${PUSH_REMOTE}.url" 2>/dev/null)
  fi
  [ -z "$ACTUAL_URL" ] && continue

  # === LAYER 2: Remote URL drift detection (WARN) ===
  BASELINE_DIR="$REPO_ROOT/.claude"
  PUSH_REMOTE_SAFE=$(printf '%s' "$PUSH_REMOTE" | sed -E 's/[^A-Za-z0-9._-]+/_/g')
  [ -n "$PUSH_REMOTE_SAFE" ] || PUSH_REMOTE_SAFE="direct-url"
  BASELINE_FILE="$BASELINE_DIR/.last-push-url.${PUSH_REMOTE_SAFE}"

  if [ -f "$BASELINE_FILE" ]; then
    BASELINE_URL=$(cat "$BASELINE_FILE" 2>/dev/null)
    if [ -n "$BASELINE_URL" ] && [ "$ACTUAL_URL" != "$BASELINE_URL" ]; then
      echo "Warning: remote '$PUSH_REMOTE' URL changed since last push." >&2
      echo "  Previous: $BASELINE_URL" >&2
      echo "  Current:  $ACTUAL_URL" >&2
      echo "If intentional, baseline will update after this push." >&2
    fi
  fi

  # Record baseline (create on first push, update on subsequent)
  if [ -d "$BASELINE_DIR" ]; then
    if ! echo "$ACTUAL_URL" > "$BASELINE_FILE"; then
      echo "WARN: baseline write failed: $BASELINE_FILE" >&2
    fi
  fi

  # === LAYER 3: Declaration validation (OPT-IN) ===
  DECL_FILE="$REPO_ROOT/.claude/.push-remote"
  if [ -f "$DECL_FILE" ]; then
    if [ "$DIRECT_URL" -eq 1 ]; then
      EXPECTED=$(cut -d= -f2- "$DECL_FILE" 2>/dev/null)
    else
      EXPECTED=$(grep "^${PUSH_REMOTE}=" "$DECL_FILE" 2>/dev/null | cut -d= -f2-)
    fi
    if [ -n "$EXPECTED" ]; then
      CLEAN_URL=$(printf '%s\n' "$ACTUAL_URL" | sed -E 's#(https?://)[^/@[:space:]]+@#\1#g')
      MATCHED=0
      while IFS= read -r _expected; do
        [ -z "$_expected" ] && continue
        if printf '%s\n' "$CLEAN_URL" | grep -qF "$_expected"; then
          MATCHED=1
          break
        fi
      done <<< "$EXPECTED"
      if [ "$MATCHED" -ne 1 ]; then
        echo "Push blocked: remote URL doesn't match declaration." >&2
        echo "  Expected: $EXPECTED" >&2
        echo "  Actual:   $CLEAN_URL" >&2
        echo "  Source:   $DECL_FILE" >&2
        echo "Fix: git remote set-url $PUSH_REMOTE <correct-url>" >&2
        exit 2
      fi
    fi
  fi
done < <(echo "$PUSH_INFO" | jq -c '.invocations[]')

exit 0

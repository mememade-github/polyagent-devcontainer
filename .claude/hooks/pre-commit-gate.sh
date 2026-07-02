#!/bin/bash
# PreToolUse hook (matcher: Bash): Enforce pre-commit verification gate
# Intercepts `git commit` commands and blocks unless verification was run recently.
# Uses exit code 2 + stderr for reliable blocking per official docs:
#   "Exit 2 means a blocking error. stderr text is fed back to Claude."
# Reference: https://code.claude.com/docs/en/hooks#exit-code-output
#
# Marker file: created by completion-checker.sh at ACTUAL_ROOT/.claude/.last-verification.$BRANCH_SAFE

INPUT=$(cat)
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq is required to parse hook input safely." >&2
  exit 2
fi
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

if [ -z "$COMMAND" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  if echo "$COMMAND" | grep -qE '(^|[^A-Za-z0-9_])git([^;&|]*[[:space:]])commit([^A-Za-z0-9_]|$)'; then
    echo "Blocked: python3 is required to parse git commit commands safely." >&2
    exit 2
  fi
  exit 0
fi

parse_git_commit() {
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
commit_value_opts = {
    "-m", "--message", "-c", "-C", "--reuse-message", "--reedit-message",
    "-F", "--file", "--author", "--date", "-t", "--template", "--fixup",
    "--squash", "--trailer", "--cleanup",
}
commit_value_prefixes = (
    "--message=", "--reuse-message=", "--reedit-message=", "--file=",
    "--author=", "--date=", "--template=", "--fixup=", "--squash=",
    "--trailer=", "--cleanup=",
)

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

def raw_command_segments(tokens):
    start = 0
    for idx, tok in enumerate(tokens + [";"]):
        if tok in separators:
            if start < idx:
                yield tokens[start:idx]
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

def unsafe_cwd_change_before_commit(segments):
    cwd_changed = False
    for segment in segments:
        idx = command_index(segment)
        cmd = os.path.basename(segment[idx]) if idx < len(segment) else ""
        if cmd in {"cd", "pushd", "popd"}:
            cwd_changed = True
            continue
        git_args = git_argv_from_segment(segment)
        if git_args and git_args_subcommand(git_args) == "commit":
            env_chdir = "env" in segment and any(
                tok in {"-C", "--chdir"} or tok.startswith("--chdir=")
                for tok in segment
            )
            if cwd_changed or env_chdir:
                return True
    return False

def nested_git_commit(segment):
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
    return bool(re.search(r"(^|[^A-Za-z0-9_])git([^;&|]*[ \t])commit([^A-Za-z0-9_]|$)", nested))

def nested_expansion_commit(segment):
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
    return bool(re.search(r"[$`]", nested) and re.search(r"g.*i.*t", nested) and re.search(r"commit", nested))

def command_expansion_commit(segment):
    idx = command_index(segment)
    if idx >= len(segment):
        return False
    token = segment[idx]
    next_token = segment[idx + 1] if idx + 1 < len(segment) else ""
    return bool(
        re.search(r"[$`]", token)
        and re.search(r"g.*i.*t", token)
        and (re.search(r"commit", token) or next_token == "commit")
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

def raw_command_expansion_commit():
    return bool(
        expansion_contains_git_subcommand(normalized_command, "commit")
        or re.search(
            r"(^|[;&|]\s*)(\S*/)?(command|exec|sudo|env|time)\b[^;&|]*?(\$\([^)]*\)|`[^`]*`)[^;&|]*\bcommit\b",
            normalized_command,
        )
    )

def raw_env_split_commit():
    return bool(
        re.search(
            r"(^|[;&|]\s*)(\S*/)?env\b[^;&|]*\s(-S|--split-string)(=|\s+)[^;&|]*\bgit\s+commit\b",
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

def raw_control_structure_commit():
    return any(control_wrapped_git_subcommand(segment, "commit") for segment in raw_segments)

def unsafe_git_environment_commit(segment):
    idx = command_index(segment)
    if idx >= len(segment) or os.path.basename(segment[idx]) != "git":
        return False
    git_args = segment[idx + 1:]
    if git_args_subcommand(git_args) != "commit":
        return False
    if any(unsafe_git_env_re.match(tok) for tok in segment[:idx]):
        return True
    return any(tok == "--bare" or tok == "--git-dir" or tok.startswith("--git-dir=") for tok in git_args)

def process_substitution_commit(segment):
    git_args = git_argv_from_segment(strip_redirections(segment))
    if not git_args or git_args_subcommand(git_args) != "commit":
        return False
    return any(
        tok in {"<(", ">("}
        or (tok in {"<", ">"} and pos + 1 < len(segment) and segment[pos + 1] == "(")
        for pos, tok in enumerate(segment)
    )

def has_shell_expansion(value):
    return "$" in value or "`" in value

def parse_commit_args(args):
    info = {"no_verify": False, "all": False, "scan_all": False, "paths": [], "unsafe_arg_expansion": False}
    skip = False
    endopt = False
    for arg in args:
        if endopt:
            if has_shell_expansion(arg):
                info["unsafe_arg_expansion"] = True
            info["paths"].append(arg)
            continue
        if skip:
            skip = False
            continue
        if arg == "--":
            endopt = True
            continue
        if arg == "--no-verify":
            info["no_verify"] = True
            continue
        if arg == "--all":
            info["all"] = True
            continue
        if arg == "--pathspec-from-file":
            info["scan_all"] = True
            skip = True
            continue
        if arg.startswith("--pathspec-from-file=") or arg == "--pathspec-file-nul":
            info["scan_all"] = True
            continue
        if has_shell_expansion(arg):
            info["unsafe_arg_expansion"] = True
            continue
        if arg in commit_value_opts:
            skip = True
            continue
        if any(arg.startswith(prefix) for prefix in commit_value_prefixes):
            continue
        if arg.startswith("--"):
            continue
        if arg.startswith("-") and arg != "-":
            cluster = arg[1:]
            if cluster.startswith("u"):
                continue
            if "n" in cluster:
                info["no_verify"] = True
            if "a" in cluster:
                info["all"] = True
            if cluster and cluster[-1] in {"m", "c", "C", "F", "t"}:
                skip = True
            continue
        info["paths"].append(arg)
    return info

try:
    normalized_command = normalize_command_separators(command)
    tokens = shell_tokens(normalized_command)
except ValueError:
    print(json.dumps({"found": False, "workdir": os.path.abspath(base_dir)}))
    sys.exit(0)

matches = []
segments = list(command_segments(tokens))
raw_segments = list(raw_command_segments(tokens))
unsafe_nested = any(nested_git_commit(seg) for seg in segments)
unsafe_cwd = unsafe_cwd_change_before_commit(segments)
unsafe_expansion = any(command_expansion_commit(seg) or nested_expansion_commit(seg) for seg in segments) or raw_command_expansion_commit()
unsafe_process_substitution = any(process_substitution_commit(seg) for seg in raw_segments)
unsafe_git_env = any(unsafe_git_environment_commit(seg) for seg in segments)
unsafe_env_split = raw_env_split_commit()
unsafe_control = raw_control_structure_commit()
for git_args in filter(None, (git_argv_from_segment(seg) for seg in segments)):
    cwd = os.path.abspath(base_dir)
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
        if subcommand == "commit":
            item = {"workdir": cwd, "args": args}
            item.update(parse_commit_args(args))
            matches.append(item)
        break

if any(m.get("unsafe_arg_expansion") for m in matches):
    unsafe_expansion = True

if not matches:
    if unsafe_nested or unsafe_cwd or unsafe_expansion or unsafe_process_substitution or unsafe_git_env or unsafe_env_split or unsafe_control:
        print(json.dumps({
            "found": True,
            "unsafe_nested": unsafe_nested,
            "unsafe_cwd": unsafe_cwd,
            "unsafe_expansion": unsafe_expansion,
            "unsafe_process_substitution": unsafe_process_substitution,
            "unsafe_git_env": unsafe_git_env,
            "unsafe_env_split": unsafe_env_split,
            "unsafe_control": unsafe_control,
            "workdir": os.path.abspath(base_dir),
            "no_verify": False,
            "all": False,
            "scan_all": False,
            "paths": [],
            "invocations": [],
        }))
        sys.exit(0)
    print(json.dumps({"found": False, "workdir": os.path.abspath(base_dir)}))
    sys.exit(0)

first = matches[0].copy()
first["found"] = True
first["match_count"] = len(matches)
first["invocations"] = matches
first["unsafe_nested"] = unsafe_nested
first["unsafe_cwd"] = unsafe_cwd
first["unsafe_expansion"] = unsafe_expansion
first["unsafe_process_substitution"] = unsafe_process_substitution
first["unsafe_git_env"] = unsafe_git_env
first["unsafe_env_split"] = unsafe_env_split
first["unsafe_control"] = unsafe_control
if len(matches) > 1:
    first["scan_all"] = True
    first["no_verify"] = first["no_verify"] or any(m["no_verify"] for m in matches)
print(json.dumps(first))
PY
}

if ! COMMIT_INFO=$(parse_git_commit); then
  echo "Blocked: unable to parse git commit command safely." >&2
  exit 2
fi

# Only intercept git commit commands (not git add, git status, etc.)
if [ "$(echo "$COMMIT_INFO" | jq -r '.found' 2>/dev/null)" != "true" ]; then
  exit 0
fi

if [ "$(echo "$COMMIT_INFO" | jq -r '.unsafe_nested // false')" = "true" ]; then
  echo "Blocked: nested shell git commit commands are not permitted by the pre-commit gate." >&2
  echo "Run git commit directly so the gate can inspect the exact target repository and arguments." >&2
  exit 2
fi

if [ "$(echo "$COMMIT_INFO" | jq -r '.unsafe_cwd // false')" = "true" ]; then
  echo "Blocked: cwd-changing shell wrappers around git commit are not permitted by the pre-commit gate." >&2
  echo "Use git -C <repo> commit ... so the gate can inspect the exact target repository." >&2
  exit 2
fi

if [ "$(echo "$COMMIT_INFO" | jq -r '.unsafe_expansion // false')" = "true" ]; then
  echo "Blocked: shell-expanded git commit commands are not permitted by the pre-commit gate." >&2
  echo "Run git commit directly without constructing the command through shell expansion." >&2
  exit 2
fi

if [ "$(echo "$COMMIT_INFO" | jq -r '.unsafe_process_substitution // false')" = "true" ]; then
  echo "Blocked: process substitution in git commit commands is not permitted by the pre-commit gate." >&2
  echo "Use a regular file argument so the gate can inspect the complete git commit command safely." >&2
  exit 2
fi

if [ "$(echo "$COMMIT_INFO" | jq -r '.unsafe_git_env // false')" = "true" ]; then
  echo "Blocked: Git repository/config environment overrides are not permitted by the pre-commit gate." >&2
  echo "Use git -C <repo> commit ... without GIT_DIR/GIT_WORK_TREE/GIT_CONFIG overrides so the gate can inspect the exact target." >&2
  exit 2
fi

if [ "$(echo "$COMMIT_INFO" | jq -r '.unsafe_env_split // false')" = "true" ]; then
  echo "Blocked: env -S git commit commands are not permitted by the pre-commit gate." >&2
  echo "Run git commit directly so the gate can inspect the exact command." >&2
  exit 2
fi

if [ "$(echo "$COMMIT_INFO" | jq -r '.unsafe_control // false')" = "true" ]; then
  echo "Blocked: shell control structures around git commit are not permitted by the pre-commit gate." >&2
  echo "Run git commit directly so the gate can inspect the exact command." >&2
  exit 2
fi

# AUD-2026-029 + L6: block --no-verify and its short alias -n when they are
# arguments to `git commit`. Strip quoted strings first so a commit MESSAGE
# mentioning the flags is not a false positive. Then flatten parens/backticks
# and split the command on shell separators (; & |) into segments, and inspect
# only the segment(s) holding the git-commit invocation, so a legit -n in a
# chained/adjacent command (git commit -m x && git log -n 5; tail -n; ...) is
# not matched while a real bypass in any git-commit segment still is. Trailing
# detection is now shlex-based so `git -C <path> commit -n` is caught and the
# target repo below is the same repo that git will commit.
if [ "$(echo "$COMMIT_INFO" | jq -r '.no_verify')" = "true" ]; then
  echo "Blocked: --no-verify/-n bypass is not permitted (project pre-commit gate)." >&2
  echo "Fix verification issues before committing — do not skip the gate." >&2
  exit 2
fi

if [ "$(echo "$COMMIT_INFO" | jq -r '.match_count // 0')" -gt 1 ]; then
  echo "Blocked: multiple git commit invocations in one Bash command are not permitted by the pre-commit gate." >&2
  echo "Run each commit as a separate command so each target repository has an explicit verification boundary." >&2
  exit 2
fi

PROJECT_DIR=$(echo "$COMMIT_INFO" | jq -r '.workdir')

# Resolve actual project root (worktree -> original repo root)
if command -v git &>/dev/null; then
  GIT_COMMON=$(git -C "$PROJECT_DIR" rev-parse --git-common-dir 2>/dev/null)
  if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
    ACTUAL_ROOT=$(dirname "$GIT_COMMON")
  else
    ACTUAL_ROOT="$PROJECT_DIR"
  fi
else
  ACTUAL_ROOT="$PROJECT_DIR"
fi

# AUD-2026-030: secret-pattern scan on staged content. project coding rules "Protect secrets".
# Extends pre-push-gate.sh Layer 1 (which only scans remote URL) to scan staged file content.
SECRET_PATTERNS='github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{36}|glpat-[A-Za-z0-9_-]{20,}|ghs_[A-Za-z0-9]{36}|(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}|BEGIN[[:space:]]+(RSA[[:space:]]+|OPENSSH[[:space:]]+|EC[[:space:]]+|DSA[[:space:]]+|ENCRYPTED[[:space:]]+)?PRIVATE[[:space:]]+KEY[-]*[-][[:space:]]*$|AKIA[0-9A-Z]{16}'
# What a commit actually writes depends on its form, and none of these land in
# --cached when this PreToolUse hook runs:
#   * git commit -a/-am     -> auto-stages ALL tracked mods at commit time
#   * git commit <path> -m  -> commits the WORKING-TREE version of <path> (no -a)
# Scan --cached always; additionally scan the unstaged tracked diff each form will
# pull in, or a secret in a modified-but-unstaged tracked file slips through.
# Narrowing the extra scan to the -a set / the named pathspecs avoids false
# positives from unrelated working-tree edits on a plain 'git commit -m'.
SECRET_SCAN=""
while IFS= read -r _commit; do
  _workdir=$(echo "$_commit" | jq -r '.workdir')
  SECRET_SCAN="$SECRET_SCAN
$(git -C "$_workdir" diff --cached -U0 2>/dev/null)"
  if [ "$(echo "$_commit" | jq -r '.all or .scan_all')" = "true" ]; then
    SECRET_SCAN="$SECRET_SCAN
$(git -C "$_workdir" diff -U0 2>/dev/null)"
  else
    while IFS= read -r _path; do
      [ -z "$_path" ] && continue
      SECRET_SCAN="$SECRET_SCAN
$(git -C "$_workdir" diff -U0 -- "$_path" 2>/dev/null)"
    done < <(echo "$_commit" | jq -r '.paths[]?')
  fi
done < <(echo "$COMMIT_INFO" | jq -c '.invocations[]')
if echo "$SECRET_SCAN" | grep -qE "$SECRET_PATTERNS"; then
  echo "Blocked: secret pattern detected in staged content." >&2
  echo "Inspect: git diff --cached" >&2
  echo "If false positive (e.g. regex literal in documentation), inspect manually and decide whether to amend or document the exception." >&2
  exit 2
fi

# resolve branch name for per-worktree marker isolation
if ! BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null); then
  BRANCH="unknown"
fi
BRANCH=$(printf '%s\n' "$BRANCH" | head -1)
BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')

MARKER="$ACTUAL_ROOT/.claude/.last-verification.$BRANCH_SAFE"
MAX_AGE=600  # 10 minutes

NEEDS_VERIFICATION=0

if [ ! -f "$MARKER" ]; then
  NEEDS_VERIFICATION=1
else
  MARKER_MTIME=$(stat -c %Y "$MARKER" 2>/dev/null) || NEEDS_VERIFICATION=1
  if [ "$NEEDS_VERIFICATION" -eq 0 ]; then
    MARKER_AGE=$(( $(date +%s) - MARKER_MTIME ))
    if [ "$MARKER_AGE" -gt "$MAX_AGE" ]; then
      NEEDS_VERIFICATION=1
    fi
  fi
fi

if [ "$NEEDS_VERIFICATION" -eq 1 ]; then
  # Fail closed: never run the checker inside the hook — its runtime exceeds
  # the PreToolUse timeout budget (settings.json), so an in-hook run can be
  # killed mid-flight and the gate outcome would depend on harness timeout
  # semantics. Block immediately and print the exact command instead.
  CHECKER="$ACTUAL_ROOT/scripts/meta/completion-checker.sh"
  echo "Blocked: verification marker is stale or missing for branch '$BRANCH'." >&2
  if [ -f "$CHECKER" ]; then
    echo "Run verification, then retry the commit:" >&2
    echo "  CLAUDE_PROJECT_DIR=\"$ACTUAL_ROOT\" bash \"$CHECKER\"" >&2
    echo "(On success it records the marker: $MARKER)" >&2
  else
    echo "Run verification before committing:" >&2
    echo "1. Python: ruff check src/ && mypy src/ --ignore-missing-imports" >&2
    echo "2. TypeScript: pnpm build" >&2
    echo "3. Or run: your project verification script (see project governance docs)" >&2
    echo "Then create the marker: mkdir -p '$ACTUAL_ROOT/.claude' && touch '$MARKER'" >&2
  fi
  exit 2
fi

# --- Layer 2: /refine requirement check for multi-file changes ---
SCORER="$ACTUAL_ROOT/.refine/score.sh"
REFINE_MARKER="$ACTUAL_ROOT/.claude/.refinement-active"
if [ -f "$SCORER" ] && [ ! -f "$REFINE_MARKER" ]; then
  STAGED_COUNT=$(git -C "$PROJECT_DIR" diff --cached --name-only | wc -l)
  if [ "$STAGED_COUNT" -ge 2 ]; then
    echo "WARNING: $STAGED_COUNT files staged but /refine is not active." >&2
    echo "Project automated workflow requires /refine for changes affecting 2+ files when scorer exists." >&2
    echo "Consider running /refine instead of direct commit." >&2
    # WARNING only, not blocking — agent can proceed with justification
  fi
fi

# --- Layer 3: Coupling: reminder for multi-file commits (AUD-2026-031, non-blocking) ---
# commit-discipline §2 requires explicit "Coupling:" line when bundling orthogonal concerns.
# Tooling cannot mechanically determine orthogonality, so this is a reminder gate, not enforcement.
STAGED_COUNT_L3=$(git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null | wc -l)
if [ "$STAGED_COUNT_L3" -ge 2 ]; then
  # Extract -m message if present in the command. Limitation: only the first -m argument is inspected;
  # commit via editor (no -m) bypasses this reminder. Acceptable trade-off — reminder, not enforcement.
  COMMIT_MSG=$(echo "$COMMAND" | grep -oE -- '-m[[:space:]]+"[^"]*"' | head -1 | sed -E 's/^-m[[:space:]]+"//; s/"$//')
  if [ -n "$COMMIT_MSG" ] && ! echo "$COMMIT_MSG" | grep -qE '^[[:space:]]*Coupling:'; then
    echo "REMINDER: $STAGED_COUNT_L3 files staged but commit message lacks 'Coupling:' line." >&2
    echo "commit-discipline §2: bundled commits must state coupling reason. Add 'Coupling: <reason>' line if files are intentionally bundled." >&2
    echo "(reminder only, not blocking — single-concern multi-file commits are legitimate)" >&2
  fi
fi

# Verification is recent — allow commit
exit 0

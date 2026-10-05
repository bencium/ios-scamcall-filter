"""Claude Code hook: blocks running `fly deploy` directly, so every deploy goes through scripts/deploy.sh.

deploy.sh refuses unless the work is committed on main and the server patches still apply.
Claude Code passes the Bash command as JSON on stdin; exit code 2 blocks it and shows Claude the reason.
"""
import json
import re
import sys

# fly or flyctl starting a command (also after ;, &&, |, a bracket or VAR=value), with deploy later on.
BARE_DEPLOY = re.compile(r'(^|[;&|(\n])\s*(\w+=\S*\s+)*(\S*/)?(fly|flyctl)\b[^;&|\n]*\bdeploy\b')
# Text fed to a command (heredocs, then quoted strings) is not run, so searches and docs that
# mention fly deploy stay allowed. Heredocs go first: their text can hold stray quote marks.
HEREDOC = re.compile(r'<<-?\s*([\'"]?)(\w+)\1[^\n]*\n.*?\n\s*\2[ \t]*(?=\n|$)', re.S)
QUOTED = re.compile(r"'[^']*'|\"(?:[^\"\\]|\\.)*\"")

command = json.load(sys.stdin).get('tool_input', {}).get('command', '')
if BARE_DEPLOY.search(QUOTED.sub('""', HEREDOC.sub('', command))):
    print('Blocked: deploy with scripts/deploy.sh, not fly deploy. It checks that the work is committed '
          'on main and that the server patches still apply.', file=sys.stderr)
    sys.exit(2)

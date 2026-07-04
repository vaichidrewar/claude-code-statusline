#!/bin/bash
# ABOUTME: Pipes representative status-line JSON cases through statusline-command.sh.
# ABOUTME: Run after any change and eyeball the rendered output for regressions.

cd "$(dirname "$0")" || exit 1
script=./statusline-command.sh

now=$(date +%s)
r5=$(( now + 4*3600 + 13*60 ))   # 4h13m out -> relative countdown
r7=$(( now + 3*86400 ))          # 3 days out -> absolute weekday+time

run() { echo "--- $1"; echo "$2" | bash "$script"; echo; }

run "full house (subagent, git diff, all meters)" \
  "{\"model\":{\"display_name\":\"Fable 5 (1M context)\"},\"effort\":{\"level\":\"xhigh\"},\"agent\":{\"name\":\"explore\"},\"workspace\":{\"project_dir\":\"/x/acme-web\"},\"cwd\":\"$PWD\",\"thinking\":{\"enabled\":true},\"rate_limits\":{\"five_hour\":{\"used_percentage\":3,\"resets_at\":$r5},\"seven_day\":{\"used_percentage\":9,\"resets_at\":$r7}},\"context_window\":{\"used_percentage\":2}}"

run "typical (no git, no agent)" \
  "{\"model\":{\"display_name\":\"Opus 4.8 (1M context)\"},\"effort\":{\"level\":\"high\"},\"workspace\":{\"project_dir\":\"/x/claude-code-statusline\"},\"cwd\":\"/tmp/nonrepo\",\"thinking\":{\"enabled\":true},\"rate_limits\":{\"five_hour\":{\"used_percentage\":5,\"resets_at\":$r5},\"seven_day\":{\"used_percentage\":10,\"resets_at\":$r7}},\"context_window\":{\"used_percentage\":47}}"

run "no meters at all (only line 2 prints)" \
  "{\"model\":{\"display_name\":\"Haiku 4.5\"},\"workspace\":{\"project_dir\":\"/a/b\"},\"cwd\":\"/tmp/nonrepo\"}"

echo "--- bar sweep (percentage -> line 1)"
for p in 0 1 3 5 9 10 30 47 55 100; do
    printf '%3s%% -> ' "$p"
    echo "{\"model\":{\"display_name\":\"M\"},\"context_window\":{\"used_percentage\":$p}}" | bash "$script" | sed -n '1p'
done

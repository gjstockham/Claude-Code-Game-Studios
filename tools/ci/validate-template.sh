#!/usr/bin/env bash
# validate-template.sh — structural validation for the CCGS template itself.
#
# This validates the TEMPLATE (agents, skills, testing framework, docs), not a
# game built from it. It is deterministic and needs no API key: every check is
# grep/awk over files on disk, so it runs in CI in seconds.
#
# Each check here corresponds to a real defect found in this repository. They
# exist to stop those defects recurring, not as generic hygiene.
#
# Usage: bash tools/ci/validate-template.sh
# Exit:  0 = all checks pass, 1 = one or more failures.

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

FAILED=0
CHECKS=0

pass() { CHECKS=$((CHECKS + 1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() {
  CHECKS=$((CHECKS + 1)); FAILED=$((FAILED + 1))
  printf '  \033[31mFAIL\033[0m  %s\n' "$1"
  [ -n "${2:-}" ] && printf '        %s\n' "$2"
}
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

AGENTS=$(find .claude/agents -name '*.md' | sort)
SKILLS=$(find .claude/skills -name 'SKILL.md' | sort)
FRAMEWORK="CCGS Skill Testing Framework"

# Extract a frontmatter field's value from a markdown file.
fm() { awk '/^---$/{n++; next} n==1' "$2" | grep -m1 "^$1:" | sed "s/^$1: *//"; }

# ---------------------------------------------------------------------------
section "Agent frontmatter"
# ---------------------------------------------------------------------------

missing=""
while IFS= read -r f; do
  for field in name description tools model; do
    awk '/^---$/{n++; next} n==1' "$f" | grep -q "^$field:" || missing="$missing $(basename "$f"):$field"
  done
done <<< "$AGENTS"
[ -z "$missing" ] && pass "all agents have name, description, tools, model" \
                  || fail "agents missing required frontmatter" "$missing"

# Agents use `tools:`; `allowed-tools:` is the SKILL field. Mixing them up made
# all 49 testing-framework agent specs assert a field that does not exist.
bad=$(grep -l '^allowed-tools:' $AGENTS 2>/dev/null || true)
[ -z "$bad" ] && pass "no agent uses 'allowed-tools:' (that is the skill field)" \
              || fail "agents using 'allowed-tools:' instead of 'tools:'" "$bad"

# ---------------------------------------------------------------------------
section "Skill frontmatter"
# ---------------------------------------------------------------------------

missing=""
while IFS= read -r f; do
  for field in name description argument-hint user-invocable allowed-tools model; do
    awk '/^---$/{n++; next} n==1' "$f" | grep -q "^$field:" || missing="$missing $(basename "$(dirname "$f")"):$field"
  done
done <<< "$SKILLS"
[ -z "$missing" ] && pass "all skills have the 6 required frontmatter fields" \
                  || fail "skills missing required frontmatter" "$missing"

# Skills use `allowed-tools:`; `tools:` is the AGENT field.
bad=$(grep -l '^tools:' $SKILLS 2>/dev/null || true)
[ -z "$bad" ] && pass "no skill uses 'tools:' (that is the agent field)" \
              || fail "skills using 'tools:' instead of 'allowed-tools:'" "$bad"

# ---------------------------------------------------------------------------
section "Model tiers"
# ---------------------------------------------------------------------------

# coordination-rules.md requires the alias, never a literal ID — aliases track
# the current model generation, pinned IDs go stale. This is the check that
# keeps that rule true.
VALID_ALIASES='^(sonnet|opus|haiku|fable|inherit)$'
bad=""
while IFS= read -r f; do
  m=$(fm model "$f")
  [[ "$m" =~ $VALID_ALIASES ]] || bad="$bad $(basename "$f")=$m"
done <<< "$AGENTS"
while IFS= read -r f; do
  m=$(fm model "$f")
  [[ "$m" =~ $VALID_ALIASES ]] || bad="$bad $(basename "$(dirname "$f")")=$m"
done <<< "$SKILLS"
[ -z "$bad" ] && pass "every agent and skill uses a model alias, not a literal ID" \
              || fail "non-alias model values found" "$bad"

# No literal model IDs anywhere in the template, except the one documented
# counter-example inside the "never pin an ID" rule itself.
hits=$(grep -rn --exclude-dir=.git -E 'claude-(opus|sonnet|haiku|fable)-[0-9]' \
         .claude "$FRAMEWORK" 2>/dev/null \
       | grep -v 'coordination-rules.md.*goes stale at the next release' \
       | grep -v 'such as `claude-sonnet-5`' || true)
[ -z "$hits" ] && pass "no stale literal model IDs in .claude/ or the framework" \
               || fail "literal model IDs found (use the alias)" "$hits"

# ---------------------------------------------------------------------------
section "Testing framework parity"
# ---------------------------------------------------------------------------

for d in agents skills; do
  if [ "$d" = "agents" ]; then
    real=$(for f in $AGENTS; do basename "$f" .md; done | sort)
  else
    real=$(for f in $SKILLS; do basename "$(dirname "$f")"; done | sort)
  fi
  spec=$(find "$FRAMEWORK/$d" -name '*.md' -exec basename {} .md \; 2>/dev/null | sort)
  diff_out=$(diff <(echo "$real") <(echo "$spec") 2>/dev/null || true)
  [ -z "$diff_out" ] && pass "every ${d%s} has a testing-framework spec ($(echo "$real" | wc -l | tr -d ' '))" \
                     || fail "$d / spec mismatch" "$diff_out"
done

# Framework specs assert each agent's tier — those assertions must match the
# agent's actual frontmatter, or the framework tests the wrong thing.
bad=""
while IFS= read -r -d '' f; do
  a=$(basename "$f" .md); rf=".claude/agents/$a.md"
  [ -f "$rf" ] || continue
  real=$(fm model "$rf")
  claim=$(grep -m1 -i 'model tier' "$f" | sed 's/.*[Mm]odel tier//' \
          | tr -d '*:` ' | tr 'A-Z' 'a-z' | sed 's/^is//' | sed 's/[^a-z].*//')
  [ -n "$claim" ] && [ "$claim" != "$real" ] && bad="$bad $a(spec=$claim,real=$real)"
done < <(find "$FRAMEWORK/agents" -name '*.md' -print0)
[ -z "$bad" ] && pass "framework tier assertions match agent frontmatter" \
              || fail "framework asserts wrong model tier" "$bad"

# Framework agent specs must assert the fields agents actually have. All 49
# specs once asserted `allowed-tools:`, a skill-only field, so every agent spec
# would have failed. This check is scoped to the framework because the specs
# are prose about frontmatter, not frontmatter themselves.
bad=$(grep -rl 'allowed-tools' "$FRAMEWORK/agents/" 2>/dev/null || true)
[ -z "$bad" ] && pass "no agent spec asserts 'allowed-tools:' (agents use 'tools:')" \
              || fail "agent specs asserting the skill-only field 'allowed-tools:'" "$bad"

# Every spec file must be registered in the catalog, or it never runs.
unreg=""
while IFS= read -r -d '' f; do
  n=$(basename "$f" .md)
  grep -q "name: $n$" "$FRAMEWORK/catalog.yaml" || unreg="$unreg $n"
done < <(find "$FRAMEWORK/skills" -name '*.md' -print0)
[ -z "$unreg" ] && pass "every skill spec is registered in catalog.yaml" \
                || fail "skill specs missing from catalog.yaml" "$unreg"

# ---------------------------------------------------------------------------
section "Documentation consistency"
# ---------------------------------------------------------------------------

# README badge counts drift silently as agents and skills are added.
a_count=$(echo "$AGENTS" | wc -l | tr -d ' ')
s_count=$(echo "$SKILLS" | wc -l | tr -d ' ')
grep -q "badge/agents-$a_count-" README.md \
  && pass "README agent badge matches reality ($a_count)" \
  || fail "README agent badge is stale" "actual: $a_count"
grep -q "badge/skills-$s_count-" README.md \
  && pass "README skill badge matches reality ($s_count)" \
  || fail "README skill badge is stale" "actual: $s_count"

# The Haiku/Opus skill lists in coordination-rules.md are hand-maintained and
# drifted from reality before (it claimed /story-readiness was Haiku).
for tier in haiku opus; do
  actual=$(grep -l "^model: $tier\$" $SKILLS | sed 's|.claude/skills/||;s|/SKILL.md||' | sort)
  listed=$(sed -n "/^Skills with \`model: $tier\`/,/^\$/p" .claude/docs/coordination-rules.md \
           | grep -oE '/[a-z-]+' | sed 's|^/||' | sort)
  d=$(diff <(echo "$actual") <(echo "$listed") 2>/dev/null || true)
  [ -z "$d" ] && pass "coordination-rules.md '$tier' skill list matches reality" \
              || fail "coordination-rules.md '$tier' list is stale" "$d"
done

# Skills that depend on a doc template must reference one that exists.
# Only hard dependencies are checked: lines that Glob for a template and
# document an explicit "if not found" fallback (e.g. /patch-notes) are
# intentionally optional, so they are excluded.
missing=""
while IFS= read -r p; do
  [ -n "$p" ] && [ ! -f "$p" ] && missing="$missing $p"
done <<< "$(grep -rh '\.claude/docs/templates/[a-z0-9-]*\.md' .claude/skills/ \
            | grep -viE 'glob|if found|if not found|available at' \
            | grep -oE '\.claude/docs/templates/[a-z0-9-]+\.md' | sort -u)"
[ -z "$missing" ] && pass "all required skill template references resolve" \
                  || fail "skills depend on missing templates" "$missing"

# ---------------------------------------------------------------------------
section "Hooks"
# ---------------------------------------------------------------------------

missing=""
while IFS= read -r h; do
  [ -f "$h" ] || missing="$missing $h"
done <<< "$(grep -oE '\.claude/hooks/[a-z-]+\.sh' .claude/settings.json | sort -u)"
[ -z "$missing" ] && pass "every hook in settings.json exists on disk" \
                  || fail "settings.json references missing hooks" "$missing"

if command -v bash >/dev/null; then
  bad=""
  for h in .claude/hooks/*.sh; do bash -n "$h" 2>/dev/null || bad="$bad $h"; done
  [ -z "$bad" ] && pass "all hook scripts parse without syntax errors" \
                || fail "hook scripts with syntax errors" "$bad"
fi

# ---------------------------------------------------------------------------
printf '\n─────────────────────────────────────────────\n'
if [ "$FAILED" -eq 0 ]; then
  printf '\033[32m%d/%d checks passed\033[0m\n' "$CHECKS" "$CHECKS"
  exit 0
else
  printf '\033[31m%d of %d checks FAILED\033[0m\n' "$FAILED" "$CHECKS"
  exit 1
fi

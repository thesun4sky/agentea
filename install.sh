#!/usr/bin/env bash
# agentea installer — https://github.com/thesun4sky/agentea
set -euo pipefail

REPO_URL="https://github.com/thesun4sky/agentea"
INSTALL_DIR="$HOME/.claude/agentea-src"
SKILLS_DIR="$HOME/.claude/skills"

echo "🫖 agentea 설치 중..."

# 1. Clone or update
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "  업데이트 중: $INSTALL_DIR"
  git -C "$INSTALL_DIR" pull --ff-only
else
  echo "  클론 중: $INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

# 2. Ensure skills dir exists
mkdir -p "$SKILLS_DIR"

# 3. Symlink all 8 skills
SKILLS=(status ask review council brainstorming clear off)

rm -rf "$SKILLS_DIR/agentea"
ln -sfn "$INSTALL_DIR" "$SKILLS_DIR/agentea"
echo "  ✅ agentea"

for sub in "${SKILLS[@]}"; do
  rm -rf "$SKILLS_DIR/agentea-$sub"
  ln -sfn "$INSTALL_DIR/agentea-$sub" "$SKILLS_DIR/agentea-$sub"
  echo "  ✅ agentea-$sub"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🍵 agentea 설치 완료!"
echo ""
echo "  업데이트: cd ~/.claude/agentea-src && git pull"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

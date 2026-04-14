#!/usr/bin/env bash
#
# Sync Upstream using Git Worktree
# 
# Safely pulls upstream changes and merges them into your integration
# branch using an isolated worktree. This prevents merge conflicts
# from destroying your current Xcode workspace / DerivedData.
#

set -e

# Configuration
INTEGRATION_BRANCH=${1:-"personal-main"}
MIRROR_BRANCH="main"
UPSTREAM_REMOTE="upstream"
WORKTREE_DIR="../osaurus-merge-zone"

echo "=========================================================="
echo " Syncing Upstream to Integration Branch: $INTEGRATION_BRANCH"
echo "=========================================================="
echo ""

# 1. Update the local mirror branch
echo "--> Step 1: Updating pure mirror branch ($MIRROR_BRANCH)..."
git checkout $MIRROR_BRANCH
git fetch $UPSTREAM_REMOTE
git merge --ff-only $UPSTREAM_REMOTE/$MIRROR_BRANCH

# 2. Setup the Worktree
echo "--> Step 2: Setting up isolated merge zone at $WORKTREE_DIR..."
# Remove if it exists and is stale
if [ -d "$WORKTREE_DIR" ]; then
    echo "    Cleaning up old worktree..."
    git worktree remove $WORKTREE_DIR --force || true
fi

# Ensure the integration branch exists
if ! git show-ref --verify --quiet refs/heads/$INTEGRATION_BRANCH; then
    echo "    Integration branch '$INTEGRATION_BRANCH' does not exist."
    echo "    Creating it from $MIRROR_BRANCH..."
    git branch $INTEGRATION_BRANCH $MIRROR_BRANCH
fi

git worktree add $WORKTREE_DIR $INTEGRATION_BRANCH

# 3. Perform the Merge
echo "--> Step 3: Merging $MIRROR_BRANCH into $INTEGRATION_BRANCH (without committing yet)..."
cd $WORKTREE_DIR

# We use --no-commit to allow testing BEFORE finalizing the merge.
# We use || true to prevent the script from exiting on merge conflicts.
git merge $MIRROR_BRANCH --no-commit || MERGE_STATUS=$?

echo ""
if [ "$MERGE_STATUS" != "0" ]; then
    echo "⚠️  MERGE CONFLICT DETECTED ⚠️"
else
    echo "✅ Merge applied cleanly (but NOT committed yet)!"
fi

echo ""
echo "=========================================================="
echo " 🛑 SCRIPT PAUSED: TESTING PHASE REQUIRED 🛑 "
echo "=========================================================="
echo "The upstream changes are currently staged in the merge zone."
echo "Your primary workspace is completely untouched."
echo ""
echo "1. Run your tests in the isolated zone:"
echo "   cd $WORKTREE_DIR"
echo "   cd Packages/OsaurusCore && swift build 2>&1 | grep -E 'error:' | grep -v 'IkigaJSON'"
echo ""
echo "2. Open the Xcode workspace if you need to debug or fix conflicts:"
echo "   open $WORKTREE_DIR/osaurus.xcworkspace"
echo ""
echo "3. TO FINALIZE (If tests pass):"
echo "   cd $WORKTREE_DIR"
echo "   git commit -m \"chore: merge upstream main into $INTEGRATION_BRANCH\""
echo "   cd ../osaurus"
echo "   git worktree remove $WORKTREE_DIR"
echo "   git checkout $INTEGRATION_BRANCH"
echo ""
echo "4. TO ABORT (If tests fail or it's broken):"
echo "   cd $WORKTREE_DIR"
echo "   git merge --abort"
echo "   cd ../osaurus"
echo "   git worktree remove $WORKTREE_DIR --force"
echo "=========================================================="

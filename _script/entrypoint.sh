#!/bin/bash

# Exit on any error
set -e

###########################################
# Utility Functions
###########################################
print_header() {
    echo -e "\n=========================================="
    echo "🚀 $1"
    echo -e "==========================================\n"
}

handle_error() {
    echo "❌ Error: $1"
    exit 1
}

debug_log() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "$1"
    fi
}

###########################################
# Validation Functions
###########################################
validate_env_vars() {
    local required_vars=("TARGET_PATH" "NEW_TAG" "TAG_STRING" "GIT_USER_NAME" "GIT_USER_EMAIL" "GITHUB_TOKEN" "REPO" "BRANCH")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            handle_error "Required environment variable $var is not set"
        fi
    done

    # Check if at least one of TARGET_VALUES_FILE or FILE_PATTERN is set
    if [[ -z "$TARGET_VALUES_FILE" ]] && [[ -z "$FILE_PATTERN" ]]; then
        handle_error "Either TARGET_VALUES_FILE or FILE_PATTERN must be set"
    fi
}

###########################################
# File Operations
###########################################
update_file() {
    local file="$1"
    debug_log "\n🔄 Processing file: $file"

    # If dry run mode is enabled, show what would be changed
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Current tag in $file: $(grep "$TAG_STRING:" "$file")"
        echo "Would change to: $TAG_STRING: \"$NEW_TAG\""
        return
    fi

    # Create backup if requested
    if [[ "$BACKUP" == "true" ]]; then
        debug_log "\n💾 Creating backup..."
        cp "$file" "${file}.bak" || handle_error "Failed to create backup"
        debug_log "✅ Backup created: ${file}.bak"
    fi

    # Update the image tag
    debug_log "\n🔄 Updating image tag..."
    if [[ "$BACKUP" == "true" ]]; then
        sed -i.bak "/^\s*$TAG_STRING:/s|:.*|: \"$NEW_TAG\"|" "$file" || handle_error "Failed to update tag with backup"
    else
        sed -i "/^\s*$TAG_STRING:/s|:.*|: \"$NEW_TAG\"|" "$file" || handle_error "Failed to update tag"
    fi

    echo "✅ Updated $file"
}

###########################################
# Main Script
###########################################
print_header "Starting Git Update Process"

# Validate environment variables
validate_env_vars

# Print current configuration
echo "••••••••••••••••••••••• 📋 Configuration: ••••••••••••••••••••••••••••••••••"
echo "• Target repo: $REPO"
echo "• Target path: $TARGET_PATH"
echo "• Target values file: $TARGET_VALUES_FILE"
echo "• New Tag: $NEW_TAG"
echo "• Branch: $BRANCH"
echo "• Commit message: $COMMIT_MESSAGE $NEW_TAG in $TARGET_PATH ($TARGET_VALUES_FILE)"
echo "• Create PR: $CREATE_PR"
echo "•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••"

[[ "$DRY_RUN" == "true" ]] && echo "• Mode: Dry Run"
[[ -n "$TARGET_VALUES_FILE" ]] && echo "• File: $TARGET_VALUES_FILE"
[[ -n "$FILE_PATTERN" ]] && echo "• Pattern: $FILE_PATTERN"

# Navigate to the target directory
debug_log "\n📂 Navigating to target directory..."
cd "$TARGET_PATH" || handle_error "Directory not found: $TARGET_PATH"

# Directory contents (debug only)
debug_log "\n📑 Current directory contents:"
if [[ "${DEBUG:-false}" == "true" ]]; then
    ls -la
fi

###########################################
# Git Operations
###########################################
# Configure Git
debug_log "\n⚙️ Configuring Git..."
git config --global --add safe.directory /usr/src || handle_error "Failed to set safe.directory /usr/src"
git config --global --add safe.directory /github/workspace || handle_error "Failed to set safe.directory /github/workspace"
git config --global user.name "$GIT_USER_NAME" || handle_error "Failed to set git user name"
git config --global user.email "$GIT_USER_EMAIL" || handle_error "Failed to set git user email"
git config --global pull.rebase false || handle_error "Failed to set pull strategy"

# Git branch operations
debug_log "\n🔄 Setting up branch: $BRANCH"
git fetch origin > /dev/null 2>&1 || handle_error "Failed to fetch from remote"

# Check if branch exists locally or remotely
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    # Branch exists locally
    git checkout "$BRANCH" > /dev/null 2>&1 || handle_error "Failed to checkout branch: $BRANCH"
    
    # Pull if remote branch exists
    if git ls-remote --heads origin "$BRANCH" | grep -q "$BRANCH"; then
        debug_log "\n⬇️ Pulling latest changes..."
        git pull origin "$BRANCH" > /dev/null 2>&1 || handle_error "Failed to pull latest changes"
    fi
else
    # Check if branch exists in remote
    if git ls-remote --heads origin "$BRANCH" | grep -q "$BRANCH"; then
        # Remote branch exists, checkout and track it
        git checkout -b "$BRANCH" origin/"$BRANCH" > /dev/null 2>&1 || handle_error "Failed to checkout remote branch"
        debug_log "\n⬇️ Pulling latest changes..."
        git pull origin "$BRANCH" > /dev/null 2>&1 || handle_error "Failed to pull latest changes"
    else
        # Create new branch locally
        debug_log "Creating new local branch: $BRANCH"
        git checkout -b "$BRANCH" > /dev/null 2>&1 || handle_error "Failed to create new branch"
    fi
fi

###########################################
# File Processing
###########################################
if [[ -n "$FILE_PATTERN" ]]; then
    debug_log "\n🔍 Processing files: $FILE_PATTERN"
    files=($FILE_PATTERN)
    if [ ${#files[@]} -eq 0 ]; then
        handle_error "No files found matching pattern: $FILE_PATTERN"
    fi
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            update_file "$file"
        fi
    done
else
    VALUES_FILE="$TARGET_VALUES_FILE"
    if [[ ! -f "$VALUES_FILE" ]]; then
        handle_error "File not found: $VALUES_FILE"
    fi
    update_file "$VALUES_FILE"
fi

# Handle dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "\n✅ Dry run completed. No changes were made."
    exit 0
fi

###########################################
# Commit and Push Changes
###########################################
debug_log "\n📦 Staging changes..."
git add . > /dev/null 2>&1 || handle_error "Failed to stage changes"

# Create commit message
if [[ -n "$FILE_PATTERN" ]]; then
    COMMIT_MESSAGE="$COMMIT_MESSAGE $TARGET_PATH ($FILE_PATTERN)"
else
    COMMIT_MESSAGE="$COMMIT_MESSAGE $NEW_TAG in $TARGET_PATH ($TARGET_VALUES_FILE)"
fi

debug_log "\n💾 Creating commit..."
git commit -m "$COMMIT_MESSAGE" > /dev/null 2>&1 || handle_error "Failed to commit changes"

# Push changes with retry logic
MAX_RETRIES=3
RETRY_COUNT=0
while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    if git push "https://x-access-token:$GITHUB_TOKEN@github.com/$REPO" "$BRANCH" > /dev/null 2>&1; then
        echo "✅ Successfully pushed changes to $BRANCH"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [[ $RETRY_COUNT -eq $MAX_RETRIES ]]; then
            handle_error "Failed to push changes after $MAX_RETRIES attempts"
        fi
        debug_log "⚠️ Push failed, retrying... (Attempt $RETRY_COUNT of $MAX_RETRIES)"
        sleep 5
    fi
done

# Create Pull Request only if CREATE_PR is explicitly set to "true"
if [[ "$CREATE_PR" == "true" ]]; then
    if [[ -z "$TARGET_BRANCH_PR" ]]; then
        TARGET_BRANCH_PR="main"
    fi
    echo "Authenticating with GitHub..."
# Authenticate with GitHub using GITHUB_TOKEN, fallback to PAT if it fails
    GH_TOKEN="$GITHUB_TOKEN" gh auth status || {
        handle_error "GITHUB_TOKEN authentication failed, trying PAT..."
        echo "$GITHUB_TOKEN" | gh auth login --with-token || {
            handle_error "Failed to authenticate with both GITHUB_TOKEN and PAT"
        }
    }
    echo "🚀 Creating a pull request to $TARGET_BRANCH_PR..."
    gh pr create --base "$TARGET_BRANCH_PR" --head "$BRANCH" \
        --title "Automated PR by Github Action: Merging $BRANCH into $TARGET_BRANCH_PR" \
        --body "This PR was created by Github Action for change image to deploy new version" || {
        echo "❌ Failed to create pull request"
        exit 1
    }
    echo "✅ Pull request created successfully!"
fi

print_header " Process Completed Successfully"
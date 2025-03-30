import os
import subprocess
import sys

def print_header(message):
    print(f"\n==========================================")
    print(f"🚀 {message}")
    print(f"==========================================\n")

def handle_error(message):
    print(f"❌ Error: {message}")
    sys.exit(1)

def debug_log(message):
    if os.getenv("DEBUG", "false").lower() == "true":
        print(message)

def print_configuration():
    print("\n••••••••••••••••••••••• 📋 Configuration: ••••••••••••••••••••••••••••••••••")
    print(f"• Target repo: {os.getenv('REPO')}")
    print(f"• Target path: {os.getenv('TARGET_PATH')}")
    print(f"• Target values file: {os.getenv('TARGET_VALUES_FILE')}")
    print(f"• New Tag: {os.getenv('NEW_TAG')}")
    print(f"• Branch: {os.getenv('BRANCH')}")
    print(f"• Commit message: {os.getenv('COMMIT_MESSAGE', 'Update tag')} {os.getenv('NEW_TAG')} in {os.getenv('TARGET_PATH')} ({os.getenv('TARGET_VALUES_FILE')})")
    print(f"• Create PR: {os.getenv('CREATE_PR')}")
    print("•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••\n")

def validate_env_vars():
    required_vars = [
        "TARGET_PATH", "NEW_TAG", "TAG_STRING", "GIT_USER_NAME", "GIT_USER_EMAIL", 
        "GITHUB_TOKEN", "REPO", "BRANCH"
    ]
    
    for var in required_vars:
        if not os.getenv(var):
            handle_error(f"Required environment variable {var} is not set")
    
    if not os.getenv("TARGET_VALUES_FILE") and not os.getenv("FILE_PATTERN"):
        handle_error("Either TARGET_VALUES_FILE or FILE_PATTERN must be set")

def update_file(file_path, new_tag, tag_string, backup=False, dry_run=False):
    debug_log(f"\n🔄 Processing file: {file_path}")
    
    if dry_run:
        print(f"Current tag in {file_path}: {tag_string}")
        print(f"Would change to: {tag_string}: \"{new_tag}\"")
        return
    
    if backup:
        subprocess.run(["cp", file_path, f"{file_path}.bak"], check=True)
        debug_log(f"✅ Backup created: {file_path}.bak")
    
    with open(file_path, "r") as file:
        content = file.read()
    
    content = content.replace(f"{tag_string}:", f"{tag_string}: \"{new_tag}\"")
    
    with open(file_path, "w") as file:
        file.write(content)
    
    print(f"✅ Updated {file_path}")

def run_command(command, allow_fail=False):
    debug_log(f"Executing: {command}")
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    if result.returncode != 0 and not allow_fail:
        handle_error(f"Command failed: {command}\n{result.stderr}")
    return result.stdout.strip()

def git_setup():
    run_command("git config --global --add safe.directory /github/workspace") 
    run_command("git config --global user.name \"" + os.getenv("GIT_USER_NAME") + "\"")
    run_command("git config --global user.email \"" + os.getenv("GIT_USER_EMAIL") + "\"")
    run_command("git config --global pull.rebase false")

def git_commit_push():
    branch = os.getenv("BRANCH")
    new_tag = os.getenv("NEW_TAG")
    commit_message = os.getenv("COMMIT_MESSAGE", "Update tag")
    target_path = os.getenv("TARGET_PATH")
    target_file = os.getenv("TARGET_VALUES_FILE")
    
    run_command("git fetch origin")
    existing_branch = run_command(f"git ls-remote --heads origin {branch}", allow_fail=True)
    
    if existing_branch:
        run_command(f"git checkout {branch}")
        run_command(f"git pull origin {branch}")
    else:
        run_command(f"git checkout -b {branch}")
    
    run_command("git add .")
    run_command(f"git commit -m \"{commit_message} {new_tag} in {target_path} ({target_file})\"")
    
    retries = 3
    for attempt in range(retries):
        try:
            run_command(f"git push https://x-access-token:{os.getenv('GITHUB_TOKEN')}@github.com/{os.getenv('REPO')} {branch}")
            print("✅ Successfully pushed changes")
            break
        except Exception as e:
            if attempt == retries - 1:
                handle_error(f"Failed to push after {retries} attempts: {e}")
            debug_log("⚠️ Push failed, retrying...")

def create_pull_request():
    if os.getenv("CREATE_PR") == "true":
        target_branch = os.getenv("TARGET_BRANCH_PR", "main")
        run_command("echo $GITHUB_TOKEN | gh auth login --with-token", allow_fail=True)
        run_command(f"gh pr create --base {target_branch} --head {os.getenv('BRANCH')} --title \"Automated PR\" --body \"Automated PR for updating tags\"")
        print("✅ Pull request created successfully!")

def main():
    print_header("Starting Git Update Process")
    print_configuration()
    validate_env_vars()
    git_setup()
    
    os.chdir(os.getenv("TARGET_PATH"))
    
    file_pattern = os.getenv("FILE_PATTERN")
    target_file = os.getenv("TARGET_VALUES_FILE")
    
    if file_pattern:
        for file in os.listdir():
            if file_pattern in file:
                update_file(file, os.getenv("NEW_TAG"), os.getenv("TAG_STRING"), backup=os.getenv("BACKUP") == "true", dry_run=os.getenv("DRY_RUN") == "true")
    elif target_file:
        if os.path.exists(target_file):
            update_file(target_file, os.getenv("NEW_TAG"), os.getenv("TAG_STRING"), backup=os.getenv("BACKUP") == "true", dry_run=os.getenv("DRY_RUN") == "true")
        else:
            handle_error(f"File not found: {target_file}")
    
    if os.getenv("DRY_RUN") == "true":
        print("✅ Dry run completed. No changes were made.")
        return
    
    git_commit_push()
    create_pull_request()
    print_header("Process Completed Successfully")

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Create Thematic PRs from Overnight Run

Groups the 256 staged files into 5-10 logical PRs by feature area.
"""

import subprocess
import sys
from pathlib import Path

PROJECT_PATH = "/Users/srowe/Projects/cuemap"

# Define file groupings by feature area
FILE_GROUPS = {
    "accessibility": {
        "name": "Accessibility Features",
        "patterns": ["Accessibility/", "accessibility_", "VoiceOver", "AssistiveTouch", "HearingAid", "ColorBlind", "ReducedMotion"],
        "description": "Comprehensive accessibility features including VoiceOver support, assistive touch, hearing aid profiles, color blind palettes, and reduced motion visualizations."
    },
    "security-privacy": {
        "name": "Security & Privacy",
        "patterns": ["Security/", "security_", "GDPR", "TwoFactor", "Biometric", "Encryption", "Audit"],
        "description": "Security and privacy features including GDPR compliance, two-factor authentication, biometric auth, encryption, and audit logging."
    },
    "analytics-gamification": {
        "name": "Analytics & Gamification",
        "patterns": ["Analytics/", "analytics_", "Achievement", "Progress", "Goal", "Streak", "practice_streaks", "progress_analytics"],
        "description": "Practice analytics, achievement tracking, goals dashboard, performance comparison, and progress visualization."
    },
    "ui-keyboard-responsive": {
        "name": "UI, Keyboard & Responsive Design",
        "patterns": ["UI/", "Keyboard", "keyboard_shortcuts", "Responsive", "responsive_design", "Layout", "Navigation", "AndroidNavigation", "AndroidSystemUI", "ExternalDisplay", "FullScreen"],
        "description": "UI services, keyboard shortcuts, responsive design, layout management, and cross-platform navigation."
    },
    "practice-features": {
        "name": "Practice Features",
        "patterns": ["Practice/", "practice_", "Repetition", "Loop", "Annotation", "RealTimeFeedback", "GoalValidation", "practice_playlists", "practice_session"],
        "description": "Practice-specific features including repetition tracking, loop controls, annotations, real-time feedback, and goal validation."
    },
    "notifications-collaboration": {
        "name": "Notifications & Collaboration",
        "patterns": ["Notifications/", "NotificationService", "Collaboration/", "ECDH", "RemoteJam", "secure_key_exchange"],
        "description": "Notification system and collaboration features including secure key exchange for band collaboration."
    },
    "performance-testing": {
        "name": "Performance Testing",
        "patterns": ["performance_", "large_audio_streaming", "Performance/"],
        "description": "Extended performance testing and stress analysis for large audio files, markers, and playlists."
    },
    "audio-infrastructure": {
        "name": "Audio Infrastructure",
        "patterns": ["Audio/", "audio_", "BPM", "Tempo", "AudioWarper", "AudioTranscription", "bpm_detector", "tempo_detector"],
        "description": "Audio processing infrastructure including BPM detection, tempo normalization, and audio transcription."
    },
    "domain-entities": {
        "name": "Domain Entities & Models",
        "patterns": ["Domain/Entities/", "Domain/Practice/", "Domain/Security/", "Domain/UI/", "Domain/Accessibility/", "Domain/Analytics/", "Domain/Collaboration/"],
        "description": "Core domain entities and value objects across all feature areas."
    },
    "infrastructure-persistence": {
        "name": "Infrastructure & Persistence",
        "patterns": ["Infrastructure/", "Persistence/", "Monitoring/", "FFI", "IncidentTracker", "RootCauseAnalyzer"],
        "description": "Infrastructure layer including persistence, monitoring, and platform-specific FFI bindings."
    },
    "build-tests": {
        "name": "Build System & Tests",
        "patterns": ["CMakeLists.txt", "Tests/", "do_build.sh"],
        "description": "Build system configuration and BDD test step definitions."
    }
}

def get_staged_files():
    """Get all staged files from git"""
    result = subprocess.run(
        ['git', 'diff', '--cached', '--name-only'],
        cwd=PROJECT_PATH,
        capture_output=True,
        text=True,
        check=True
    )
    return [f.strip() for f in result.stdout.strip().split('\n') if f.strip()]

def categorize_files(files):
    """Categorize files into groups"""
    groups = {key: [] for key in FILE_GROUPS.keys()}
    uncategorized = []

    for file_path in files:
        matched = False
        for group_key, group_info in FILE_GROUPS.items():
            for pattern in group_info['patterns']:
                if pattern in file_path:
                    groups[group_key].append(file_path)
                    matched = True
                    break
            if matched:
                break

        if not matched:
            uncategorized.append(file_path)

    return groups, uncategorized

def create_pr_for_group(group_key, files):
    """Create a branch, commit, and PR for a group of files"""
    if not files:
        print(f"No files for {group_key}, skipping...")
        return False

    group_info = FILE_GROUPS[group_key]

    print(f"\n{'='*80}")
    print(f"Creating PR: {group_info['name']}")
    print(f"Files: {len(files)}")
    print(f"{'='*80}")

    try:
        # Create branch name
        branch_name = f"feat/bdd-{group_key}"

        # Check if branch exists
        result = subprocess.run(
            ['git', 'rev-parse', '--verify', branch_name],
            cwd=PROJECT_PATH,
            capture_output=True
        )

        if result.returncode == 0:
            import random
            branch_name = f"{branch_name}-{random.randint(1000, 9999)}"

        # Checkout main
        print("Checking out main...")
        subprocess.run(['git', 'checkout', 'main'], cwd=PROJECT_PATH, check=True)
        subprocess.run(['git', 'pull'], cwd=PROJECT_PATH, check=True)

        # Create branch
        print(f"Creating branch: {branch_name}")
        subprocess.run(['git', 'checkout', '-b', branch_name], cwd=PROJECT_PATH, check=True)

        # Checkout files from overnight branch
        print("Checking out files...")
        subprocess.run(
            ['git', 'checkout', 'feat/agent-overnight-implementations-20251116', '--'] + files,
            cwd=PROJECT_PATH,
            check=True
        )

        # Add files
        subprocess.run(['git', 'add'] + files, cwd=PROJECT_PATH, check=True)

        # Create commit
        commit_msg = f"""feat(bdd): {group_info['name']}

{group_info['description']}

Implemented by autonomous BDD agent overnight run.
Retroactively organized into thematic PR for review.

Files changed: {len(files)}

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>
"""

        print("Creating commit...")
        subprocess.run(['git', 'commit', '-m', commit_msg], cwd=PROJECT_PATH, check=True)

        # Push
        print("Pushing...")
        subprocess.run(['git', 'push', '-u', 'origin', branch_name], cwd=PROJECT_PATH, check=True)

        # Create PR
        pr_title = f"feat(bdd): {group_info['name']}"
        pr_body = f"""## {group_info['name']}

### Description

{group_info['description']}

### Implementation Details

This PR contains {len(files)} files implementing BDD steps from the autonomous overnight run:

"""
        # Add file list
        file_categories = {}
        for f in files:
            parts = f.split('/')
            if len(parts) > 2:
                category = '/'.join(parts[:3])
            else:
                category = parts[0]

            if category not in file_categories:
                file_categories[category] = []
            file_categories[category].append(f)

        for category in sorted(file_categories.keys()):
            pr_body += f"\n**{category}/**\n"
            for f in sorted(file_categories[category])[:10]:
                pr_body += f"- `{f}`\n"
            if len(file_categories[category]) > 10:
                pr_body += f"- ... and {len(file_categories[category]) - 10} more files\n"

        pr_body += f"""

### Test Status

✅ Implemented by autonomous BDD agent
⚠️ Requires review and potential build fixes

### Labels

- `agent-generated` - Generated by autonomous BDD agent
- `bdd` - BDD step implementation
- `retroactive` - Retroactively created from overnight run

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
"""

        print("Creating PR...")
        pr_result = subprocess.run(
            ['gh', 'pr', 'create',
             '--title', pr_title,
             '--body', pr_body,
             '--label', 'agent-generated',
             '--label', 'bdd',
             '--label', 'retroactive'],
            cwd=PROJECT_PATH,
            capture_output=True,
            text=True,
            check=True
        )

        pr_url = pr_result.stdout.strip()
        print(f"✅ Created PR: {pr_url}")

        # Return to overnight branch
        subprocess.run(['git', 'checkout', 'feat/agent-overnight-implementations-20251116'], cwd=PROJECT_PATH, check=True)

        return True

    except subprocess.CalledProcessError as e:
        print(f"❌ Error: {e}")
        if hasattr(e, 'stderr'):
            print(f"stderr: {e.stderr}")
        subprocess.run(['git', 'checkout', 'feat/agent-overnight-implementations-20251116'], cwd=PROJECT_PATH)
        return False

def main():
    print("Thematic PR Creator for Overnight BDD Run")
    print("=" * 80)

    # Ensure we're on the overnight branch
    subprocess.run(['git', 'checkout', 'feat/agent-overnight-implementations-20251116'], cwd=PROJECT_PATH, check=True)

    # Get all staged files
    files = get_staged_files()
    print(f"Total staged files: {len(files)}")

    # Categorize
    groups, uncategorized = categorize_files(files)

    # Show summary
    print(f"\n{'='*80}")
    print("FILE GROUPINGS")
    print(f"{'='*80}")
    for key, group_files in groups.items():
        if group_files:
            print(f"{FILE_GROUPS[key]['name']}: {len(group_files)} files")

    if uncategorized:
        print(f"Uncategorized: {len(uncategorized)} files")
        print("\nUncategorized files:")
        for f in uncategorized[:10]:
            print(f"  - {f}")
        if len(uncategorized) > 10:
            print(f"  ... and {len(uncategorized) - 10} more")

    # Ask for confirmation
    print(f"\n{'='*80}")
    response = input("Create PRs for these groups? (y/n): ").lower()
    if response != 'y':
        print("Aborted.")
        return

    # Create PRs
    success_count = 0
    for key in FILE_GROUPS.keys():
        if groups[key]:
            if create_pr_for_group(key, groups[key]):
                success_count += 1

            # Ask to continue after each PR
            if success_count > 0:
                cont = input("\nContinue to next PR? (y/n): ").lower()
                if cont != 'y':
                    print("Stopped.")
                    break

    print(f"\n{'='*80}")
    print("SUMMARY")
    print(f"{'='*80}")
    print(f"PRs created: {success_count}")
    print(f"{'='*80}")

if __name__ == '__main__':
    main()

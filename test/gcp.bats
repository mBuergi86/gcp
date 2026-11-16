#!/usr/bin/env bats
# Tests for gcp. Every test runs in its own temporary repository with a
# local bare repository as remote, so nothing touches the network.
#
# Run: bats test/

setup() {
    GCP="$BATS_TEST_DIRNAME/../gcp"
    TMP="$BATS_TEST_TMPDIR"

    # Isolated git config, English messages, UTF-8
    export HOME="$TMP/home"
    export GIT_CONFIG_NOSYSTEM=1
    export LC_ALL=C.UTF-8
    mkdir -p "$HOME"
    git config --global user.name "Test"
    git config --global user.email "test@example.com"
    git config --global init.defaultBranch main

    # gitleaks is tested separately; the numbered list instead of fzf for -i
    export SKIP_GITLEAKS=1 GCP_NO_FZF=1
    unset ALLOW_MAIN GCP_YES

    git init -q --bare "$TMP/remote.git"
    git init -q "$TMP/work"
    cd "$TMP/work"
    git remote add origin "$TMP/remote.git"
    git switch -q -c feat/test
}

gcp() {
    bash "$GCP" "$@"
}

# run_tty "<input>" <args...>: run gcp in a pseudo terminal, feeding <input>
run_tty() {
    local input="$1"
    shift
    local cmd
    printf -v cmd '%q ' bash "$GCP" "$@"
    run bash -c "printf '%s\n' $(printf '%q' "$input") | script -qec $(printf '%q' "$cmd") /dev/null"
}

subject() {
    git log -1 --format=%s "${1:-HEAD}"
}

remote_subject() {
    git --git-dir="$TMP/remote.git" log -1 --format=%s "${1:-feat/test}"
}

# Make one pushed commit so the branch has an upstream
first_commit() {
    echo base > base.txt
    gcp -y "chore: initial commit" >/dev/null
}

# ---------------------------------------------------------------------------
# Help and arguments
# ---------------------------------------------------------------------------

@test "-h shows the help" {
    run gcp -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"gcp status"* ]]
    [[ "$output" == *"gcp undo"* ]]
}

@test "--version, -v and -V print the version" {
    run gcp --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^gcp\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
    [ "$(gcp -V)" = "$output" ]
    [ "$(gcp -v)" = "$output" ]
}

@test "unknown option is rejected" {
    run gcp --nope "fix: x"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option: --nope"* ]]
}

@test "no arguments shows usage" {
    run gcp
    [ "$status" -eq 1 ]
    [[ "$output" == *"usage:"* ]]
}

# ---------------------------------------------------------------------------
# Commit message and gitmoji
# ---------------------------------------------------------------------------

@test "adds gitmoji by type" {
    echo a > a.txt
    run gcp -y "feat(api): add endpoint"
    [ "$status" -eq 0 ]
    [ "$(subject)" = "feat(api): ✨ add endpoint" ]
}

@test "keeps own unicode gitmoji" {
    echo a > a.txt
    gcp -y "chore: ⬆️ bump deps"
    [ "$(subject)" = "chore: ⬆️ bump deps" ]
}

@test "keeps own gitmoji shortcode" {
    echo a > a.txt
    gcp -y "fix: :ambulance: hotfix"
    [ "$(subject)" = "fix: :ambulance: hotfix" ]
}

@test "description starting with an umlaut still gets a gitmoji" {
    echo a > a.txt
    gcp -y "docs: Übersetzung ergänzt"
    [ "$(subject)" = "docs: 📝 Übersetzung ergänzt" ]
}

@test "breaking change with ! gets 💥" {
    echo a > a.txt
    gcp -y "feat!: new api"
    [ "$(subject)" = "feat!: 💥 new api" ]
}

@test "BREAKING CHANGE footer gets 💥 and keeps the body" {
    echo a > a.txt
    gcp -y "$(printf 'refactor: new auth\n\nBREAKING CHANGE: login moved')"
    [ "$(subject)" = "refactor: 💥 new auth" ]
    [[ "$(git log -1 --format=%b)" == *"BREAKING CHANGE: login moved"* ]]
}

@test "rejects a message that is not Conventional Commits" {
    echo a > a.txt
    run gcp -y "added stuff"
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not follow Conventional Commits"* ]]
}

@test "rejects a header that is too long" {
    echo a > a.txt
    run gcp -y "docs: $(printf 'x%.0s' {1..80})"
    [ "$status" -eq 1 ]
    [[ "$output" == *"max is 72"* ]]
}

@test "unquoted message is caught" {
    echo a > a.txt
    run gcp -y fix: something
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Safety checks
# ---------------------------------------------------------------------------

@test "refuses to commit on main without ALLOW_MAIN" {
    git switch -q -c main
    echo a > a.txt
    run gcp -y "fix: x"
    [ "$status" -eq 1 ]
    [[ "$output" == *"refusing to commit directly to main"* ]]
}

@test "commits on main with ALLOW_MAIN=1" {
    git switch -q -c main
    echo a > a.txt
    ALLOW_MAIN=1 run gcp -y "fix: x"
    [ "$status" -eq 0 ]
    [ "$(remote_subject main)" = "fix: 🐛 x" ]
}

@test "blocks .env, unstages and keeps the file" {
    echo SECRET=1 > .env
    run gcp -y "chore: add env"
    [ "$status" -eq 1 ]
    [[ "$output" == *"look like secrets"* ]]
    [ -f .env ]
    [ -z "$(git diff --cached --name-only)" ]
    ! git rev-parse -q --verify HEAD
}

@test "allows .env.example" {
    echo SECRET= > .env.example
    run gcp -y "chore: add env example"
    [ "$status" -eq 0 ]
}

@test "blocks files of 100 MiB or more" {
    truncate -s 100M big.bin
    run gcp -y "chore: add big file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"100 MiB or more"* ]]
    [ -z "$(git diff --cached --name-only)" ]
}

@test "refuses without a remote" {
    git remote remove origin
    echo a > a.txt
    run gcp -y "fix: x"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no remote configured"* ]]
}

@test "refuses without a terminal and without -y" {
    echo a > a.txt
    run gcp "fix: x" < /dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Use -y"* ]]
}

@test "confirmation n aborts without committing" {
    echo a > a.txt
    run_tty "n" "fix: x"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aborted."* ]]
    ! git rev-parse -q --verify HEAD
}

@test "nothing to commit" {
    first_commit
    run gcp -y "fix: x"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to commit."* ]]
}

@test "gitleaks finds a secret in the content" {
    command -v gitleaks >/dev/null || skip "gitleaks not installed"
    # Built at runtime so this test file itself contains no token
    printf 'token = "ghp_%s"\n' "$(printf 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8')" > config.txt
    SKIP_GITLEAKS=0 run gcp -y "chore: add config"
    [ "$status" -eq 1 ]
    [[ "$output" == *"gitleaks found possible secrets"* ]]
    ! git rev-parse -q --verify HEAD
}

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

@test "commits only the given paths, other changes stay" {
    echo a > a.txt
    echo b > b.txt
    echo s > staged.txt
    git add staged.txt
    run gcp -y "feat: add a" a.txt
    [ "$status" -eq 0 ]
    [ "$(git show --format= --name-only HEAD)" = "a.txt" ]
    [ "$(git diff --cached --name-only)" = "staged.txt" ]
    [[ "$(git status --porcelain)" == *"?? b.txt"* ]]
}

@test "commits a deleted file by path" {
    first_commit
    rm base.txt
    run gcp -y "chore: remove base" base.txt
    [ "$status" -eq 0 ]
    [ ! -e base.txt ]
    [ -z "$(git ls-files base.txt)" ]
}

@test "unknown path is rejected" {
    echo a > a.txt
    run gcp -y "fix: x" nope.txt
    [ "$status" -eq 1 ]
    [[ "$output" == *"path not found"* ]]
}

@test "nothing to commit in the given paths" {
    first_commit
    echo a > a.txt
    run gcp -y "fix: x" base.txt
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to commit in the given paths."* ]]
}

# ---------------------------------------------------------------------------
# Interactive selection (numbered list)
# ---------------------------------------------------------------------------

@test "-i commits the selected files" {
    echo a > a.txt
    echo b > b.txt
    echo c > c.txt
    run_tty "1 3" -iy "feat: pick some"
    [ "$status" -eq 0 ]
    [ "$(git show --format= --name-only HEAD | sort | paste -sd ' ' -)" = "a.txt c.txt" ]
}

@test "-i with empty selection aborts" {
    echo a > a.txt
    run_tty "" -iy "feat: pick none"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No files selected"* ]]
    ! git rev-parse -q --verify HEAD
}

@test "-i with an out of range selection fails" {
    echo a > a.txt
    run_tty "5" -iy "feat: pick"
    [[ "$output" == *"out of range"* ]]
}

@test "-i and paths cannot be combined" {
    echo a > a.txt
    run gcp -iy "feat: x" a.txt
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot be combined"* ]]
}

@test "-i on main is refused before the selection" {
    git switch -q -c main
    echo a > a.txt
    run_tty "1" -iy "feat: x"
    [[ "$output" == *"refusing to commit directly to main"* ]]
    [[ "$output" != *"Select files"* ]]
}

# ---------------------------------------------------------------------------
# Push
# ---------------------------------------------------------------------------

@test "first push sets the upstream" {
    first_commit
    [ "$(git rev-parse --abbrev-ref '@{u}')" = "origin/feat/test" ]
    [ "$(remote_subject)" = "chore: 🔧 initial commit" ]
}

@test "rebases onto new remote commits and keeps other changes" {
    first_commit
    git clone -q -b feat/test "$TMP/remote.git" "$TMP/other"
    (cd "$TMP/other" && echo r > remote.txt && git add . && git commit -qm "chore: remote" && git push -q)
    echo local > local.txt
    echo wip > wip.txt
    run gcp -y "feat: local change" local.txt
    [ "$status" -eq 0 ]
    [ "$(remote_subject)" = "feat: ✨ local change" ]
    [ -f remote.txt ]
    [ -f wip.txt ]
}

@test "unreachable remote: clear message, commit kept" {
    first_commit
    git remote set-url origin "$TMP/missing.git"
    echo a > a.txt
    run gcp -y "fix: offline"
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not pull"* ]]
    [[ "$output" != *"conflict"* ]]
    [ "$(subject)" = "fix: 🐛 offline" ]
}

# ---------------------------------------------------------------------------
# Release branches
# ---------------------------------------------------------------------------

release_setup() {
    git switch -q -c release/1.4
    echo base > base.txt
    gcp -y "chore: start release" >/dev/null
    git tag -a v1.4.0 -m v1.4.0
    git push -q origin v1.4.0
}

@test "fix on release branch creates the next patch tag" {
    release_setup
    echo fix > fix.txt
    run gcp -y "fix: correct export"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Released v1.4.1"* ]]
    git --git-dir="$TMP/remote.git" rev-parse -q --verify refs/tags/v1.4.1
}

@test "feat on release branch is rejected" {
    release_setup
    echo f > f.txt
    run gcp -y "feat: new thing"
    [ "$status" -eq 1 ]
    [[ "$output" == *"feat is not allowed"* ]]
}

@test "fix on release branch without base tag is rejected" {
    git switch -q -c release/2.0
    echo f > f.txt
    run gcp -y "fix: x"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no base tag"* ]]
}

# ---------------------------------------------------------------------------
# status and history
# ---------------------------------------------------------------------------

@test "status: clean branch is ready" {
    first_commit
    run gcp status
    [ "$status" -eq 0 ]
    [[ "$output" == *"up to date"* ]]
    [[ "$output" == *"Ready for gcp"* ]]
}

@test "status: warns about secrets and main" {
    git switch -q -c main
    echo x > .env
    run gcp status
    [ "$status" -eq 0 ]
    [[ "$output" == *".env looks like a secret"* ]]
    [[ "$output" == *"gcp needs ALLOW_MAIN=1"* ]]
}

@test "status: shows ahead count" {
    first_commit
    echo a > a.txt
    git add a.txt
    git commit -qm "local only"
    run gcp status
    [[ "$output" == *"1 ahead, 0 behind"* ]]
}

@test "history: lists commits, filters by type and count" {
    for m in "feat: one" "fix: two" "docs: three" "fix(api): four"; do
        echo "$m" >> log.txt
        gcp -y "$m" >/dev/null
    done
    run gcp history
    [ "${#lines[@]}" -eq 4 ]
    run gcp history fix
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[0]}" == *"fix(api): 🐛 four"* ]]
    run gcp history 1
    [ "${#lines[@]}" -eq 1 ]
    run gcp history perf
    [[ "$output" == *"No perf commits found."* ]]
}

@test "history: breaking filter" {
    echo a > a.txt
    gcp -y "feat: normal" >/dev/null
    echo b > b.txt
    gcp -y "feat!: big" >/dev/null
    run gcp history breaking
    [ "${#lines[@]}" -eq 1 ]
    [[ "$output" == *"feat!: 💥 big"* ]]
}

@test "history: invalid argument" {
    run gcp history foo
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# undo
# ---------------------------------------------------------------------------

@test "undo: local commit is removed, changes stay staged" {
    first_commit
    echo a > a.txt
    git add a.txt
    git commit -qm "feat: local"
    run gcp undo -y
    [ "$status" -eq 0 ]
    [ "$(subject)" = "chore: 🔧 initial commit" ]
    [ "$(git diff --cached --name-only)" = "a.txt" ]
}

@test "undo: first commit of a repository" {
    echo a > a.txt
    git add a.txt
    git commit -qm "feat: first"
    run gcp undo -y
    [ "$status" -eq 0 ]
    ! git rev-parse -q --verify HEAD
    [ "$(git diff --cached --name-only)" = "a.txt" ]
}

@test "undo: pushed commit is reverted and pushed" {
    first_commit
    echo a > a.txt
    gcp -y "feat: add a" >/dev/null
    run gcp undo -y
    [ "$status" -eq 0 ]
    [ "$(subject)" = "revert: ⏪️ feat: ✨ add a" ]
    [ "$(remote_subject)" = "revert: ⏪️ feat: ✨ add a" ]
    [ ! -e a.txt ]
}

@test "undo: refuses a merge commit" {
    first_commit
    git switch -q -c side
    echo s > s.txt && git add s.txt && git commit -qm "feat: side"
    git switch -q feat/test
    echo m > m.txt && git add m.txt && git commit -qm "feat: main"
    git merge -q --no-edit side
    run gcp undo -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"merge commit"* ]]
}

@test "undo: no commits" {
    run gcp undo -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"no commits yet"* ]]
}

# ---------------------------------------------------------------------------
# amend
# ---------------------------------------------------------------------------

# A pushed base commit plus one local, not yet pushed commit
local_commit() {
    first_commit
    echo a > a.txt
    git add a.txt
    git commit -qm "feat: ✨ add a"
}

@test "amend: adds a forgotten file to the last commit and pushes" {
    local_commit
    echo b > b.txt
    run gcp amend -y b.txt
    [ "$status" -eq 0 ]
    [ "$(subject)" = "feat: ✨ add a" ]
    [ "$(git show --format= --name-only HEAD | sort | paste -sd ' ' -)" = "a.txt b.txt" ]
    [ "$(remote_subject)" = "feat: ✨ add a" ]
}

@test "amend: changes only the message with -m" {
    local_commit
    run gcp amend -y -m "feat: add file a"
    [ "$status" -eq 0 ]
    [ "$(subject)" = "feat: ✨ add file a" ]
    [ "$(git show --format= --name-only HEAD)" = "a.txt" ]
}

@test "amend: refuses a pushed commit" {
    first_commit
    echo b > b.txt
    run gcp amend -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"already pushed"* ]]
}

@test "amend: nothing to amend" {
    local_commit
    run gcp amend -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to amend"* ]]
}

@test "amend: blocks secrets like a normal commit" {
    local_commit
    echo x > .env
    run gcp amend -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"look like secrets"* ]]
    [ "$(git show --format= --name-only HEAD)" = "a.txt" ]
}

@test "amend: invalid new message is rejected" {
    local_commit
    run gcp amend -y -m "bad message"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Conventional Commits"* ]]
}

# ---------------------------------------------------------------------------
# install.sh and completion
# ---------------------------------------------------------------------------

@test "install.sh: installs, sets up ~/.zshrc once, uninstalls" {
    local inst="$BATS_TEST_DIRNAME/../install.sh" prefix="$TMP/prefix"
    touch "$HOME/.zshrc"
    run bash "$inst" --prefix "$prefix" --zshrc
    [ "$status" -eq 0 ]
    [ -x "$prefix/bin/gcp" ]
    [ -f "$prefix/share/man/man1/gcp.1" ]
    [ -f "$prefix/share/zsh/site-functions/_gcp" ]
    [[ "$output" == *"Installed gcp "* ]]
    bash "$inst" --prefix "$prefix" --zshrc >/dev/null
    [ "$(grep -c '^unalias gcp' "$HOME/.zshrc")" -eq 1 ]
    [ "$(grep -c 'compdef _gcp gcp' "$HOME/.zshrc")" -eq 1 ]
    run bash "$inst" --prefix "$prefix" --uninstall
    [ "$status" -eq 0 ]
    [ ! -e "$prefix/bin/gcp" ]
    [ ! -e "$prefix/share/zsh/site-functions/_gcp" ]
}

@test "install.sh: rejects a malformed --version" {
    run bash "$BATS_TEST_DIRNAME/../install.sh" --version 1.0
    [ "$status" -eq 1 ]
    [[ "$output" == *"must look like 1.0.0"* ]]
}

@test "zsh completion has valid syntax" {
    command -v zsh >/dev/null || skip "zsh not installed"
    zsh -n "$BATS_TEST_DIRNAME/../completions/_gcp"
}

# ---------------------------------------------------------------------------
# new, sync, pr, changelog, release
# ---------------------------------------------------------------------------

# A main branch with one commit on the remote; we stay on main
main_setup() {
    git symbolic-ref HEAD refs/heads/main
    echo base > base.txt
    git add base.txt
    git commit -q -m "chore: initial commit"
    git push -q -u origin main
}

# Commit on main through a second clone, as if someone else pushed
remote_main_commit() {
    git clone -q "$TMP/remote.git" "$TMP/other"
    (
        cd "$TMP/other"
        echo "$1" > "$1.txt"
        git add "$1.txt"
        git commit -q -m "docs: $1"
        git push -q origin main
    )
    rm -rf "$TMP/other"
}

# Fake gh: logs every call, "pr create" prints a URL
fake_gh() {
    mkdir -p "$TMP/bin"
    cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
    "pr view")   [[ -n "${GH_EXISTING:-}" ]] && echo "$GH_EXISTING"; exit 0 ;;
    "pr create") echo "https://github.com/x/y/pull/7" ;;
esac
exit 0
GH
    chmod +x "$TMP/bin/gh"
    export PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log"
}

@test "new: creates type/name from the remote main, without upstream" {
    main_setup
    remote_main_commit later
    run gcp new feat "Login Form"
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "feat/login-form" ]
    [ -f later.txt ]
    [ -z "$(git config --get branch.feat/login-form.merge || true)" ]
}

@test "new: rejects an unknown type and an existing branch" {
    main_setup
    run gcp new feature login
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown type"* ]]
    gcp new fix crash >/dev/null
    git switch -q main
    run gcp new fix crash
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

@test "new: first gcp commit pushes the new branch, not main" {
    main_setup
    gcp new feat login >/dev/null
    echo x > x.txt
    gcp -y "feat: add login" >/dev/null
    [ "$(remote_subject feat/login)" = "feat: ✨ add login" ]
    [ "$(remote_subject main)" = "chore: initial commit" ]
}

@test "sync: rebases the branch onto new commits from main" {
    main_setup
    gcp new feat login >/dev/null
    echo x > x.txt
    gcp -y "feat: add login" >/dev/null
    remote_main_commit later
    run gcp sync -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"force-with-lease"* ]]
    [ -f later.txt ]
    [ "$(subject)" = "feat: ✨ add login" ]
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/feat/login)" ]
}

@test "sync: nothing to do" {
    main_setup
    gcp new feat login >/dev/null
    run gcp sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"already has all commits"* ]]
}

@test "sync: conflict explains how to continue or abort" {
    main_setup
    gcp new fix base >/dev/null
    echo mine > base.txt
    git commit -q -am "fix: mine"
    git clone -q "$TMP/remote.git" "$TMP/other"
    (cd "$TMP/other" && echo theirs > base.txt && git commit -q -am "fix: theirs" && git push -q origin main)
    run gcp sync
    [ "$status" -eq 1 ]
    [[ "$output" == *"git rebase --abort"* ]]
    git rebase --abort
}

@test "pr: refuses on main" {
    main_setup
    fake_gh
    run gcp pr -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"gcp new"* ]]
}

@test "pr: refuses without commits on the branch" {
    main_setup
    fake_gh
    gcp new feat login >/dev/null
    run gcp pr -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"no commits"* ]]
}

@test "pr: pushes and creates the PR, title from the only commit" {
    main_setup
    fake_gh
    gcp new feat login >/dev/null
    echo x > x.txt
    git add x.txt && git commit -q -m "feat: ✨ add login"
    run gcp pr -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"pull/7"* ]]
    [ "$(remote_subject feat/login)" = "feat: ✨ add login" ]
    grep -q -- "pr create --base main --head feat/login --title feat: ✨ add login" "$GH_LOG"
}

@test "pr: title from the branch name with several commits, --draft" {
    main_setup
    fake_gh
    gcp new feat login-form >/dev/null
    echo x > x.txt; git add x.txt; git commit -q -m "feat: ✨ add form"
    echo y > y.txt; git add y.txt; git commit -q -m "test: ✅ form tests"
    run gcp pr -y --draft
    [ "$status" -eq 0 ]
    grep -q -- "--title feat: ✨ login form" "$GH_LOG"
    grep -q -- "--draft" "$GH_LOG"
}

@test "pr: existing PR is only pushed" {
    main_setup
    fake_gh
    export GH_EXISTING="https://github.com/x/y/pull/3"
    gcp new fix crash >/dev/null
    echo x > x.txt; git add x.txt; git commit -q -m "fix: 🐛 crash"
    run gcp pr -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"pull/3"* ]]
    ! grep -q "pr create" "$GH_LOG"
}

@test "pr --merge: squash merges and goes back to main" {
    main_setup
    fake_gh
    gcp new fix crash >/dev/null
    echo x > x.txt; git add x.txt; git commit -q -m "fix: 🐛 crash"
    run gcp pr -y --merge
    [ "$status" -eq 0 ]
    grep -q -- "pr merge fix/crash --squash --delete-branch" "$GH_LOG"
    [ "$(git branch --show-current)" = "main" ]
    ! git rev-parse -q --verify refs/heads/fix/crash
}

@test "changelog: groups features, fixes and breaking changes since the last tag" {
    main_setup
    git tag -a v1.0.0 -m v1.0.0
    git commit -q --allow-empty -m "feat(ui): ✨ dark mode"
    git commit -q --allow-empty -m "fix: 🐛 crash on start"
    git commit -q --allow-empty -m "docs: 📝 readme"
    git commit -q --allow-empty -m "refactor!: 💥 new config format"
    run gcp changelog
    [ "$status" -eq 0 ]
    [[ "$output" == *"since v1.0.0"* ]]
    [[ "$output" == *"### 💥 Breaking Changes"*"new config format"* ]]
    [[ "$output" == *"### ✨ Features"*"**ui:** dark mode"* ]]
    [[ "$output" == *"### 🐛 Bug Fixes"*"crash on start"* ]]
    [[ "$output" != *"readme"* ]]
    run gcp changelog --all
    [[ "$output" == *"Other Changes"*"readme"* ]]
}

@test "release: feat bumps minor, tags and pushes" {
    main_setup
    git tag -a v1.0.0 -m v1.0.0 && git push -q origin v1.0.0
    git commit -q --allow-empty -m "feat: ✨ dark mode"
    git push -q
    run gcp release -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"v1.0.0 → v1.1.0"* ]]
    git --git-dir="$TMP/remote.git" rev-parse -q --verify refs/tags/v1.1.0
}

@test "release: fix bumps patch, breaking bumps major, dry run tags nothing" {
    main_setup
    git tag -a v1.2.3 -m v && git push -q origin v1.2.3
    git commit -q --allow-empty -m "fix: 🐛 crash"
    git push -q
    run gcp release -n
    [[ "$output" == *"→ v1.2.4"* ]]
    git commit -q --allow-empty -m "feat!: 💥 new api"
    git push -q
    run gcp release -n
    [[ "$output" == *"→ v2.0.0"* ]]
    run gcp release -n minor
    [[ "$output" == *"→ v1.3.0"* ]]
    [ -z "$(git tag -l 'v1.2.4' 'v2.0.0' 'v1.3.0')" ]
}

@test "release: refuses on a branch, with unpushed commits and without changes" {
    main_setup
    git tag -a v1.0.0 -m v && git push -q origin v1.0.0
    run gcp release -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"nothing to release"* ]]
    git commit -q --allow-empty -m "fix: 🐛 crash"
    run gcp release -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"unpushed"* ]]
    git switch -q -c feat/x
    run gcp release -y
    [ "$status" -eq 1 ]
    [[ "$output" == *"made from main"* ]]
}

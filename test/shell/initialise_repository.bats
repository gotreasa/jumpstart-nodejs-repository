#!/usr/bin/env bats

# Characterisation tests for initialise_repository.sh.
# External commands are stubbed as shell functions that record their
# arguments in $CALLS, so nothing touches GitHub, SonarCloud or brew.

load '../../node_modules/bats-support/load'
load '../../node_modules/bats-assert/load'

SCRIPT="${BATS_TEST_DIRNAME}/../../initialise_repository.sh"

setup() {
  CALLS="${BATS_TEST_TMPDIR}/calls"
  : > "$CALLS"
  cd "$BATS_TEST_TMPDIR"
  unset repository_name GIT_USER GIT_ORG SONAR_SECRET SNYK_SECRET
  # shellcheck source=../../initialise_repository.sh
  source "$SCRIPT"
}

record() {
  echo "$*" >> "$CALLS"
}

github_has() {
  # Stub curl so only the listed GitHub IDs return HTTP 200
  local known=" $* "
  eval 'curl() {
    local id="${@: -1}"
    id="${id#https://github.com/}"
    if [[ "'"$known"'" == *" $id "* ]]; then echo 200; else echo 404; fi
  }'
}

@test "sourcing the script defines functions without running main" {
  run bash -c 'source "$1"; echo sourced' _ "$SCRIPT"
  assert_success
  assert_output "sourced"
}

@test "load_config_from_file loads an existing configuration" {
  echo "GIT_USER=from-config" > .templateRepositoryConfig
  load_config_from_file > "${BATS_TEST_TMPDIR}/out"
  assert_equal "$GIT_USER" "from-config"
  run cat "${BATS_TEST_TMPDIR}/out"
  assert_output "✅    Loaded existing configuration"
}

@test "load_config_from_file falls back to interactive mode without a configuration" {
  run load_config_from_file
  assert_success
  assert_output "ℹ️    No configuration found, using interactive mode"
}

@test "install_package accepts a command that is already available" {
  run install_package "bash"
  assert_success
  assert_output "✅    All good with bash"
}

@test "install_package installs a missing command with brew on macOS" {
  uname() { echo "Darwin"; }
  brew() { record "brew $*"; }
  run install_package "not-a-real-command"
  assert_success
  assert_line "ℹ️    Installing not-a-real-command"
  assert_line "✅    not-a-real-command installed successfully"
  run cat "$CALLS"
  assert_output "brew install not-a-real-command"
}

@test "install_package stops when brew fails to install" {
  uname() { echo "Darwin"; }
  brew() { return 1; }
  run install_package "not-a-real-command"
  assert_failure 1
  assert_line "⛔️    There was an problem installing not-a-real-command"
}

@test "install_package stops when a command is missing outside macOS" {
  uname() { echo "Linux"; }
  run install_package "not-a-real-command"
  assert_failure 1
  assert_output "⛔️    not-a-real-command needs to be installed"
}

@test "install_nvm loads nvm from the default NVM_DIR" {
  export HOME="$BATS_TEST_TMPDIR"
  unset XDG_CONFIG_HOME
  mkdir -p "$HOME/.nvm"
  echo 'nvm() { :; }' > "$HOME/.nvm/nvm.sh"
  run install_nvm
  assert_success
  assert_output "✅    All good with NVM"
}

@test "install_nvm uses XDG_CONFIG_HOME when it is set" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/xdg"
  mkdir -p "$XDG_CONFIG_HOME/nvm"
  echo 'nvm() { :; }' > "$XDG_CONFIG_HOME/nvm/nvm.sh"
  run install_nvm
  assert_success
  assert_output "✅    All good with NVM"
}

@test "install_nvm stops when nvm is not installed" {
  export HOME="$BATS_TEST_TMPDIR"
  unset XDG_CONFIG_HOME
  run install_nvm
  assert_failure 1
  assert_output "⛔️    NVM needs to be installed"
}

@test "get_repository_name asks again until a name is given" {
  get_repository_name <<< $'\n\nmy-repo' > "${BATS_TEST_TMPDIR}/out"
  assert_equal "$repository_name" "my-repo"
  run grep -c "What is the name of the repository you need?" "${BATS_TEST_TMPDIR}/out"
  assert_output "3"
}

@test "get_git_user_name asks again until the ID exists on GitHub" {
  github_has "real-user"
  get_git_user_name <<< $'ghost\nreal-user' > "${BATS_TEST_TMPDIR}/out"
  assert_equal "$GIT_USER" "real-user"
  run cat "${BATS_TEST_TMPDIR}/out"
  assert_line "⛔️    That ID was not found at https://github.com/ghost"
  assert_line "✅    Your ID was found at https://github.com/real-user"
}

@test "get_git_organisation defaults to the GitHub ID" {
  github_has "me"
  GIT_USER="me"
  get_git_organisation <<< $'\n' > /dev/null
  assert_equal "$GIT_ORG" "me"
}

@test "get_git_organisation asks again until the organisation exists on GitHub" {
  github_has "me" "my-org"
  GIT_USER="me"
  get_git_organisation <<< $'bad-org\nmy-org' > "${BATS_TEST_TMPDIR}/out"
  assert_equal "$GIT_ORG" "my-org"
  run cat "${BATS_TEST_TMPDIR}/out"
  assert_line "⛔️    That Organisation was not found at https://github.com/bad-org"
  assert_line "✅    Your Organisation was found at https://github.com/my-org"
}

git_with_main_after_one_fetch() {
  git() {
    case "$1" in
      branch)
        if grep -q "git fetch origin" "$CALLS"; then
          echo "  remotes/origin/main"
        fi
        ;;
      *) record "git $*" ;;
    esac
  }
}

@test "clone_template_repository creates a personal repository and checks out main" {
  gh() { record "gh $*"; }
  git_with_main_after_one_fetch
  mkdir my-repo
  GIT_USER="me" GIT_ORG="me" repository_name="my-repo"
  clone_template_repository > /dev/null
  assert_equal "$(basename "$PWD")" "my-repo"
  run cat "$CALLS"
  assert_output - << 'EOF'
gh repo create my-repo --public --confirm --template=gotreasa/templateRepository
git fetch origin
git checkout main
EOF
}

@test "clone_template_repository creates the repository under the organisation" {
  gh() { record "gh $*"; }
  git_with_main_after_one_fetch
  mkdir my-repo
  GIT_USER="me" GIT_ORG="my-org" repository_name="my-repo"
  clone_template_repository > /dev/null
  run head -1 "$CALLS"
  assert_output "gh repo create my-org/my-repo --public --confirm --template=gotreasa/templateRepository"
}

@test "install_latest_node_and_npm_packages pins the LTS node and updates packages" {
  nvm() {
    if [[ "$1" == "version" ]]; then echo "v22.23.3"; else record "nvm $*"; fi
  }
  npm() { record "npm $*"; }
  npx() { record "npx $*"; }
  echo '{ "engines": { "node": "v1.0.0" } }' > package.json
  install_latest_node_and_npm_packages > /dev/null
  assert_equal "$(cat .nvmrc)" "v22.23.3"
  assert_equal "$(cat package.json)" '{ "engines": { "node": "v22.23.3" } }'
  run cat "$CALLS"
  assert_output - << 'EOF'
nvm install --lts
npm i --ignore-scripts
npx --ignore-scripts npm-check-updates -u
npm i --ignore-scripts
EOF
}

@test "update_repository_files points package.json and the workflow at the new repository" {
  mkdir -p .github/workflows
  echo '"url": "gotreasa/templateRepository"' > package.json
  echo 'node-version: [14.15.1]' > .github/workflows/node.js.yml
  GIT_ORG="acme" repository_name="widget" node_version="v22.23.3"
  update_repository_files
  assert_equal "$(cat package.json)" '"url": "acme/widget"'
  assert_equal "$(cat .github/workflows/node.js.yml)" 'node-version: [v22.23.3]'
}

@test "sed_in_place reports failure when sed cannot edit the file" {
  run sed_in_place 's/a/b/' missing-file
  assert_failure 1
}

@test "update_repository_files leaves no sed backup files to be committed" {
  mkdir -p .github/workflows
  echo '"url": "gotreasa/templateRepository"' > package.json
  echo 'node-version: [14.15.1]' > .github/workflows/node.js.yml
  GIT_ORG="acme" repository_name="widget" node_version="v22.23.3"
  update_repository_files
  run find . -name '*.bak'
  assert_output ""
}

@test "setup_sonar rewrites the Sonar settings, stores the token and creates the project" {
  gh() { record "gh $*"; }
  curl() { record "curl $*"; }
  cat > sonar-project.properties << 'EOF'
sonar.organization=gotreasa
sonar.projectKey=gotreasa_templateRepository
sonar.links.scm=https://github.com/gotreasa/templateRepository
EOF
  cat > README.md << 'EOF'
https://sonarcloud.io/dashboard?id=gotreasa_templateRepository
https://sonarcloud.io/api/project_badges/measure?project=gotreasa_templateRepository
EOF
  GIT_USER="me" GIT_ORG="acme" repository_name="widget"
  SONAR_SECRET="fake-sonar-token" # pragma: allowlist secret
  setup_sonar > /dev/null
  run cat sonar-project.properties
  assert_output - << 'EOF'
sonar.organization=me
sonar.projectKey=me_acme_widget
sonar.links.scm=https://github.com/acme/widget
EOF
  run cat README.md
  assert_output - << 'EOF'
https://sonarcloud.io/dashboard?id=me_acme_widget
https://sonarcloud.io/api/project_badges/measure?project=me_acme_widget
EOF
  run cat "$CALLS"
  assert_line "gh secret set SONAR_TOKEN -b fake-sonar-token"
  assert_line --partial "-u fake-sonar-token: -d project=me_acme_widget&organization=me&name=acme_widget https://sonarcloud.io/api/projects/create"
}

@test "setup_sonar asks for the API key when none is configured" {
  gh() { record "gh $*"; }
  curl() { :; }
  touch sonar-project.properties README.md
  GIT_USER="me" GIT_ORG="acme" repository_name="widget"
  setup_sonar <<< $'\nentered-token' > /dev/null
  run grep "SONAR_TOKEN" "$CALLS"
  assert_output "gh secret set SONAR_TOKEN -b entered-token"
}

@test "setup_snyk rewrites the Snyk badge and stores the token" {
  gh() { record "gh $*"; }
  cat > README.md << 'EOF'
https://snyk.io/test/github/gotreasa/templateRepository/badge.svg
https://snyk.io/test/github/gotreasa/templateRepository
EOF
  GIT_ORG="acme" repository_name="widget"
  setup_snyk <<< $'\nentered-snyk-token' > /dev/null
  run cat README.md
  assert_output - << 'EOF'
https://snyk.io/test/github/acme/widget/badge.svg
https://snyk.io/test/github/acme/widget
EOF
  run cat "$CALLS"
  assert_output "gh secret set SNYK_TOKEN -b entered-snyk-token"
}

@test "save_config_to_file writes the answers next to the new repository" {
  mkdir widget && cd widget
  GIT_USER="me" GIT_ORG="acme"
  SONAR_SECRET="fake-sonar" SNYK_SECRET="fake-snyk" # pragma: allowlist secret
  save_config_to_file > /dev/null
  run cat ../.templateRepositoryConfig
  assert_output - << 'EOF'
GIT_USER=me
GIT_ORG=acme
SONAR_SECRET=fake-sonar
SNYK_SECRET=fake-snyk
EOF
}

@test "commit_code_to_git commits everything and pushes main" {
  git() { record "git $*"; }
  commit_code_to_git > /dev/null
  run cat "$CALLS"
  assert_output - << 'EOF'
git add .
git commit -m feat: setup of the repository
git push origin main
EOF
}

@test "print_success_message names the repository" {
  repository_name="widget"
  run print_success_message
  assert_output "ℹ️    Repository setup for widget is now complete"
}

#!/usr/bin/env bats

# End-to-end tests of initialiseRepository.sh's main(), with every external
# command (gh, git, curl, brew, npm, npx, nvm) replaced by a stub on PATH that
# records its arguments. No repository is created, no secret is set, nothing
# is pushed.
#
# main() runs in-process (sourced, then `run main`) so kcov can trace it: a
# child bash started by exec does not report to kcov's trace pipe. One test
# still executes the script as a program to prove the entry point calls main.

load '../../node_modules/bats-support/load'
load '../../node_modules/bats-assert/load'

SCRIPT="${BATS_TEST_DIRNAME}/../../initialiseRepository.sh"

stub() {
  local name="$1"
  local body="$2"
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "${BIN}/${name}"
  chmod +x "${BIN}/${name}"
}

setup() {
  export CALLS="${BATS_TEST_TMPDIR}/calls"
  : > "$CALLS"
  BIN="${BATS_TEST_TMPDIR}/bin"
  WORK="${BATS_TEST_TMPDIR}/work"
  mkdir -p "$BIN" "$WORK"
  cp -R "${BATS_TEST_DIRNAME}/fixtures/templateRepository" "${BATS_TEST_TMPDIR}/template"

  # gh: "repo create" stands in for cloning the template locally
  stub gh '
echo "gh $*" >> "$CALLS"
if [[ "$1 $2" == "repo create" ]]; then
  cp -R "'"${BATS_TEST_TMPDIR}/template"'" "${3##*/}"
fi'
  # git: report origin/main as soon as asked, record everything else
  stub git '
if [[ "$1" == "branch" ]]; then echo "  remotes/origin/main"; exit 0; fi
echo "git $*" >> "$CALLS"'
  # curl: every GitHub ID exists; record the other calls
  stub curl '
for arg in "$@"; do
  if [[ "$arg" == "%{http_code}" ]]; then echo 200; exit 0; fi
done
echo "curl $*" >> "$CALLS"'
  stub brew 'echo "brew $*" >> "$CALLS"'
  stub npm 'echo "npm $*" >> "$CALLS"'
  stub npx 'echo "npx $*" >> "$CALLS"'

  export HOME="${BATS_TEST_TMPDIR}/home"
  unset XDG_CONFIG_HOME
  mkdir -p "$HOME/.nvm"
  cat > "$HOME/.nvm/nvm.sh" << 'EOF'
nvm() {
  if [[ "$1" == "version" ]]; then echo "v22.23.3"; else echo "nvm $*" >> "$CALLS"; fi
}
EOF
  export PATH="${BIN}:${PATH}"
  cd "$WORK"
  unset repositoryName GIT_USER GIT_ORG SONAR_SECRET SNYK_SECRET
  # shellcheck source=../../initialiseRepository.sh
  source "$SCRIPT"
}

answers() {
  # repository name, GitHub ID, organisation, Sonar key, Snyk key
  printf '%s\n' "my-repo" "me" "my-org" "fake-sonar" "fake-snyk" # pragma: allowlist secret
}

@test "executing the script runs main end to end" {
  run "$SCRIPT" < <(answers)
  assert_success
  assert_output --partial "✅    Your Organisation was found at https://github.com/my-org"
  assert_output --partial "ℹ️    Repository setup for my-repo is now complete"
}

@test "main calls the external tools in order" {
  run main < <(answers)
  assert_success
  assert_line "ℹ️    Repository setup for my-repo is now complete"
  run cat "$CALLS"
  assert_output - << 'EOF'
gh repo create my-org/my-repo --public --confirm --template=gotreasa/templateRepository
git checkout main
nvm install --lts
npm i --ignore-scripts
npx --ignore-scripts npm-check-updates -u
npm i --ignore-scripts
gh secret set SONAR_TOKEN -b fake-sonar
curl --include --request POST --header Content-Type: application/x-www-form-urlencoded -u fake-sonar: -d project=me_my-org_my-repo&organization=me&name=my-org_my-repo https://sonarcloud.io/api/projects/create
gh secret set SNYK_TOKEN -b fake-snyk
git add .
git commit -m feat: setup of the repository
git push origin main
EOF
}

@test "main rewrites the cloned template for the new repository" {
  run main < <(answers)
  assert_success
  cd my-repo
  assert_equal "$(cat .nvmrc)" "v22.23.3"
  run cat package.json
  assert_output - << 'EOF'
{
  "name": "my-repo",
  "homepage": "https://github.com/my-org/my-repo#readme",
  "repository": {
    "url": "git+https://github.com/my-org/my-repo.git"
  },
  "main": "src/my-repo.js",
  "engines": {
    "node": "v22.23.3"
  }
}
EOF
  run cat sonar-project.properties
  assert_output - << 'EOF'
sonar.links.scm=https://github.com/my-org/my-repo
sonar.organization=me
sonar.projectKey=me_my-org_my-repo
EOF
  run cat README.md
  assert_output - << 'EOF'
[![Sonarcloud Status](https://sonarcloud.io/api/project_badges/measure?project=me_my-org_my-repo&metric=alert_status)](https://sonarcloud.io/dashboard?id=me_my-org_my-repo)
[![Known Vulnerabilities](https://snyk.io/test/github/my-org/my-repo/badge.svg)](https://snyk.io/test/github/my-org/my-repo)
EOF
  run find . -name '*.bak'
  assert_output ""
}

@test "main saves the answers for the next run" {
  run main < <(answers)
  assert_success
  run cat .templateRepositoryConfig
  assert_output - << 'EOF'
GIT_USER=me
GIT_ORG=my-org
SONAR_SECRET=fake-sonar
SNYK_SECRET=fake-snyk
EOF
}

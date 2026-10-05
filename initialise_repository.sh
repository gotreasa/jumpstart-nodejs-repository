#!/bin/bash

# In-place sed for both BSD (macOS) and GNU (Linux), leaving no backup behind
function sed_in_place() {
  local expression="$1"
  local file="$2"
  if ! sed -i.bak "$expression" "$file"; then
    return 1
  fi
  rm -f "$file.bak"
  return 0
}

function load_config_from_file() {
  if [[ -f .templateRepositoryConfig ]]; then
    . .templateRepositoryConfig
    echo "✅    Loaded existing configuration"
  else
    echo "ℹ️    No configuration found, using interactive mode"
  fi
  return 0
}

function install_package() {
  local package_name="$1"
  set +e
  if ! [[ -x "$(command -v "$package_name")" ]]; then
    if [[ $(uname) == "Darwin" ]]; then
      echo "ℹ️    Installing $package_name"
      if ! brew install "$package_name"; then
        echo "⛔️    There was an problem installing $package_name"
        exit 1
      else
        echo "✅    $package_name installed successfully"
      fi
    else
      echo "⛔️    $package_name needs to be installed"
      exit 1
    fi
  else
    echo "✅    All good with $package_name"
  fi
  set -e
  return 0
}

function install_nvm() {
  set +e
  # Setup the NVM path
  export NVM_DIR="$([[ -z "${XDG_CONFIG_HOME-}" ]] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
  [[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh" # This loads nvm
  # Check if NVM is installed
  if [[ -z "$(command -v nvm)" ]]; then
    echo "⛔️    NVM needs to be installed"
    exit 1
  else
    echo "✅    All good with NVM"
  fi
  set -e
  return 0
}

function get_repository_name() {
  while [[ -z "$repository_name" ]]; do
    echo -e "\n\n🙋‍♀️    What is the name of the repository you need?"
    read repository_name
  done
  return 0
}

function get_git_user_name() {
  while [[ -z "$GIT_USER" ]]; do
    echo "🙋‍♀️    What is your GitHub ID?"
    read GIT_USER
    if [[ $(curl -s -o /dev/null -w "%{http_code}" https://github.com/$GIT_USER) != 200 ]]; then
      echo "⛔️    That ID was not found at https://github.com/$GIT_USER"
      unset GIT_USER
    else
      echo "✅    Your ID was found at https://github.com/$GIT_USER"
    fi
  done
  return 0
}

function get_git_organisation() {
  while [[ -z "$GIT_ORG" ]]; do
    echo "🙋‍♀️    What is your GitHub Org?  If not using an Organisation, press enter to default to $GIT_USER"
    read GIT_ORG
    if [[ -z "$GIT_ORG" ]]; then
      GIT_ORG=$GIT_USER
    fi
    if [[ $(curl -s -o /dev/null -w "%{http_code}" https://github.com/$GIT_ORG) != 200 ]]; then
      echo "⛔️    That Organisation was not found at https://github.com/$GIT_ORG"
      unset GIT_ORG
    else
      echo "✅    Your Organisation was found at https://github.com/$GIT_ORG"
    fi
  done
  return 0
}

function clone_template_repository() {
  echo "ℹ️    Creating the repository"
  if [[ $GIT_USER == $GIT_ORG ]]; then
    full_repository_name=${repository_name}
  else
    full_repository_name=$GIT_ORG/${repository_name}
  fi
  gh repo create $full_repository_name --public --confirm --template="gotreasa/templateRepository"
  cd $repository_name
  while [[ "$(git branch -a | grep remotes/origin/main)" != *"remotes/origin/main" ]]; do
    git fetch origin
  done
  git checkout main
  return 0
}

function install_latest_node_and_npm_packages() {
  # Setup NVM and Node version
  echo "ℹ️    Installing node"
  nvm install --lts
  node_version=$(nvm version)
  echo $node_version > .nvmrc
  sed_in_place 's/"node": ".*"/"node": "'${node_version}'"/g' package.json
  # Install and update NPM packages
  echo "ℹ️    Setting up the npm packages"
  npm i --ignore-scripts
  npx --ignore-scripts npm-check-updates -u
  npm i --ignore-scripts
  return 0
}

function update_repository_files() {
  sed_in_place 's/gotreasa/'${GIT_ORG}'/g' package.json
  sed_in_place 's/templateRepository/'${repository_name}'/g' package.json
  sed_in_place 's/node-version: \[14.15.1\]/node-version: \['${node_version}'\]/g' .github/workflows/node.js.yml
  return 0
}

function setup_sonar() {
  project_name=${GIT_ORG}_${repository_name}
  project_organisation=${GIT_USER}
  project_key=${project_organisation}_${project_name}
  echo "ℹ️    Updating sonar properties file"
  sed_in_place 's/sonar.organization=gotreasa/sonar.organization='${project_organisation}'/g' sonar-project.properties
  sed_in_place 's/sonar.projectKey=gotreasa_templateRepository/sonar.projectKey='${project_key}'/g' sonar-project.properties
  sed_in_place 's#sonar.links.scm=https://github.com/gotreasa/templateRepository#sonar.links.scm=https://github.com/'${GIT_ORG}'/'${repository_name}'#g' sonar-project.properties
  sed_in_place 's#https://sonarcloud.io/dashboard?id=gotreasa_templateRepository#https://sonarcloud.io/dashboard?id='${project_key}'#g' README.md
  sed_in_place 's#https://sonarcloud.io/api/project_badges/measure?project=gotreasa_templateRepository#https://sonarcloud.io/api/project_badges/measure?project='${project_key}'#g' README.md

  while [[ -z "$SONAR_SECRET" ]]; do
    echo -e "\n\nWhat is the sonar API key?"
    read -s SONAR_SECRET
  done
  gh secret set SONAR_TOKEN -b ${SONAR_SECRET}

  curl --include \
    --request POST \
    --header "Content-Type: application/x-www-form-urlencoded" \
    -u ${SONAR_SECRET}: \
    -d "project=${project_key}&organization=${project_organisation}&name=${project_name}" \
    'https://sonarcloud.io/api/projects/create'
  return 0
}

function setup_snyk() {
  while [[ -z "$SNYK_SECRET" ]]; do
    echo -e "\n\nWhat is the synk API key?"
    read -s SNYK_SECRET
  done
  sed_in_place 's#https://snyk.io/test/github/gotreasa/templateRepository/badge.svg#https://snyk.io/test/github/'${GIT_ORG}'/'${repository_name}'/badge.svg#g' README.md
  sed_in_place 's#https://snyk.io/test/github/gotreasa/templateRepository#https://snyk.io/test/github/'${GIT_ORG}'/'${repository_name}'#g' README.md
  gh secret set SNYK_TOKEN -b ${SNYK_SECRET}
  return 0
}

function save_config_to_file() {
  echo "ℹ️    Saving the configuration to file"
  cat > ../.templateRepositoryConfig << EOF
GIT_USER=${GIT_USER}
GIT_ORG=${GIT_ORG}
SONAR_SECRET=${SONAR_SECRET}
SNYK_SECRET=${SNYK_SECRET}
EOF
  return 0
}

function commit_code_to_git() {
  echo "ℹ️    Commit code to Git"
  git add .
  git commit -m "feat: setup of the repository"
  git push origin main
  return 0
}

function print_success_message() {
  echo "ℹ️    Repository setup for ${repository_name} is now complete"
  return 0
}

function main() {
  load_config_from_file
  install_package "git"
  install_package "gh"
  install_package "curl"
  install_nvm
  get_repository_name
  get_git_user_name
  get_git_organisation
  clone_template_repository
  install_latest_node_and_npm_packages
  update_repository_files
  setup_sonar
  setup_snyk
  save_config_to_file
  commit_code_to_git
  print_success_message
  return 0
}

# Run only when executed, so tests can source the functions
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

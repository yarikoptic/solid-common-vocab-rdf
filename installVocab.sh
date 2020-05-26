#!/bin/bash
# set -e to exit on error.
set -e
# set -u to error on unbound variable (use ${var:-} to check if 'var' is set.
set -u
set -o pipefail

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
NORMAL=$(tput sgr0)

# Get the directory this script itself is located in.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
STARTING_DIR="${PWD}"
DEFAULT_TARGET_DIR="src/ExternalVocab"
TARGET_DIR="${PWD}/${DEFAULT_TARGET_DIR}"
PROGRAMMING_LANGUAGE=JavaScript

source ${SCRIPT_DIR}/run_command.sh

VOCAB_LOCAL=false
VOCAB_REMOTE=false
VOCAB_INTERNAL_LOCATION=""

helpFunction() {
    echo ""
    printf "${YELLOW}Usage: $0 -r <RepositoryToClone> -m <VocabModule> [ -t <TargetDirectory> ] [ -p <ProgrammingLanguage> ] [ -l | -r ]\n"
    printf "Installs the provided vocabulary module locally (i.e. clones the module inside this project), or remotely (publishing any local changes).${NORMAL}\n"
    printf "${BLUE}Options:${NORMAL}\n"
    printf "\t-r ${BLUE}Repository to clone (e.g. git@github.com:inrupt/lit-vocab.git)${NORMAL}\n\n"
    printf "\t-m ${BLUE}Module to extract (may contain a bundle of vocabularies, e.g. @inrupt/lit-generated-vocab-common)${NORMAL}\n"
    printf "\t-i ${BLUE}Internal vocab location (e.g. inrupt-rdf-vocab/UIComponent)${NORMAL}\n"
    printf "\t-t ${BLUE}Optional: target directory (default is: [${DEFAULT_TARGET_DIR}])${NORMAL}\n"
    printf "\t-p ${BLUE}Optional: programming language (default is: [${PROGRAMMING_LANGUAGE}])${NORMAL}\n"
    printf "\t-l ${BLUE}Depend on module locally (e.g. to watch for local changes and apply them immediately)${NORMAL}\n"
    printf "\t-n ${BLUE}Depend on non-local module${NORMAL}\n\n"
    printf "${RED}Current working directory: [${PWD}]${NORMAL}\n"
    printf "${RED}Target directory: [${TARGET_DIR}]${NORMAL}\n"
    printf "${RED}Script directory: [${SCRIPT_DIR}]${NORMAL}\n"
}

while getopts ":r:m:i:t:p:ln" opt
do
    case "$opt" in
      r ) GIT_REPOSITORY_URL="$OPTARG" ;;
      m ) VOCAB_MODULE="$OPTARG" ;;
      i ) VOCAB_INTERNAL_LOCATION="$OPTARG" ;;
      t ) TARGET_DIRECTORY="$OPTARG" ;;
      p ) PROGRAMMING_LANGUAGE="$OPTARG" ;;
      l ) VOCAB_LOCAL=true ;;
      n ) VOCAB_REMOTE=true ;;
      ? ) helpFunction ;; # Print help in case parameter is non-existent
    esac
done


if [ "${1:-}" == "?" ] || [ "${1:-}" == "-h" ] || [ "${1:-}" == "--help" ]
then
    helpFunction
    exit 1 # Exit script after printing help.
fi

# Print help in case parameters are empty, but display everything.
if [ "${VOCAB_MODULE:-}" == "" ] || ( [ "${VOCAB_LOCAL}" == false ] && [ "${VOCAB_REMOTE}" == false ] )
then
    printf "${RED}You *MUST* provide a Vocab module, and state either local or remote.${NORMAL}\n"
    helpFunction
    exit 1 # Exit script after printing help.
fi

# Check if the module we want to install is mentioned in our 'package.json' file
# already (so we can uninstall what's there first before installing it fresh).
if grep "\"${VOCAB_MODULE}\": " ${PWD}/package.json > /dev/null 2>&1;
then
    printf "${GREEN}Found vocab module [$VOCAB_MODULE] in local 'package.json' file.${NORMAL}\n"
    printf "${GREEN}Uninstalling [${VOCAB_MODULE}] from this project...${NORMAL}\n"

    run_command "npm uninstall ${VOCAB_MODULE}"
else
    printf "${GREEN}Vocab module [$VOCAB_MODULE] not found in local 'package.json' file, so no need to uninstall it first.${NORMAL}\n"
fi

# If a local install, then we need to fetch the LAG, then clone the repository
# containing the module we actually want, use the LAG to generate artifacts
# locally, and then NPM install the actual module we want referencing the
# locally generated copy.
if [ ${VOCAB_LOCAL} == true ]
then
    printf "\n${GREEN}Fetching LIT Artifact Generator into directory [${TARGET_DIR}]...${NORMAL}\n"
    run_command "${SCRIPT_DIR}/fetchLag.sh -t ${TARGET_DIR}"

    printf "\n${GREEN}Fetching vocabulary repository [${GIT_REPOSITORY_URL}] into directory [${TARGET_DIR}]...${NORMAL}\n"
    run_command "${SCRIPT_DIR}/fetchVocabRepo.sh -r ${GIT_REPOSITORY_URL} -t ${TARGET_DIR}"


    REPO_DIR="$(echo ${GIT_REPOSITORY_URL} | sed 's/^.*\///' | sed 's/\..*$//')"
    FULL_REPO_DIR="${TARGET_DIR}/${REPO_DIR}"
    GENERATED_DIR="${FULL_REPO_DIR}/Generated"

    # Currently we use a glob pattern to generate from every YAML file found
    # recursively under the root directory of the GIT repository we cloned from.
    # Therefore all our generated source-code also lives in sub-directories
    # under a common root directory.
    # If we wanted our source-code generated in s sub-directory alongside each
    # YAML file we find, we'd have to update the LAG first.
    printf "\n${GREEN}Generating source-code artifacts from Git repo [${REPO_DIR}] in directory [${FULL_REPO_DIR}] into [${GENERATED_DIR}]...${NORMAL}\n"
    # If the LAG is globally installed, you can just use this:
#    lit-artifact-generator/index.js \

    # If the LAG is locally installed, you can just use this:
#    node /home/pmcb55/Work/Projects/LIT/lit-artifact-generator/index.js \

    # If the LAG was cloned locally, you can just use this:
    node ${TARGET_DIR}/lit-artifact-generator/index.js \
      generate \
      --outputDirectory "${GENERATED_DIR}" \
      --vocabListFile "${FULL_REPO_DIR}/**/*.yml" \
      --vocabListFileIgnore "${FULL_REPO_DIR}/lit-artifact-generator/**" \
      --noprompt
#      --force # Don't force generation of all for just one vocab install!


    # Unfortunately, the VOCAB_MODULE (e.g. @inrupt/lit-generated-vocab-ui-component)
    # tells us nothing about the structure within the vocab repo itself...
#    VOCAB_MODULE_DIRECTORY="$(echo $VOCAB_MODULE | sed 's/@//g' | sed 's/\//-/g')"
#    printf "\n\n\n${RED}VOCAB_MODULE_DIRECTORY is [${VOCAB_MODULE_DIRECTORY}]...${NORMAL}\n\n\n"


    FULL_LOCAL_VOCAB=${GENERATED_DIR}/${VOCAB_INTERNAL_LOCATION}/Generated/SourceCodeArtifacts/${PROGRAMMING_LANGUAGE}
    INSTALL=${VOCAB_MODULE}@file://${FULL_LOCAL_VOCAB}
    printf "\n${GREEN}Installing LOCAL dependency as [${INSTALL}]...${NORMAL}\n"
    run_command "npm install ${INSTALL}"

    # We watch all YAMLs under a given root, and update the generated code
    # in our target directory accordingly.
    printf "\n${GREEN}Watching vocabulary bundles within directory [${TARGET_DIR}]...${NORMAL}\n"
#    run_command "${SCRIPT_DIR}/watchAll.sh -t ${FULL_LOCAL_VOCAB}"

    node ${TARGET_DIR}/lit-artifact-generator/index.js \
      watch \
      --vocabListFile /home/pmcb55/Work/Projects/LIT/lit-vocab/inrupt-rdf-vocab/UiComponent/Vocab-List-Inrupt-UiComponent.yml \
      --TARGET_DIR ${TARGET_DIR}/inrupt-lit-generated-vocab-ui-component


else
    INSTALL=${VOCAB_MODULE}
    printf "\n${GREEN}Installing REMOTE dependency as [${INSTALL}]...${NORMAL}\n"
    run_command "npm install ${INSTALL}"
fi

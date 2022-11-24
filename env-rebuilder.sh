#!/bin/bash
#-----------------------------------------------------------------------------------------------------------------------------------
# env-rebuilder is a CLI to create conda environments from existing yaml files using either 'mamba' or 'conda'.
#
# copyright @Dr. Dominik Straßel, 2022
# license: AGPLv3
#-----------------------------------------------------------------------------------------------------------------------------------


#bash set buildins -----------------------------------------------------------------------------------------------------------------
set -e
set -o pipefail
#-----------------------------------------------------------------------------------------------------------------------------------


# functions ------------------------------------------------------------------------------------------------------------------------
function die () {
  # define function die that is called if a command fails
  echo "ERROR: ${1}"
  exit 200
}


function currenttime () {
  # define function to print time and date
  date +"[%F %T]"
}


function log () {
  # define log function
  echo " $(currenttime): ${1}"
}


function get_variable () {
# get_variable function
# USAGE: get_variable CARME_VARIABLE

  local CONFIG_FILE="/opt/env-rebuilder/env-rebuilder.conf"
  local variable_value

  if [[ ! -f "${CONFIG_FILE}" ]];then
    echo "ERROR: no config-file ('${CONFIG_FILE}') not found"
    exit 200
  fi

  check_command grep

  variable_value=$(grep --color=never -Po "^${1}=\K.*" "${CONFIG_FILE}")
  variable_value=$(echo "${variable_value}" | tr -d '"')
  echo "${variable_value}"

}
#-----------------------------------------------------------------------------------------------------------------------------------


# variables ------------------------------------------------------------------------------------------------------------------------
# adjustible variables
ENV_FILES_ROOT=$(get_variable ENV_FILES_ROOT)
PACKAGE_MANAGER_ROOT=$(get_variable PACKAGE_MANAGER_ROOT)
ENV_JOB_DIR=$(get_variable ENV_JOB_DIR)
PACKAGE_MANAGER=$(get_variable PACKAGE_MANAGER)

[[ -z ${ENV_FILES_ROOT} ]] && die "ENV_FILES_ROOT not set"
[[ -z ${PACKAGE_MANAGER_ROOT} ]] && die "PACKAGE_MANAGER_ROOT not set"
[[ -z ${ENV_JOB_DIR} ]] && die "ENV_JOB_DIR not set"
[[ -z ${PACKAGE_MANAGER} ]] && die "PACKAGE_MANAGER not set"


# fixed variables
INSTALL_ROOT="/opt/env-rebuilder"
CLI_VERSION="v1.0 (03/2022)"
AUTHOR="Dr. Dominik Straßel"
LICENSE="AGPLv3"
#-----------------------------------------------------------------------------------------------------------------------------------


# check if conda env dir exists ----------------------------------------------------------------------------------------------------
[[ ! -d "${ENV_FILES_ROOT}" ]] && die "${ENV_FILES_ROOT} does not exist"
#-----------------------------------------------------------------------------------------------------------------------------------


# define functions -----------------------------------------------------------------------------------------------------------------
function print_help (){
  echo "'env-rebuilder' is a CLI to create conda environments from existing yaml files

Version: ${CLI_VERSION}
Author:  ${AUTHOR}
License: ${LICENSE}

Usage: env-rebuilder [arguments]

Arguments:
  --list                                        print all available env files
  --inspect                                     see the content of a specific env file

  --filter SEARCH_STRING                        add a search string for possible env files

  --local FULL_PATH_TO_YAML_FILES               define another folder to check for env files

  --create ENV_NAME                             create a new environment with the name 'ENV_NAME'
  --ssd                                         create the environment on the local SSD in '/home/SSD/conda/ENV_NAME'
                                                NOTE: this environment is only accessable inside the job you are now
                                                      and will be deleted the moment the job ends

  -h or --help                                  print this help and exit
  --version                                     print the version and exit
"
  exit 0
}


function print_arglist () {
# define argument list for bash completion

  arg_list=( "-h" "--help" "--version" "--list" "--inspect" "--filter" "--local" "--create" "--create-and-activate" "--ssd")
  echo "${arg_list[@]}"

  return 0
}


function print_version () {
# print the version

  echo "env-rebuilder ${CLI_VERSION}"

  return 0
}


function print_license () {
# print the version

  less "${INSTALL_ROOT}/LICENSE"

  return 0
}


function load_conda_init_file () {
# source the conda init file

  local CONDA_INIT_FILE="${PACKAGE_MANAGER_ROOT}/etc/profile.d/conda.sh"
  local MAMBA_INIT_FILE="${PACKAGE_MANAGER_ROOT}/etc/profile.d/mamba.sh"

  if [[ -f "${CONDA_INIT_FILE}" ]];then
    source "${CONDA_INIT_FILE}"
  else
    die "cannot find conda init file '${CONDA_INIT_FILE}'"
  fi

  if [[ "${PACKAGE_MANAGER}" == "mamba" ]];then
    if [[ -f "${MAMBA_INIT_FILE}" ]];then
    source "${MAMBA_INIT_FILE}"
    else
      die "cannot find mamba init file '${MAMBA_INIT_FILE}'"
    fi
  fi

  return 0
}


function initiate_env_files_list () {
# find all conda env files located in 'ENV_FILES_ROOT' and apply if specified the search filter 'ENV_FILE_SEARCH_FILTER'

  local ENV_FILE_FILTER

  if [[ -n ${ENV_FILE_SEARCH_FILTER} ]];then
    ENV_FILE_FILTER="*${ENV_FILE_SEARCH_FILTER}*.y*ml"
  else
    ENV_FILE_FILTER="*.y*ml"
  fi

  mapfile -t ENV_FILES_LIST < <(find "${ENV_FILES_ROOT}" -maxdepth 1 -name "${ENV_FILE_FILTER}" -printf '%f\n')

  return 0
}


function list_env_files () {
# list all conda env files located in 'ENV_FILES_ROOT' taking 'ENV_FILE_SEARCH_FILTER' into account

  local COUNTER

  if [[ "${#ENV_FILES_LIST[@]}" == "0" ]];then
    die "did not find any env file with the search filter '${ENV_FILE_SEARCH_FILTER}'"
  else
    echo ""
    echo " available conda environment files"
    COUNTER=1
    for ENV_FILES in "${ENV_FILES_LIST[@]}";do
      echo " ${COUNTER} - ${ENV_FILES}"
      ((COUNTER++))
    done
  fi

  return 0
}


function inspect_env_file () {
# inspect a specific environment file using 'less'

  local INDEX

  INDEX=${1}
  ((INDEX--))
  less "${ENV_FILES_ROOT}/${ENV_FILES_LIST[${INDEX}]}"

  return 0
}


function create_env_in_home () {
# create a new conda environment using the environment file 'ENV_FILES_ROOT/ENV_FILE' and giving it a new name 'ENV_NAME'

  local INDEX="${1}"
  local ENV_FILE
  local ENV_NAME="${2}"
  local LOCAL_ENVS

  ((INDEX--))
  ENV_FILE="${ENV_FILES_LIST[${INDEX}]}"

  mapfile -t LOCAL_ENVS < <("${PACKAGE_MANAGER}" env list | grep "${HOME}" | awk '{print $1}')

  if [[ "${LOCAL_ENVS[*]}" =~ (^|[[:space:]])"${ENV_NAME}"($|[[:space:]]) ]];then
    log "environment '${ENV_NAME}' already exists"
  else
    echo ""
    log "create environment '${ENV_NAME}' using ${ENV_FILE}"
    cp "${ENV_FILES_ROOT}/${ENV_FILE}" "/tmp/${ENV_FILE}"
    "${PACKAGE_MANAGER}" env create --name "${ENV_NAME}" -f "/tmp/${ENV_FILE}"
    rm "/tmp/${ENV_FILE}"
    log "created environment '${ENV_NAME}' successfully"
    echo ""
  fi

  return 0
}


function create_env_on_ssd () {
# create a new conda environment using the environment file 'ENV_FILES_ROOT/ENV_FILE', giving it a new name 'ENV_NAME' and store it
# on the local SSD
# (this env is deleted the moment the job ends)

  local INDEX="${1}"
  local ENV_FILE
  local ENV_NAME="${2}"
  local ENV="${ENV_JOB_DIR}/${ENV_NAME}"

  ((INDEX--))
  ENV_FILE="${ENV_FILES_LIST[${INDEX}]}"

  if [[ ! -d "${ENV}" ]];then
    echo ""
    log "create conda env '${ENV}' from ${ENV_FILE}"
    cp "${ENV_FILES_ROOT}/${ENV_FILE}" "/tmp/${ENV_FILE}"
    "${PACKAGE_MANAGER}" env create --prefix "${ENV}" -f "/tmp/${ENV_FILE}"
    rm "/tmp/${ENV_FILE}"
    log "created environment '${ENV}' successfully"
    log "NOTE: this env is only accessable in this job and well be deleted the moment the job ends!"
    echo ""
  else
    log "environment '${ENV}' already exists"
  fi

  return 0
}
#-----------------------------------------------------------------------------------------------------------------------------------


# main -----------------------------------------------------------------------------------------------------------------------------
if [[ ${#} -eq 0 ]];then

  print_help

else

  while [[ ${#} -gt 0 ]];do
    KEY="${1}"
    case ${KEY} in
      -h|--help)
        print_help
        shift
      ;;
      --filter)
        shift
        ENV_FILE_SEARCH_FILTER=${1}
        shift
      ;;
      --list)
        PRINT_ENV_LIST="true"
        shift
        ;;
      --inspect)
        INSPECT_ENV_LIST="true"
        shift
      ;;
      --local)
        shift
        ENV_FILES_ROOT="${1}"
        [[ -z "${ENV_FILES_ROOT}" ]] && die "you have to specifiy the name (full path) of the folder holding your environment files"
        [[ ! -d "${ENV_FILES_ROOT}" ]] && die "${ENV_FILES_ROOT} does not exist"
        shift
      ;;
      --create)
        shift
        CREATE_ENV="true"
        NEW_ENV_NAME="${1}"
        [[ -z "${NEW_ENV_NAME}" ]] && die "you have to specifiy the name of the new env to create"
        shift
      ;;
      --ssd)
        shift
        USE_SSD="true"
      ;;
      #--mamba)
      #  shift
      #  USE_MAMBA="true"
      #;;
      --version)
        print_version
        shift
      ;;
      arglist)
        print_arglist
        shift
      ;;
      *)
        print_help
        shift
      ;;
    esac
  done


  # load conda init file (to be sure that conda works as expected)
  load_conda_init_file


  # initiate the list of all env files
  initiate_env_files_list


  # inspect env file
  if [[ "${PRINT_ENV_LIST}" == "true" ]];then
    list_env_files
    echo ""
  fi

  # inspect env file
  if [[ "${INSPECT_ENV_LIST}" == "true" ]];then
    list_env_files
    echo ""

    read -rp " specify number of env file to inspect: " ENV_NUMBER
    if [[ "${ENV_NUMBER}" == ?(-)+([0-9]) ]]; then
      inspect_env_file "${ENV_NUMBER}"
    fi

    LOOP_RUN="true"
    while [[ ${LOOP_RUN} == "true" ]];do
      echo ""
      read -rp " inspect another file? [y|N] " RESP
      if [[ "${RESP}" == "y" ]];then
        read -rp " specify number of env file to inspect: " ENV_NUMBER
        if [[ "${ENV_NUMBER}" == ?(-)+([0-9]) ]]; then
          inspect_env_file "${ENV_NUMBER}"
        fi
      else
        LOOP_RUN="false"
      fi
    done
  fi


  # create new environment
  if [[ "${CREATE_ENV}" == "true" ]];then
    list_env_files
    echo ""

    read -rp " specify number of env file to use: " ENV_NUMBER
    if [[ "${ENV_NUMBER}" == ?(-)+([0-9]) ]]; then
      if [[ "${USE_SSD}" == "true" ]];then
        create_env_on_ssd "${ENV_NUMBER}" "${NEW_ENV_NAME}"
      else
        create_env_in_home "${ENV_NUMBER}" "${NEW_ENV_NAME}"
      fi
    fi
  fi

fi
#-----------------------------------------------------------------------------------------------------------------------------------

exit 0

#-----------------------------------------------------------------------------------------------------------------------------------
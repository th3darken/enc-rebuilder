#!/usr/bin/env bash
#-----------------------------------------------------------------------------------------------------------------------------------
# bash completion file for env-rebuilder
#-----------------------------------------------------------------------------------------------------------------------------------

_env_rebuilder_commands () {
  local opts
  local cur

  opts=$(env-rebuilder arglist)

  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )

  return 0
}

complete -o nospace -F _env_rebuilder_commands env-rebuilder

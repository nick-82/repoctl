#!/bin/sh

CONF="./repoctl.conf"
SCRIPT_NAME="${0##*/}"
VERSION=0.03

##########################################RETURN CODE##########################################
SUCCESS=0
ERROR=65
MISSING_OPT_ARG=66
UNKNOWN_OPTION=67
NOT_FOUND=75
NOT_EXIST=110
IS_EMPTY=111
IS_EXIST=112
ERROR_FILE_MODE=113
DOWNLOAD_FAILED=80
NO_EXEC_PROCESS=90
MANY_EXEC_PROCESSES=91
ERROR_CREATE=100
ERROR_REMOVE=101
MANY_PID_FILES=105
PID_FILE_NOT_FOUND=106
ERROR_CREATE_PID=107
##########################################/RETURN CODE#########################################

##########################################MESSAGES#############################################
MSG_NOT_FOUND='not found'
MSG_MISSING_OPT_ARG='Option requires an argument'
MSG_UTILITY_NOT_FOUND='utility not found'
MSG_FILE_NOT_FOUND='file not found'
MSG_DOWNLOAD_FAILED='download failed'
MSG_NO_EXEC_PROCESS='no exec process'
MSG_MANY_EXEC_PROCESSES='many exec processes'
MSG_ERROR_CREATE_PID='error create PID file'
MSG_ERROR_CREATE_PID='error remove PID file'
MSG_PID_FILE_NOT_FOUND='PID file not found'
MSG_MANY_PID_FILES='many PID files'
MSG_REPO_VERSION_NOT_EXIST='repo version not exist'
MSG_REPO_VERSION_IS_EMPTY='repo version is empty'
MSG_REPO_ARCH_NOT_EXIST='repo arch not exist'
MSG_REPO_ARCH_IS_EMPTY='repo arch is empty'
MSG_REPO_BRANCH_NOT_EXIST='repo branch not exist'
MSG_REPO_BRANCH_IS_EMPTY='repo branch is empty'
MSG_REPO_ABI_NOT_EXIST='repo abi nor exist'
MSG_ERROR_REMOVE_REPO='error remove repo'
##########################################/MESSAGES############################################

##########################################USAGE MESSAGES#######################################
MSG_USAGE_MAIN=$(cat << EOF
    Shell script for upload FreeBSD repositories.

    Global options supported:
        -h             This message
        -v             Script version 
    Commands supported:
        init           Initialize local repo 
        remove         Remove local repo 
        info           Info local repo 
        remote-info    Remote repo info (Only PUBLIC MODE)
        list           List local repos 
        remote-list    Remote repos list (Only PUBLUC MODE)
        check          Check local repo packages
        remote-check   Diffs between local and remote repo packages (Only PUBLIC MODE)
        status         Script jobs status
        update         Update local repo from remote repo (Only PUBLIC MODE)
        push           Push repo diffs to private network
        pull           Pull repo diffs to private network
        log            History local repo diffs

    For more information on the different commands see repoctl.sh <command> -h.
EOF
)

MSG_USAGE_INIT=$(cat << EOF
    Command init (local empty repo initialize)
EOF
)

MSG_USAGE_REMOVE=$(cat << EOF
    Command remove (remove local repo)
EOF
)

MSG_USAGE_INFO=$(cat << EOF
    Command info (info local repo)
EOF
)

MSG_USAGE_REMOTE_INFO=$(cat << EOF
    Command remote-info (remote repo info (Only PUBLIC MODE))
EOF
)

MSG_USAGE_LIST=$(cat << EOF
     Command list (list local repos)
EOF
)

MSG_USAGE_REMOTE_LIST=$(cat << EOF
    Command remote-list (remote repos list (Only PUBLIC MODE))
EOF
)

MSG_USAGE_CHECK=$(cat << EOF
    Command check (check local repo packages)
EOF
)

MSG_USAGE_REMOTE_CHECK=$(cat << EOF
    Command remote-check (diffs between local and remote repo packages (Only PUBLIC MODE))
EOF
)

MSG_USAGE_STATUS=$(cat << EOF
    Command status (script jobs status)
EOF
)

MSG_USAGE_UPDATE=$(cat << EOF
    Command update (update local repo from remote repo (Only PUBLIC MODE))
EOF
)

MSG_USAGE_PUSH=$(cat << EOF
    Command push (push repo diffs to private network)
EOF
)

MSG_USAGE_PULL=$(cat << EOF
    Command pull (pull repo diffs to private network)
EOF
)

MSG_USAGE_LOG=$(cat << EOF
    Command log (history local repo diffs)
EOF
)
##########################################/USAGE MSGS######################################

# set meta files names
META_FILES=meta,meta.conf

# set packagesite files names
PACKAGESITE_FILES=packagesite.pkg,packagesite.txz,packagesite.tzst

# set data files names
DATA_FILES=data.pkg,data.txz,data.tzst

# set manifest file name
MANIFESTS=packagesite.yaml

# Download progress

##########################################USAGE########################################

# Usage messages
# $1 - command
usage() {
  [ "$#" -eq 0 ] && echo "$MSG_USAGE_MAIN"
  case "$1" in
    'main') echo "$MSG_USAGE_MAIN" ;;
    'init') echo "$MSG_USAGE_INIT";;
    'remove')echo "$MSG_USAGE_REMOVE" ;;
    'info') echo "$MSG_USAGE_INFO" ;;
    'remote-info') echo "$MSG_USAGE_REMOTE_INFO" ;;
    'list') echo "$MSG_USAGE_LIST" ;;
    'remote-list') echo "$MSG_USAGE_REMOTE_LIST" ;;
    'check') echo "$MSG_USAGE_CHECK" ;;
    'remote-check') echo "$MSG_USAGE_REMOTE_CHECK" ;;
    'status') echo "$MSG_USAGE_STATUS" ;;
    'update') echo "$MSG_USAGE_UPDATE" ;;
    'push') echo "$MSG_USAGE_PUSH" ;;
    'pull') echo "$MSG_USAGE_PULL" ;;
    'log') echo "$MSG_USAGE_LOG" ;;
    *) printf "Unknown command %s\n" "$1" && echo "$MSG_USAGE_MAIN" ;;
  esac
  exit "$SUCCESS"
}
##########################################/USAGE#######################################

##########################################SERVICE FUNCTIONS############################
# Error handler
# $1 - text
# $2 - code
error() {
  printf "Error: %s, code %s\n" "$1" "$2"
}

# Error and exit handler
# $1 - text
# $2 - code
exit_error() {
  error "$1" "$2" && exit "$2"
}

# Success handler
# $1 - text
success() {
  printf "Success: %s\n" "$1"
}

# Success and exit handler
# $1 - text
exit_success() {
  success "$1" && exit "$SUCCESS"
}

# Info handler
# $1 - text
info() {
  printf "Info: %s\n" "$1"
}

# Warning handler
# $1 - text
warn() {
  printf "Warning: %s\n" "$1"
}

# Load .conf file
load_conf() {
  if [ -f "$CONF" ]; then
    # shellcheck source=/dev/null
    . "$CONF"
  else
    exit_error "Conf file by path $CONF not found" 1
  fi
}

# Create timestamp
timestamp() {
  date '+%Y-%m-%d-%H-%M-%S'
}

# Process control
get_process() {
  pgrep -f "$SCRIPT_NAME" | xargs ps | awk -v re="$SCRIPT_NAME" '$6~re {print $1,$7}'
}

stop_process() {
  get_process | cut -wf1 | xargs kill 
}

# PID file control
check_pid() {
  [ -f "$PID_DIR/$SCRIPT_NAME.pid" ] || return "$PID_FILE_NOT_FOUND" 
}

get_pid() {
  check_pid && cat "$PID_DIR/$SCRIPT_NAME.pid"
}

# $1 - execute command
create_pid() {
  echo "$$" >"$PID_DIR/$SCRIPT_NAME.pid" || return "$ERROR_CREATE_PID"
}

remove_pid() {
  if check_pid ; then
    rm -f "$PID_DIR/$SCRIPT_NAME.pid" || return "$ERROR_REMOVE_PID" 
  fi
}

check_status() {
  return 0
}

# pipe progress
create_progress() {
  touch "$TEMP_DIR/${SCRIPT_NAME%.*}.progress"
}

remove_progress() {
  [ -f "$TEMP_DIR/${SCRIPT_NAME%.*}.progress" ] && rm -f "$TEMP_DIR/${SCRIPT_NAME%.*}.progress"
}

push_progress() {
  echo "$1" >"$TEMP_DIR/${SCRIPT_NAME%.*}.progress"
}

show_progress() {
  [ -f "$TEMP_DIR/${SCRIPT_NAME%.*}.progress" ] && tail -n1 "$TEMP_DIR/${SCRIPT_NAME%.*}.progress"
}

# Check required utilities
check_utility() {
  while [ "$#" -gt 0 ] ; do
    type "$1" >/dev/null 2>&1 || exit_error "$1 not found!" "$UTILITY_NOT_FOUND"
    shift
  done
}

handle_exit() {
  remove_progress
  remove_pid
}

# Logger
# $1 - massage priority
# $2 - message text
log() {
  [ "$SYSLOG" = "true" ] && logger -p "$1" -t "${SCRIPT_NAME%.*}" "$2" 
  [ "$FILELOG" = "true" ] && echo "$(timestamp)" "$1" "$2" >>"$FILELOG_DIR/${SCRIPT_NAME%.*}.log"
}

# Error logger
# $1 - message text
log_error() {
  log "$PRIORITY_ERROR" "$1"
}

# Info logger
# $1 - message text
log_info() {
  log "$PRIORITY_INFO" "$1"
}

# Remove all space/tabs
# $1 - string
strip_str() {
 echo "$1" | sed 's/[[:blank:]]*//g'
}

# Remove start and end space/tabs
# $1 - string
strip_str_frame() {
  # check regex!!!
 echo "$1" | sed 's/^([[:blank:]]*)(.*)([[:blank:]]*)$/\2/'
}

# Upload remote file
# $1 - file URI 
# $2 - upload directory
fetch_file() {
  if fetch -aqr "$1" -o "$2" 2>/dev/null; then log_info "success fetch $1 to $2/" 
    else log_info "fail fetch $1 to $2/ by code $?" 
  fi
}

# Unpack and parse packagesite manifest file with grep (not work)
#parse_manifest_grep() {
  #grep -n -o -e "name":"[^"]*" -e "version":"[^"]*" -e "repopath":"[^"]*"
#}

# Unpack and parse packagesite manifest file with sed (slow)
# $1 - TAR packages file path 
# $2 - CSV packages file path 
parse_manifest_sed() {
  tar -xJOf "$1" "$MANIFESTS" >"${1%.*}"
  head -n20 "${1%.*}" \
  | tail -n20 \
  | sort \
  | head -n12 \
  | sed -nE 's/.*"name":"([^"]*)".*"version":"([^"]*)".*"repopath":"([^"]*)".*"sum":"([^"]*)".*/\1 \2 \3 \4/p' \
  | sort >"$2"
  rm -f "${1%.*}" 
}

# Unpack and parse packagesite manifest file with awk (fast)
# $1 - TAR packages file path 
# $2 - CSV packages file path 
parse_manifest_awk() {
  tar -xJOf "$1" "$MANIFESTS" >"${1%.*}"

  if [ "$TEMP_MODE_RECORDS" = "ALL" ] ; then
    cat "${1%.*}" >"${1%.*}.part"
  else
    head -n"$TEMP_HEAD_RECORDS" "${1%.*}" | tail -n"$TEMP_TAIL_RECORDS" >"${1%.*}.part"
  fi

  rm -f "${1%.*}" 

  awk 'BEGIN {OFS=";"} {
      if(match($0,/"name"[^"]*"[^"]*"/)) {name=substr($0,RSTART,RLENGTH);if(match(name,/:[^"]*"[^"]*"/)){name=substr(name,RSTART+2,RLENGTH-3)}}
      if(match($0,/"version"[^"]*"[^"]*"/)) {version=substr($0,RSTART,RLENGTH);if(match(version,/:[^"]*"[^"]*"/)){version=substr(version,RSTART+2,RLENGTH-3)}}
      if(match($0,/"repopath"[^"]*"[^"]*"/)) {repopath=substr($0,RSTART,RLENGTH);if(match(repopath,/:[^"]*"[^"]*"/)){repopath=substr(repopath,RSTART+2,RLENGTH-3)}}
      if(match($0,/"sum"[^"]*"[^"]*"/)) {sum=substr($0,RSTART,RLENGTH);if(match(sum,/:[^"]*"[^"]*"/)){sum=substr(sum,RSTART+2,RLENGTH-3)}}
      {print name, version, repopath, sum} }' \
  <"${1%.*}.part" | sort >"$2"

  rm -f "${1%.*}.part" 
}

# Create diff packages file
# $1 - first CSV sorted packages file path 
# $2 - second CSV sorted packages file path 
# $3 - diff CSV packages file path 
create_diff() {
  comm -23 "$1" "$2" >"${3}.1"
  comm -13 "$1" "$2" >"${3}.2"
  paste "${3}.1" "${3}.2" >"$3" && rm -f "${3}.1" "${3}.2"
}

# Check exist "REPOS_DIR" directory
check_repos_path() {
  [ -d "$REPOS_DIR" ] || exit_error "$REPOS_DIR not exist" "$NOT_EXIST"
  [ -w "$REPOS_DIR" ] || exit_error "$REPOS_DIR not write directory mode" "$ERROR_FILE_MODE"
}

check_push_diffs_path() {
  [ -d "$PUSH_DIFFS_DIR" ] || exit_error "$PUSH_DIFFS_DIR not exist" "$NOT_EXIST"
  [ -w "$PUSH_DIFFS_DIR" ] || exit_error "$PUSH_DIFFS_DIR not write directory mode" "$ERROR_FILE_MODE"
}

check_pull_diffs_path() {
  [ -d "$PULL_DIFFS_DIR" ] || exit_error "$PULL_DIFFS_DIR not exist" "$NOT_EXIST"
  [ -w "$PULL_DIFFS_DIR" ] || exit_error "$PULL_DIFFS_DIR not write directory mode" "$ERROR_FILE_MODE"
}
# Remote repo list
repo_remote_list() {
  fetch -qo - "$REMOTE_REPOS_URL" \
  | grep "<a href=\"FreeBSD" \
  | sed -nE 's/.*href="([^"]+)">(.+)<.*/\1 \2/p' \
  | sed '/^[[:space:]]*$/d'
}

# Remote repo branch list
# $1 - version
# $2 - arch
repo_remote_branch_list() {
  fetch -qo - "$REMOTE_REPOS_URL/FreeBSD:$1:$2" \
  | grep "<a href=" \
  | sed -nE 's/.*href="([^"]+)".*title="([^"]+)".*"size">([^<>]+)<.*"date">([^<>]+)</\1 \2 \3 \4/p' \
  | sed '/^[[:space:]]*$/d'
}

# Check presence REPO_VERSION ENV
check_repo_version_env() {
  [ -z "$REPO_VERSION" ] && return "$IS_EMPTY"
}

# Check presence REPO_ARCH ENV
check_repo_arch_env() {
  [ -z "$REPO_ARCH" ] && return "$IS_EMPTY"
}

# Check presence REPO_BRANCH ENV
check_repo_branch_env() {
  [ -z "$REPO_BRANCH" ] && return "$IS_EMPTY"
}

# $1 - abi list VERSION:ARCH format
check_abi() {
  [ -z "$(echo "$1" | grep -E "^$REPO_VERSION:$REPO_ARCH$")" ] && return "$IS_EMPTY"
}

# Local repo initialize
# $1 - version
# $2 - arch
init_repo() {
  [ -d "$REPOS_DIR/FreeBSD:$1:$2" ] \
  && warn "repo $REPOS_DIR/FreeBSD:$1:$2 is exist, ignore init new repo" \
  || ( mkdir -p "$REPOS_DIR/FreeBSD:$1:$2" \
       && success "repo $REPOS_DIR/FreeBSD:$1:$2 is created" )
}

# Local repo branch initialize
# $1 - version
# $2 - arch
# $3 - branch
init_repo_branch() {
  [ -d "$REPOS_DIR/FreeBSD:$1:$2/$3" ] \
  && warn "repo branch $REPOS_DIR/FreeBSD:$1:$2/$3 is exist, ignore init new repo branch" \
  || ( mkdir -p "$REPOS_DIR/FreeBSD:$1:$2/$3/$DIFFS_DIR" 
       [ "$MODE" = "PUBLIC" ] && timestamp >"$REPOS_DIR/FreeBSD:$1:$2/$3/$DIFFS_DIR/$DIFFS_DIR.init" 
       [ "$MODE" = "PRIVATE" ] && touch "$REPOS_DIR/FreeBSD:$1:$2/$3/$DIFFS_DIR/$DIFFS_DIR.init" 
       success "repo branch $REPOS_DIR/FreeBSD:$1:$2/$3 is created" )
}

# Local repo remove
# $1 - version
# $2 - arch
remove_repo() {
  if [ -d "$REPOS_DIR/FreeBSD:$1:$2" ] ; then
    rm -rI "$REPOS_DIR/FreeBSD:$1:$2" && success "remove repo $REPOS_DIR/FreeBSD:$1:$2"
  else 
    warn "repo $REPOS_DIR/FreeBSD:$1:$2 not exist, ignore remove repo FreeBSD:$1:$2"
  fi
}

# Local repo branch remove
# $1 - version
# $2 - arch
# $3 - branch
remove_repo_branch() {
  if [ -d "$REPOS_DIR/FreeBSD:$1:$2/$3" ] ; then
    rm -rI "$REPOS_DIR/FreeBSD:$1:$2/$3" && success "remove repo branch $REPOS_DIR/FreeBSD:$1:$2/$3"
  else 
    warn "repo branch $REPOS_DIR/FreeBSD:$1:$2/$3 not exist, ignore remove branch $3"
  fi
}

# Fetch packagesite, meta, data files
# $1 - repo name + branch
# $2 - destination dir
fetch_service_files() {
  remote_repo_url="$REMOTE_REPOS_URL/$1"
  for file in $(printf "%s" "$META_FILES,$PACKAGESITE_FILES,$DATA_FILES" | awk -F, 'BEGIN {OFS=" "} {$1=$1; print}') ; do
    fetch_file "$remote_repo_url/$file" "$2"
  done
}

# Fetch packagesite, meta, data files
# $1 - source dir
# $2 - repo name + branch
copy_service_files() {
  for file in $(printf "%s" "$META_FILES,$PACKAGESITE_FILES,$DATA_FILES" | awk -F, 'BEGIN {OFS=" "} {$1=$1; print}') ; do
    if [ -f "$1/$file" ] ; then  
      cp -fp "$1/$file" "$2" 2>/dev/null && log_info "success copy $1 to $2/" || log_info "fail copy $1 to $2/ by code $?"
    fi
  done
}

FETCH_EXEC=$(cat <<-'EOF'
  local_path="$(echo "$0" | awk 'BEGIN {FS="/";OFS="/"} {NF--;print}')"
  [ -d "$2/$local_path" ] || mkdir -p "$2/$local_path"
  fetch -aqr "$1/$0" -o "$2/$0" 2>/dev/null && echo "success;fetch;$1/$0;to;$2/" || echo "fail;fetch;$1/$0;to;$2/"
EOF
)

COUNT_EXEC=$(cat <<-'EOF'
  #echo $(( $(tail -n1 .counter ) - 1 )) >.counter
EOF
)

COPY_EXEC=$(cat <<-'EOF'
  local_path="$(echo "$0" | awk 'BEGIN {FS="/";OFS="/"} {NF--;print}')"
  attempts=5
  timeout=60
  [ -d "$2/$local_path" ] || mkdir -p "$2/$local_path"
  while [ ! -f "$1/$0" -a "$attempts" -gt 0 ] ; do
   sleep "$timeout"
   attempts="$(( attempts - 1 ))"
  done
  cp -fpR "$1/$0" "$2/$0" 2>/dev/null && echo "success;copy;$1/$0;to;$2/" || echo "fail;copy;$1/$0;to;$2/"
EOF
)

CHECK_EXEC=$(cat <<-'EOF'
  [ -f "$1/$0" ] && echo "success;check;$1/$0" || echo "fail;check;$1/$0"
EOF
)

REMOVE_EXEC=$(cat <<-'EOF'
  rm -f "$1/$0" 2>/dev/null && echo "success;remove;$1/$0" || echo "fail;remove;$1/$0"
EOF
)

# $0 message text
# $1 message priority
# $2 SCRIPT_BASENAME
# $3 SYSLOG
# $4 FILELOG
# $5 FILELOG_DIR
# $6 timestamp
LOG_EXEC=$(cat <<-'EOF'
  message="$(echo $0 | tr ';' ' ' )"
  [ "$3" = "true" ] && logger -p "$1" -t "$2" "$message" 
  [ "$4" = "true" ] && echo "$6" "$1" "$message" >>"$5/$2.log"
  echo "success;logging;$1"
EOF
)

PROGRESS_EXEC=$(cat <<-'EOF'
  echo "$0" >>"$1" 
  echo "success;progress;$0/$1"
EOF
)

# Update repo branch
# $1 - repo name + branch
# $2 - last diff dir
# $3 - current diff dir
# $4 - timestamp
update_repo_branch() {
  fetch_service_files "$1" "$3"
  for file in $(printf "%s" "$PACKAGESITE_FILES" | awk -F, 'BEGIN {OFS=" "} {$1=$1; print}') ; do
    if [ -f "$3/$file" ] ; then
      #sed_parse "${file}" 
      parse_manifest_awk "$3/$file" "$3/${MANIFESTS%.*}.csv"
      break
    fi
  done
  if [ -n "$2" ] ; then
    create_diff "$2/${MANIFESTS%.*}.csv" "$3/${MANIFESTS%.*}.csv" "$3/$DIFF_DIR.csv"
  else { 
    echo "" >"$3/${MANIFESTS%.*}.init.csv" \
    && create_diff "$3/${MANIFESTS%.*}.init.csv" "$3/${MANIFESTS%.*}.csv" "$3/$DIFF_DIR.csv" \
    && rm -f "$3/${MANIFESTS%.*}.init.csv" 
    }
  fi

  # set count .pkg add in PID file !!!
  #cut -wf2 "$3/$DIFF_DIR.csv" | sed '/^[[:space:]]*$/d' | wc -l >.counter
  # Decrement counter for xargs exec
  # echo $(( $(tail -n1 tst) - 1 )) >>tst

  # TODO add logging
  max_packages="$(cut -wf2 "$3/$DIFF_DIR.csv" | sed '/^[[:space:]]*$/d' | wc -l)"
  count_packages=0
  create_progress
  #exec 3<>"$TEMP_DIR/progress"

  # TODO fix counter functional
  cut -wf2 "$3/$DIFF_DIR.csv" | sed '/^[[:space:]]*$/d' | cut -d';' -f3 \
  | xargs -n1 -P"$THREADS" -S2048 -I% sh -c "$FETCH_EXEC" % "$REMOTE_REPOS_URL/$1" "$REPOS_DIR/$1" \
  | xargs -n1 -S2048 -I% sh -c "$LOG_EXEC" % "$PRIORITY_INFO" "${SCRIPT_NAME%.*}" "$SYSLOG" "$FILELOG" "$FILELOG_DIR" "$(timestamp)" \
  | xargs -n1 -I% echo $(( count_packages=$count_packages + 1 )) \
  | xargs -n1 -I% sh -c "$PROGRESS_EXEC" "%/$max_packages" "$TEMP_DIR/${SCRIPT_NAME%.*}.progress" 
  #| xargs -n1 echo >/dev/null

  #cat "$TEMP_DIR/progress"
  #exec 3>&-
  #remove_progress

  copy_service_files "$3" "$REPOS_DIR/$1"
}

##########################################/SERVICE FUNCTIONS###########################

##########################################PARSE OPTIONS################################
parse_options() {
  #[ "$#" -eq "0" ] && usage "$1"
  COMMAND="$1" && shift
  OPTIND=1
  while getopts :V:A:B:n:fhsa OPT; do
    case "$OPT" in
      h) usage "$COMMAND" ;;
      s) SILENT=true ;; 
      a) CHOICE=ALL ;; 
      f) FORCE=true ;; 
      n) case "$COMMAND" in
          'push'|'pull') COUNT="${OPTARG:-1}" ;;
          *) exit_error "unknown option -$OPT for command $COMMAND" "$UNKNOWN_OPTION" ;;
          esac ;;
      V) case "$COMMAND" in
          'init'|'remove'|'info'|'remote-info'|'check'| \
          'remote-check'|'clone'|'update'|'push'|'pull') REPO_VERSION="$OPTARG" ;;
          *) exit_error "unknown option -$OPT for command $COMMAND" "$UNKNOWN_OPTION" ;;
          esac ;;
      A) case "$COMMAND" in
          'init'|'remove'|'info'|'remote-info'|'check'| \
          'remote-check'|'clone'|'update'|'push'|'pull') REPO_ARCH="$OPTARG" ;;
          *) exit_error "unknown option -$OPT for command $COMMAND" "$UNKNOWN_OPTION" ;;
          esac ;;
      B) case "$COMMAND" in
          'init'|'remove'|'info'|'remote-info'|'check'| \
          'remote-check'|'clone'|'update'|'push'|'pull') REPO_BRANCHES="$OPTARG" ;;
          *) exit_error "unknown option -$OPT for command $COMMAND" "$UNKNOWN_OPTION" ;;
          esac ;;
      :) exit_error "option -${OPTARG} requires an argument\n" "$MISSING_OPT_ARG" ;;
      \?) exit_error "unknown option -$OPT" "$UNKNOWN_OPTION" ;;
    esac
  done
}
##########################################/PARSE OPTIONS#########################################

##########################################COMMAND HANDLERS#######################################

# Init local repository command handler
init_repo_handler() {
  parse_options "$@"
  [ -z "$REPO_VERSION" ] && exit_error "$MSG_REPO_VERSION_IS_EMPTY" "$IS_EMPTY"
  [ -z "$REPO_ARCH" ] && exit_error "$MSG_REPO_ARCH_IS_EMPTY" "$IS_EMPTY"

  init_repo "$REPO_VERSION" "$REPO_ARCH"

  if [ -n "$REPO_BRANCHES" ] ; then
      branches=$(strip_str "$REPO_BRANCHES" | awk -F, '{$1=$1;print}')
      for branch in $branches ; do
        [ -n "$branch" ] && init_repo_branch "$REPO_VERSION" "$REPO_ARCH" "$branch"
      done
  fi
  #find "${REPOS_PATH}/FreeBSD:${REPO_VERSION}:${REPO_ARCH}" -type d -name {} -exec \
}

# Remove local repository command handler
remove_repo_handler() {
  parse_options "$@"
  [ -z "$REPO_VERSION" ] && exit_error "$MSG_REPO_VERSION_IS_EMPTY" "$IS_EMPTY"
  [ -z "$REPO_ARCH" ] && exit_error "$MSG_REPO_ARCH_IS_EMPTY" "$IS_EMPTY"

  if [ -n "$REPO_BRANCHES" ] ; then
    branches=$(strip_str "$REPO_BRANCHES" | awk -F, '{$1=$1;print}')
    for branch in $branches ; do
      [ -n "$branch" ] && remove_repo_branch "$REPO_VERSION" "$REPO_ARCH" "$branch"
    done
  else
    remove_repo "$REPO_VERSION" "$REPO_ARCH"
  fi
}

# Info local repository command handler
info_repo_handler() {
  parse_options "$@"
  printf "info handler\n"
  printf "params %s\n" "$@"
}

# Info remote repository command handler
remote_info_repo_handler() {
  if [ "$MODE" != "PUBLIC" ] ; then 
    info "Only PUBLIC mode"
    usage "remote-info" 
  fi

  parse_options "$@"
  #shift $(("${OPTIND}"))
  printf "Info remote repo FreeBSD:%s:%s\n" "$REPO_VERSION" "$REPO_ARCH"
  repo_remote_branch_list "$REPO_VERSION" "$REPO_ARCH" \
  | awk 'BEGIN {print "BRANCH","SIZE","DATE"} {print $2,$3,$4}' 
}

# List local repos command handler
list_repo_handler() {
  parse_options "$@"
  printf "list handler\n"
  printf "params %s\n" "$@"
}

# List remote repos command handler
remote_list_repo_handler() {
  if [ "$MODE" != "PUBLIC" ] ; then 
    info "Only PUBLIC mode"
    usage "remote-list" 
  fi

  parse_options "$@"

  repo_remote_list \
  | cut -wf2 \
  | sort \
  | awk -F: 'BEGIN {OFS=" ";print "OS","VERSION","ARCH"} {$1=$1;print $0}'
}

# Check local repository command handler
check_repo_handler() {
  parse_options "$@"
  printf "check handler\n"
  shift $(("${OPTIND}"))
  #printf "params %s\n" "$@"
}

# Check diffs between local and remote repos command handler
remote_check_repo_handler() {
  parse_options "$@"
  printf "remote check handler\n"
  printf "params %s\n" "$@"
}

# Status script command handler
status_handler() {
  parse_options "$@"
  get_process | awk 'BEGIN {print "PID","COMMAND"} {print}' 
  show_progress
}

# Update local repository command handler
update_repo_handler() {
  if [ "$MODE" != "PUBLIC" ] ; then 
    info "Only PUBLIC mode"
    usage "update" 
  fi

  parse_options "$@"

  [ -z "${REPO_VERSION}" ] && exit_error "repo version is empty" "$IS_EMPTY"
  [ -z "${REPO_ARCH}" ] && exit_error "repo arch is empty" "$IS_EMPTY"

  if [ -n "${REPO_BRANCHES}" ] ; then 
    branches="$(strip_str "$REPO_BRANCHES" | awk -F, '{$1=$1;print}')"

    for branch in $branches ; do
      repo_branch_name="FreeBSD:$REPO_VERSION:$REPO_ARCH/$branch"
      remote_repo_url="$REMOTE_REPOS_URL/$repo_branch_name"
      repo_branch_dir="$REPOS_DIR/$repo_branch_name"

      if [ -n "$branch" ] && [ -d "$repo_branch_dir" ] ; then 
        current_timestamp="$(timestamp)"
        last_diff_dir="$(find "$repo_branch_dir/$DIFFS_DIR" -type d -name "$DIFF_DIR.*" | sort | tail -n1)"

        if [ -z "$last_diff_dir" ] ; then 
          start_timestamp="$(cat "$repo_branch_dir/$DIFFS_DIR/$DIFFS_DIR.init")" \
          && mkdir -p "$repo_branch_dir/$DIFFS_DIR/$DIFF_DIR.$start_timestamp.$current_timestamp"
        else
          mkdir -p "$repo_branch_dir/$DIFFS_DIR/$DIFF_DIR.${last_diff_dir##*.}.$current_timestamp"
        fi

        current_diff_dir="$(find "$repo_branch_dir/$DIFFS_DIR" -type d -name "$DIFF_DIR.*" | sort | tail -n1)"

        update_repo_branch "$repo_branch_name" "$last_diff_dir" "$current_diff_dir" "$current_timestamp"
      fi
    done
  fi
}

# $1 - path to (push/pull) diff dir
check_diff_dir() {
  [ -d "$1" ] || exit_error "$1 not exist" "$NOT_EXIST"
  checked_diff_dir="$(echo "$1" | awk -F/ '{print $NF}' | awk -F: '{print $NF}')"
  [ -f "$1/$DIFF_DIR.csv" ] || exit_error "$1/${DIFF_DIR}.csv" "$NOT_EXIST"

  cut -wf2 "$1/$DIFF_DIR.csv" | sed '/^[[:space:]]*$/d' | cut -d';' -f3 \
  | xargs -n1 -P"$THREADS" -S2048 -I% sh -c "$CHECK_EXEC" % "$1/packages" \
  | xargs -n1 echo
}

# Push diffs from local repository to private network command handler
push_repo_handler() {
  if [ "$MODE" != "PUBLIC" ] ; then 
    info "Only PUBLIC mode"
    usage "push" 
  fi

  parse_options "$@"

  [ -z "${REPO_VERSION}" ] && exit_error "repo version is empty" "$IS_EMPTY"
  [ -z "${REPO_ARCH}" ] && exit_error "repo arch is empty" "$IS_EMPTY"

  if [ -n "${REPO_BRANCHES}" ] ; then 
    branches="$(strip_str "$REPO_BRANCHES" | awk -F, '{$1=$1;print}')"

    for branch in $branches ; do
      repo_branch_name="FreeBSD:$REPO_VERSION:$REPO_ARCH/$branch"
      repo_branch_dir="$REPOS_DIR/$repo_branch_name"

      if [ -n "$branch" ] && [ -d "$repo_branch_dir" ] ; then 
        init_diffs="$(sed '1d' "$repo_branch_dir/$DIFFS_DIR/$DIFFS_DIR.init" | sort )"
        diff_dirs="$(find "$repo_branch_dir/$DIFFS_DIR" -type d -name "$DIFF_DIR.*" | sort )"

        echo "$init_diffs" >"$repo_branch_dir/$DIFFS_DIR/.diffs.push"
        echo "$diff_dirs" | awk -F/ '{print $NF}' | sed 's/^diff.//g' >"$repo_branch_dir/$DIFFS_DIR/.diffs.fetched"

        last_diffs="$(comm -13 "$repo_branch_dir/$DIFFS_DIR/.diffs.push" "$repo_branch_dir/$DIFFS_DIR/.diffs.fetched")"

        rm -f "$repo_branch_dir/$DIFFS_DIR/.diffs.push"
        rm -f "$repo_branch_dir/$DIFFS_DIR/.diffs.fetched"

        for dir in $last_diffs ; do
          push_dir="$PUSH_DIFFS_DIR/FreeBSD:$REPO_VERSION:$REPO_ARCH:$branch:${dir##*/}"
          mkdir -p "$push_dir/packages"
          cp -fp "$repo_branch_dir/$DIFFS_DIR/$DIFF_DIR.$dir/"* "$push_dir"

          cut -wf2 "$repo_branch_dir/$DIFFS_DIR/$DIFF_DIR.$dir/$DIFF_DIR.csv" | sed '/^[[:space:]]*$/d' | cut -d';' -f3 \
          | xargs -n1 -P"$THREADS" -S2048 -I% sh -c "$COPY_EXEC" % "$repo_branch_dir" "$push_dir/packages" \
          | xargs -n1 -S2048 -I% sh -c "$LOG_EXEC" % "$PRIORITY_INFO" "${SCRIPT_NAME%.*}" "$SYSLOG" "$FILELOG" "$FILELOG_DIR" "$(timestamp)"
          echo "${dir##*/diff.}" >>"$repo_branch_dir/$DIFFS_DIR/$DIFFS_DIR.init"
        done
      fi
    done
  fi
}

# Pull diffs to private network command handler
pull_repo_handler() {
  if [ "$MODE" != "PRIVATE" ] ; then 
    info "Only PRIVATE mode"
    usage "pull" 
  fi

  parse_options "$@"

  [ -z "${REPO_VERSION}" ] && exit_error "repo version is empty" "$IS_EMPTY"
  [ -z "${REPO_ARCH}" ] && exit_error "repo arch is empty" "$IS_EMPTY"

  if [ -n "${REPO_BRANCHES}" ] ; then 
    branches="$(strip_str "$REPO_BRANCHES" | awk -F, '{$1=$1;print}')"

    for branch in $branches ; do
      repo_branch_name="FreeBSD:$REPO_VERSION:$REPO_ARCH/$branch"
      repo_branch_dir="$REPOS_DIR/$repo_branch_name"

      if [ -n "$branch" ] && [ -d "$repo_branch_dir" ] ; then 
        [ -f "$repo_branch_dir/$DIFFS_DIR/.diffs.init" ] || exit_error "$repo_branch_dir/$DIFFS_DIR/.diffs.init" "$NOT_EXIST"
        init_diffs="$(sort "$repo_branch_dir/$DIFFS_DIR/.diffs.init")"
        pull_diff_dirs="$(find "$PULL_DIFFS_DIR" -type d -name "FreeBSD:$REPO_VERSION:$REPO_ARCH:$branch*" | sort )"

        echo "$init_diffs" >"$repo_branch_dir/$DIFFS_DIR/.diffs.pull"
        echo "$pull_diff_dirs" | awk -F/ '{print $NF}' | awk -F: '{print $NF}' >"$repo_branch_dir/$DIFFS_DIR/.diffs.fetched"

        last_diffs="$(comm -13 "$repo_branch_dir/$DIFFS_DIR/.diffs.pull" "$repo_branch_dir/$DIFFS_DIR/.diffs.fetched")"

        rm -f "$repo_branch_dir/$DIFFS_DIR/.diffs.pull"
        rm -f "$repo_branch_dir/$DIFFS_DIR/.diffs.fetched"

        for diff in $last_diffs ; do
          pull_dir="$PULL_DIFFS_DIR/FreeBSD:$REPO_VERSION:$REPO_ARCH:$branch:$diff"
          check_diff_dir "$pull_dir" | cut -d";" -f1,3 
          copy_service_files "$pull_dir" "$repo_branch_dir"
          cp -fp "$pull_dir/diff.csv" "$repo_branch_dir/$DIFFS_DIR/.diff.$diff.csv"

          cut -wf2 "$pull_dir/$DIFF_DIR.csv" | sed '/^[[:space:]]*$/d' | cut -d';' -f3 \
          | xargs -n1 -P"$THREADS" -S2048 -I% sh -c "$COPY_EXEC" %  "$pull_dir/packages" "$repo_branch_dir" \
          | xargs -n1 -P1 -S2048 -I% sh -c "$LOG_EXEC" % "$PRIORITY_INFO" "${SCRIPT_NAME%.*}" "$SYSLOG" "$FILELOG" "$FILELOG_DIR" "$(timestamp)"

          cut -wf1 "$pull_dir/$DIFF_DIR.csv" | sed '/^[[:space:]]*$/d' | cut -d';' -f3 \
          | xargs -n1 -P"$THREADS" -S2048 -I% sh -c "$REMOVE_EXEC" % "$repo_branch_dir" \
          | xargs -n1 -P1 -S2048 -I% sh -c "$LOG_EXEC" % "$PRIORITY_INFO" "${SCRIPT_NAME%.*}" "$SYSLOG" "$FILELOG" "$FILELOG_DIR" "$(timestamp)"

          echo "$diff" >>"$repo_branch_dir/$DIFFS_DIR/$DIFFS_DIR.init"
          rm -rf "$pull_dir"
        done
      fi
    done
  fi
}

# History updates local repository
log_repo_handler() {
  parse_options "$@"
  printf "log handler\n"
  printf "params %s\n" "$@"
}

# Stop all active script jobs
stop_handler() {
  parse_options "$@"
  stop_process
}

##########################################/COMMAND HANDLERS##########################################

##########################################ENRTY POINT################################################

#set -o nounset
set -o errexit
(set -o pipefail 2>/dev/null) && set -o pipefail

check_utility date getopts tar fetch mkdir comm logger tee printf awk sed tail head rm sort xargs pgrep cut trap nproc
load_conf
check_repos_path
[ "$MODE" = "PUBLIC" ] && check_push_diffs_path
[ "$MODE" = "PRIVATE" ] && check_pull_diffs_path

# Set fetch threads
[ "$MAX_THREADS" = "ALL" ] && THREADS="$(nproc)" || THREADS="$MAX_THREADS"

# Handle exit
trap handle_exit HUP INT QUIT ABRT TERM

# Debug mode on
[ "$DEBUG" = "true" ] && set -x

case "$1" in
  ''|'-h') usage 'main' ;;
  '-v') printf "%s version %s\n" "${SCRIPT_NAME%.*}" "$VERSION" && exit "$SUCCESS" ;;
  'init') init_repo_handler "$@" ;;
  'remove') remove_repo_handler "$@" ;;
  'info') info_repo_handler "$@";;
  'remote-info') remote_info_repo_handler "$@";;
  'check') check_repo_handler "$@" ;;
  'list') list_repo_handler "$@" ;;
  'remote-list') remote_list_repo_handler "$@" ;;
  'remote-check') remote_check_repo_handler "$@" ;;
  'status') status_handler "$@" ;;
  'update') update_repo_handler "$@" ;;
  'push') push_repo_handler "$@" ;;
  'pull') pull_repo_handler "$@" ;;
  'log') log_repo_handler "$@" ;;
  'stop') stop_handler "$@" ;;
  *) printf "Unknown command %s\n" "$1" && usage 'main' ;;
esac

# create tempfile
#mktemp

# Debug mode off
[ "$DEBUG" = "true" ] && set +x

handle_exit 

exit "$SUCCESS"

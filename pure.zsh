# Pure
# by Sindre Sorhus
# https://github.com/sindresorhus/pure
# MIT License

# For my own and others sanity
# git:
# %b => current branch
# %a => current action (rebase/merge)
# prompt:
# %F => color dict
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)
# terminal codes:
# \e7   => save cursor position
# \e[2A => move cursor 2 lines up
# \e[1G => go to position 1 in terminal
# \e8   => restore cursor position
# \e[K  => clears everything after the cursor on the current line
# \e[2K => clear everything on the current line

# A box-drawing, two-line prompt with custom segments (conda, kube, git
# tag/commit), a command-execution-time line, and a right-aligned timestamp.
# Grafted onto pure v1.28.1's async core.
PROMPT_PREFIX_TOP='╭'
PROMPT_PREFIX_BOTTOM='╰'
RPROMPT_LINE_UP='%{'$'\e[1A''%}'    # move the cursor one line up
RPROMPT_LINE_DOWN='%{'$'\e[1B''%}'  # move the cursor one line down

# Colour the prompt corners white on success and red on failure. 141 (SIGPIPE,
# e.g. from `git log`) is treated as success.
prompt_pure_colour_for_exit_code() {
	print -n '%(141?.%F{white}.%(?.%F{white}.%F{red}))'
}

# Human-readable elapsed time; sub-second resolution below a minute.
prompt_pure_fmt_exec_time() {
	local human total_seconds=$1
	if (( total_seconds > 60 )); then
		local days=$(( total_seconds / 60 / 60 / 24 ))
		local hours=$(( total_seconds / 60 / 60 % 24 ))
		local minutes=$(( total_seconds / 60 % 60 ))
		local seconds=$(( total_seconds % 60 ))
		(( days > 0 )) && human+="${days}d "
		(( hours > 0 )) && human+="${hours}h "
		(( minutes > 0 )) && human+="${minutes}m "
		human+="${seconds}s"
	else
		typeset -F 1 total_seconds
		human="${total_seconds}s"
	fi
	print -- "$human"
}

# Re-render with a timestamp on the line being executed, then run the command.
prompt_pure_accept_line() {
	typeset -g prompt_pure_last_cmd_timestamp=$EPOCHREALTIME

	typeset -g prompt_pure_show_timestamp=true
	prompt_pure_preprompt_render
	typeset -g prompt_pure_show_timestamp=

	zle .accept-line
}

# Turns seconds into human readable time.
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
prompt_pure_human_time_to_var() {
	local human total_seconds=$1 var=$2
	local days=$(( total_seconds / 60 / 60 / 24 ))
	local hours=$(( total_seconds / 60 / 60 % 24 ))
	local minutes=$(( total_seconds / 60 % 60 ))
	local seconds=$(( total_seconds % 60 ))
	(( days > 0 )) && human+="${days}d "
	(( hours > 0 )) && human+="${hours}h "
	(( minutes > 0 )) && human+="${minutes}m "
	human+="${seconds}s"

	# Store human readable time in a variable as specified by the caller
	typeset -g "${var}"="${human}"
}

# Stores (into prompt_pure_cmd_exec_time) the execution
# time of the last command if set threshold was exceeded.
prompt_pure_check_cmd_exec_time() {
	integer elapsed
	(( elapsed = EPOCHSECONDS - ${prompt_pure_cmd_timestamp:-$EPOCHSECONDS} ))
	typeset -g prompt_pure_cmd_exec_time=
	(( elapsed > ${PURE_CMD_MAX_EXEC_TIME:-5} )) && {
		prompt_pure_human_time_to_var $elapsed "prompt_pure_cmd_exec_time"
	}
}

prompt_pure_set_title() {
	setopt localoptions noshwordsplit

	# Allow disabling title management.
	zstyle -T ":prompt:pure:title" show || return

	# Emacs terminal does not support settings the title.
	(( ${+EMACS} || ${+INSIDE_EMACS} )) && return

	case $TTY in
		# Don't set title over serial console.
		/dev/ttyS[0-9]*) return;;
	esac

	# "restore" pops the title the terminal saved when we last set it, so our
	# title only persists while a command runs and the title is otherwise left
	# untouched.
	if [[ $1 == restore ]]; then
		print -n $'\e[23;0t'
		return
	fi

	# Show hostname if connected via SSH and host display is enabled.
	local hostname=
	if (( psvar[13] )) && (( ${prompt_pure_state[show_host]:-1} )); then
		# Expand in-place in case ignore-escape is used.
		hostname="${(%):-(%m) }"
	fi

	local -a opts
	case $1 in
		expand-prompt) opts=(-P);;
		ignore-escape) opts=(-r);;
	esac

	# Save the current title, then set ours atomically in one print statement so
	# that it works when XTRACE is enabled. The escapes use $'...' so they remain
	# real control bytes even under `print -r` (the 'ignore-escape' path).
	print -n $opts $'\e[22;0t\e]0;'${hostname}${2}$'\a'
}

prompt_pure_preexec() {
	if [[ -n $prompt_pure_git_fetch_pattern ]]; then
		# Detect when Git is performing pull/fetch, including Git aliases.
		local -H MATCH MBEGIN MEND match mbegin mend
		if [[ $2 =~ (git|hub)\ (.*\ )?($prompt_pure_git_fetch_pattern)(\ .*)?$ ]]; then
			# We must flush the async jobs to cancel our git fetch in order
			# to avoid conflicts with the user issued pull / fetch.
			async_flush_jobs 'prompt_pure'
		fi
	fi

	typeset -g prompt_pure_cmd_timestamp=$EPOCHSECONDS

	# Show the executed command in the title while a process is active; skip the
	# helper used to set tab titles so we don't clobber it.
	if [[ $2 != set-tab-title* ]]; then
		prompt_pure_set_title 'ignore-escape' "$2"
	fi

	# Disallow Python virtualenv from updating the prompt. Set it to 20 if
	# untouched by the user to indicate that Pure modified it. Here we use
	# the magic number 20, same as in `psvar`.
	export VIRTUAL_ENV_DISABLE_PROMPT=${VIRTUAL_ENV_DISABLE_PROMPT:-20}
}

# Change the colors if their value are different from the current ones.
prompt_pure_set_colors() {
	local color_temp key value
	for key value in ${(kv)prompt_pure_colors}; do
		zstyle -t ":prompt:pure:$key" color "$value" && continue
		case $? in
			1) # The current style is different from the one from zstyle.
				zstyle -s ":prompt:pure:$key" color color_temp
				prompt_pure_colors[${key}]=$color_temp ;;
			2) # No style is defined.
				prompt_pure_colors[${key}]=${prompt_pure_colors_default[${key}]} ;;
		esac
	done

	prompt_pure_set_path_separator

	return 0
}

prompt_pure_set_path_separator() {
	typeset -g prompt_pure_path_segment="%F{${prompt_pure_colors[path]}}%~%f"

	if zstyle -t ':prompt:pure:path:separator' dim; then
		typeset -g prompt_pure_path_separator_dimmed=1
	else
		typeset -g prompt_pure_path_separator_dimmed=
	fi
}

prompt_pure_render_dimmed_path() {
	setopt localoptions noshwordsplit

	# This runs from PROMPT_SUBST so directory changes followed by reset-prompt redraw correctly without precmd.
	local current_path=${1:-${(%):-%~}}
	current_path=${current_path//\%/%%}

	local separator=$'%{\e[2m%}/%{\e[22m%}'
	# Keep the leading / on absolute paths at full brightness.
	local prefix=
	if [[ $current_path == /* ]]; then
		prefix=/
		current_path=${current_path:1}
	fi
	print -n -r -- "%F{${prompt_pure_colors[path]}}${prefix}${current_path//\//$separator}%f"
}

prompt_pure_preprompt_render() {
	setopt localoptions noshwordsplit

	unset prompt_pure_async_render_requested

	# Branch/dirty colour: red once the dirty-check result is cached.
	typeset -g prompt_pure_git_branch_color=101
	[[ -n ${prompt_pure_git_last_dirty_check_timestamp+x} ]] && prompt_pure_git_branch_color=red

	# Populate the psvar slots used by the static PROMPT template (built once in
	# prompt_pure_setup). Each is rendered with %(NV.true.false), so an empty
	# slot simply vanishes. Using a static PROMPT + psvar — rather than
	# rebuilding the whole PROMPT string every render — keeps `zle reset-prompt`
	# repainting a fixed structure, which is what prevents the cd-time redraw
	# corruption.
	#   psvar[14]=branch  [15]=dirty  [16]=arrows  [17]=tag/commit
	#   psvar[18]=conda   [19]=kube
	psvar[14]=${prompt_pure_vcs_info[branch]}
	psvar[15]=${prompt_pure_git_dirty}
	psvar[16]=${prompt_pure_git_arrows}
	psvar[17]=${prompt_pure_git_tag_and_commit}

	# Conda environment (only inside a named env under .../envs/...).
	psvar[18]=
	local _conda=$CONDA_ENV_PATH$CONDA_PREFIX
	if [[ -n $_conda && $CONDA_PREFIX =~ .+/envs/.+ ]]; then
		psvar[18]=$'\UE73C'" ${_conda:t}"
	fi

	# Kubernetes context. Gated on the aws CLI being present, as a cheap proxy
	# for "this is a work machine where kube context is relevant".
	psvar[19]=
	if (( $+commands[aws] )); then
		local kube_info=$(command kubectl config current-context 2>/dev/null)
		if [[ -n $kube_info ]]; then
			local kube_namespace=$(command kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null)
			[[ -n $kube_namespace ]] && kube_info="${kube_info}:${kube_namespace}"
			psvar[19]=$'\U000F10FE'" ${kube_info}"
		fi
	fi

	# Right-aligned timestamp of the command being run (set via accept-line),
	# floated onto the preprompt line with a cursor-up RPROMPT.
	if [[ $prompt_pure_show_timestamp == true ]]; then
		local timestamp_str=$(command date --date="@${prompt_pure_last_cmd_timestamp%.*}" +' %a %H:%M:%S')
		RPROMPT="${RPROMPT_LINE_UP} %F{242}"$''"${timestamp_str}%f${RPROMPT_LINE_DOWN}"
	else
		RPROMPT=''
	fi

	# Detect changes in the dynamic parts without expanding PROMPT (no subshell).
	local -a fingerprint_parts=(
		"${psvar[14]}" "${psvar[15]}" "${psvar[16]}" "${psvar[17]}"
		"${psvar[18]}" "${psvar[19]}" "${prompt_pure_git_branch_color}"
		"${RPROMPT}" "${PWD}"
	)
	local fingerprint="${(pj:|:)${(@qqq)fingerprint_parts}}"

	if [[ $1 == precmd ]]; then
		# Initial blank line for spaciousness — printed, not baked into PROMPT
		# (a leading newline in PROMPT reintroduces the reset-prompt corruption).
		print
	elif [[ $prompt_pure_last_prompt != $fingerprint ]]; then
		prompt_pure_reset_prompt
	fi

	typeset -g prompt_pure_last_prompt=$fingerprint
}

prompt_pure_precmd() {
	setopt localoptions noshwordsplit

	# Print the previous command's execution time on its own line if it exceeds
	# the threshold.
	if [[ -n $prompt_pure_last_cmd_timestamp ]]; then
		integer elapsed=$(( EPOCHREALTIME - prompt_pure_last_cmd_timestamp ))
		(( elapsed > ${PURE_CMD_MAX_EXEC_TIME:-2} )) && \
			print -P -- "%F{142}"$''" $(prompt_pure_fmt_exec_time $elapsed)%f"
		unset prompt_pure_last_cmd_timestamp
	fi

	# Restore the terminal title we saved before the command ran.
	prompt_pure_set_title 'restore'

	# Modify the colors if some have changed..
	prompt_pure_set_colors

	# Perform async Git dirty check and fetch.
	prompt_pure_async_tasks

	# Make sure the VIM prompt symbol is reset.
	prompt_pure_reset_prompt_symbol

	# Print the preprompt.
	prompt_pure_preprompt_render "precmd"

	if [[ -n $ZSH_THEME ]]; then
		print "WARNING: Oh My Zsh themes are enabled (ZSH_THEME='${ZSH_THEME}'). Pure might not be working correctly."
		print "For more information, see: https://github.com/sindresorhus/pure#oh-my-zsh"
		unset ZSH_THEME  # Only show this warning once.
	fi
}

prompt_pure_async_git_aliases() {
	setopt localoptions noshwordsplit
	local -a gitalias pullalias

	# List all aliases and split on newline.
	gitalias=(${(@f)"$(command git config --get-regexp "^alias\.")"})
	for line in $gitalias; do
		parts=(${(@)=line})           # Split line on spaces.
		aliasname=${parts[1]#alias.}  # Grab the name (alias.[name]).
		shift parts                   # Remove `aliasname`

		# Check alias for pull or fetch. Must be exact match.
		if [[ $parts =~ ^(.*\ )?(pull|fetch)(\ .*)?$ ]]; then
			pullalias+=($aliasname)
		fi
	done

	print -- ${(j:|:)pullalias}  # Join on pipe, for use in regex.
}

prompt_pure_async_vcs_info() {
	setopt localoptions noshwordsplit

	# Configure `vcs_info` inside an async task. This frees up `vcs_info`
	# to be used or configured as the user pleases.
	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	# Only export four message variables from `vcs_info`.
	zstyle ':vcs_info:*' max-exports 3
	# Export branch (%b), Git toplevel (%R), action (rebase/cherry-pick) (%a)
	zstyle ':vcs_info:git*' formats '%b' '%R' '%a'
	zstyle ':vcs_info:git*' actionformats '%b' '%R' '%a'

	vcs_info

	local -A info
	info[pwd]=$PWD
	info[branch]=${vcs_info_msg_0_//\%/%%}
	info[top]=$vcs_info_msg_1_
	info[action]=$vcs_info_msg_2_

	print -r - ${(@kvq)info}
}

# Fastest possible way to check if a Git repo is dirty.
# When detailed mode is enabled, outputs markers: * (unstaged), + (staged), ? (untracked).
prompt_pure_async_git_dirty() {
	setopt localoptions noshwordsplit
	local untracked_dirty=$1
	local detailed=${2:-0}
	local untracked_git_mode=$(command git config --get status.showUntrackedFiles)
	if [[ "$untracked_git_mode" != 'no' ]]; then
		untracked_git_mode='normal'
	fi

	# Prevent e.g. `git status` from refreshing the index as a side effect.
	export GIT_OPTIONAL_LOCKS=0

	# Skip scanning each submodule's working tree — the dominant cost of git
	# status/diff in repos with submodules, and the reason the dirty result used
	# to land late enough to corrupt the prompt redraw. A submodule checked out
	# at a different commit than the superproject records still marks the repo
	# dirty; only changes *inside* a submodule's tree are ignored. Use =all to
	# ignore submodules entirely.
	local ignore_submodules='--ignore-submodules=dirty'

	if (( ! detailed )); then
		if [[ $untracked_dirty = 0 ]]; then
			command git diff $ignore_submodules --no-ext-diff --quiet --exit-code || return $?
			command git diff $ignore_submodules --no-ext-diff --cached --quiet --exit-code
		else
			test -z "$(command git status --porcelain $ignore_submodules -u${untracked_git_mode})"
		fi

		return
	fi

	local u_flag
	if [[ $untracked_dirty = 0 ]]; then
		u_flag='-uno'
	else
		u_flag="-u${untracked_git_mode}"
	fi

	local output
	output=$(command git status --porcelain $ignore_submodules $u_flag)
	[[ -z $output ]] && return 0

	local has_unstaged=0 has_staged=0 has_untracked=0 line
	for line in "${(f)output}"; do
		(( ! has_unstaged )) && [[ ${line[2]} == [MTDUA] ]] && has_unstaged=1
		(( ! has_staged )) && [[ ${line[1]} == [MTADRCU] ]] && has_staged=1
		(( ! has_untracked )) && [[ $line == '??'* ]] && has_untracked=1
		(( has_unstaged + has_staged + has_untracked == 3 )) && break
	done

	local markers=""
	(( has_unstaged )) && markers+="*"
	(( has_staged )) && markers+="+"
	(( has_untracked )) && markers+="?"

	print -r - "$markers"
	return 1
}

prompt_pure_async_git_fetch() {
	setopt localoptions noshwordsplit

	local only_upstream=${1:-0}

	# Sets `GIT_TERMINAL_PROMPT=0` to disable authentication prompt for Git fetch (Git 2.3+).
	export GIT_TERMINAL_PROMPT=0
	# Set SSH `BachMode` to disable all interactive SSH password prompting.
	export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-"ssh"} -o BatchMode=yes"

	# If gpg-agent is set to handle SSH keys for `git fetch`, make
	# sure it doesn't corrupt the parent TTY.
	# Setting an empty GPG_TTY forces pinentry-curses to close immediately rather
	# than stall indefinitely waiting for user input.
	export GPG_TTY=

	local -a remote
	if ((only_upstream)); then
		local ref
		ref=$(command git symbolic-ref -q HEAD)
		# Set remote to only fetch information for the current branch.
		remote=($(command git for-each-ref --format='%(upstream:remotename) %(refname)' $ref))
		if [[ -z $remote[1] ]]; then
			# No remote specified for this branch, skip fetch.
			return 97
		fi
	fi

	# Default return code, which indicates Git fetch failure.
	local fail_code=99

	# Guard against all forms of password prompts. By setting the shell into
	# MONITOR mode we can notice when a child process prompts for user input
	# because it will be suspended. Since we are inside an async worker, we
	# have no way of transmitting the password and the only option is to
	# kill it. If we don't do it this way, the process will corrupt with the
	# async worker.
	setopt localtraps monitor

	# Make sure local HUP trap is unset to allow for signal propagation when
	# the async worker is flushed.
	trap - HUP

	trap '
		# Unset trap to prevent infinite loop
		trap - CHLD
		if [[ $jobstates = suspended* ]]; then
			# Set fail code to password prompt and kill the fetch.
			fail_code=98
			kill %%
		fi
	' CHLD

	# Do git fetch and avoid fetching tags or
	# submodules to speed up the process.
	command git -c gc.auto=0 -c fetch.prune=false fetch \
		--quiet \
		--no-tags \
		--no-prune-tags \
		--recurse-submodules=no \
		$remote &>/dev/null &
	wait $! || return $fail_code

	unsetopt monitor

	# Check arrow status after a successful `git fetch`.
	prompt_pure_async_git_arrows
}

prompt_pure_async_git_arrows() {
	setopt localoptions noshwordsplit
	command git rev-list --left-right --count HEAD...@'{u}'
}

# Show an exact tag (when HEAD is tagged) followed by the short commit hash.
prompt_pure_async_git_tag_and_commit() {
	setopt localoptions noshwordsplit
	local tag commit
	tag=$(command git describe --tags --exact-match HEAD 2>/dev/null)
	[[ -n $tag ]] && tag=$''" ${tag} "
	commit=$(command git rev-parse --short=8 HEAD 2>/dev/null) || return $?
	print -- "${tag}"$''" $commit"
}

prompt_pure_async_git_stash() {
	command git rev-list --walk-reflogs --count refs/stash
}

prompt_pure_check_node_version() {
	setopt localoptions noshwordsplit

	# Walk up to find package.json (similar to how git detects repos).
	local dir=$PWD
	while [[ $dir != "/" ]]; do
		[[ -f "$dir/package.json" ]] && break
		dir=${dir:h}
	done

	local version=
	if [[ -f "$dir/package.json" ]]; then
		version=$(command node --version 2>/dev/null) || version=
		version=${${${version#v}%%.*}//[$'\t\r\n']}
	fi

	print -r -- "$version"
}

# Try to lower the priority of the worker so that disk heavy operations
# like `git status` has less impact on the system responsivity.
prompt_pure_async_renice() {
	setopt localoptions noshwordsplit

	if command -v renice >/dev/null; then
		command renice +15 -p $$
	fi

	if command -v ionice >/dev/null; then
		command ionice -c 3 -p $$
	fi
}

prompt_pure_async_worker_sync() {
	setopt localoptions noshwordsplit

	local sync_token=$1 target_pwd=$2 has_git_dir=$3 git_dir=$4 has_git_work_tree=$5 git_work_tree=$6

	if ! builtin cd -q "$target_pwd"; then
		builtin cd -q /
		unset GIT_DIR GIT_WORK_TREE
		print -r -- "prompt_pure_worker_sync:$sync_token:1"
		return 1
	fi

	if (( has_git_dir )); then
		export GIT_DIR=$git_dir
	else
		unset GIT_DIR
	fi

	if (( has_git_work_tree )); then
		export GIT_WORK_TREE=$git_work_tree
	else
		unset GIT_WORK_TREE
	fi

	print -r -- "prompt_pure_worker_sync:$sync_token:0"
}

prompt_pure_clear_git_state() {
	unset prompt_pure_git_dirty prompt_pure_git_last_dirty_check_timestamp prompt_pure_git_arrows prompt_pure_git_stash prompt_pure_git_fetch_pattern prompt_pure_git_tag_and_commit
	typeset -gA prompt_pure_worker_env=()
	typeset -gA prompt_pure_worker_env_pending=()
	typeset -gA prompt_pure_vcs_info
	prompt_pure_vcs_info[branch]=
	prompt_pure_vcs_info[top]=
	prompt_pure_vcs_info[action]=
	prompt_pure_vcs_info[pwd]=
}

prompt_pure_async_init() {
	typeset -g prompt_pure_async_inited
	if ((${prompt_pure_async_inited:-0})); then
		return
	fi
	if ! async_start_worker "prompt_pure" -u -n 2>/dev/null; then
		# Worker failed to start (e.g. zpty permission denied).
		# Degrade gracefully by skipping async git operations.
		return 1
	fi
	prompt_pure_async_inited=1
	async_register_callback "prompt_pure" prompt_pure_async_callback
	async_worker_eval "prompt_pure" prompt_pure_async_renice

	# Set up the render-coalescing self-pipe (no-op after the first call).
	prompt_pure_render_init
}

prompt_pure_async_tasks() {
	setopt localoptions noshwordsplit

	# Check if Node.js version display is enabled (independent of Git).
	if zstyle -t ":prompt:pure:environment:node_version" show; then
		# Cache key uses "|" separator so the value is never a valid directory
		# path, preventing zsh from treating it as a named directory for %~.
		local node_cache_key="$PWD|$PATH"
		if [[ ${prompt_pure_node_cache_key-} != "$node_cache_key" ]]; then
			typeset -g prompt_pure_node_version=$(prompt_pure_check_node_version)
			typeset -g prompt_pure_node_cache_key=$node_cache_key
		fi
	else
		unset prompt_pure_node_version
		unset prompt_pure_node_cache_key
	fi

	# Check if git integration is enabled (default: yes).
	if ! zstyle -T ":prompt:pure:git" show; then
		# Flush any in-flight async git jobs.
		if (( ${prompt_pure_async_inited:-0} )); then
			async_flush_jobs "prompt_pure"
		fi

		prompt_pure_clear_git_state
		return
	fi

	# Initialize the async worker. If it fails (e.g. zpty unavailable),
	# skip all async tasks and show prompt without git info.
	if ! prompt_pure_async_init; then
		prompt_pure_clear_git_state
		return
	fi

	# Sync working directory and git environment variables to the async worker.
	# Skip if nothing changed since last sync (common case: running commands in same dir).
	# Uses an associative array to avoid scalar globals triggering AUTO_NAME_DIRS.
	typeset -gA prompt_pure_worker_env
	typeset -gA prompt_pure_worker_env_pending
	local cur_git_dir=${GIT_DIR-__unset__}
	local cur_git_work_tree=${GIT_WORK_TREE-__unset__}
	if [[ $PWD != ${prompt_pure_worker_env[pwd]-} ||
		$cur_git_dir != ${prompt_pure_worker_env[git_dir]-} ||
		$cur_git_work_tree != ${prompt_pure_worker_env[git_work_tree]-} ]]; then
		(( ${#prompt_pure_worker_env_pending} )) && return
		prompt_pure_clear_git_state
		async_flush_jobs "prompt_pure"
		typeset -gi prompt_pure_worker_sync_token
		(( prompt_pure_worker_sync_token++ ))
		local sync_token=$prompt_pure_worker_sync_token
		prompt_pure_worker_env_pending[pwd]=$PWD
		prompt_pure_worker_env_pending[git_dir]=$cur_git_dir
		prompt_pure_worker_env_pending[git_work_tree]=$cur_git_work_tree
		prompt_pure_worker_env_pending[token]=$sync_token
		async_worker_eval "prompt_pure" \
			prompt_pure_async_worker_sync $sync_token "$PWD" ${+GIT_DIR} "${GIT_DIR-}" ${+GIT_WORK_TREE} "${GIT_WORK_TREE-}" || {
				if [[ ${prompt_pure_worker_env_pending[token]-} == $sync_token ]]; then
					typeset -gA prompt_pure_worker_env_pending=()
				fi
				return
			}
		return
	fi

	typeset -gA prompt_pure_vcs_info

	local -H MATCH MBEGIN MEND
	if [[ $PWD != ${prompt_pure_vcs_info[pwd]}* ]]; then
		# Stop any running async jobs.
		async_flush_jobs "prompt_pure"

		# Reset preprompt variables, switching working tree.
		unset prompt_pure_git_dirty
		unset prompt_pure_git_last_dirty_check_timestamp
		unset prompt_pure_git_arrows
		unset prompt_pure_git_stash
		unset prompt_pure_git_fetch_pattern
		prompt_pure_vcs_info[branch]=
		prompt_pure_vcs_info[top]=
	fi
	unset MATCH MBEGIN MEND

	async_job "prompt_pure" prompt_pure_async_vcs_info || return

	# Only perform tasks inside a Git working tree.
	[[ -n $prompt_pure_vcs_info[top] ]] || return

	prompt_pure_async_refresh
}

prompt_pure_async_refresh() {
	setopt localoptions noshwordsplit

	if [[ -z $prompt_pure_git_fetch_pattern ]]; then
		# We set the pattern here to avoid redoing the pattern check until the
		# working tree has changed. Pull and fetch are always valid patterns.
		typeset -g prompt_pure_git_fetch_pattern="pull|fetch"
		async_job "prompt_pure" prompt_pure_async_git_aliases || return
	fi

	async_job "prompt_pure" prompt_pure_async_git_arrows || return

	async_job "prompt_pure" prompt_pure_async_git_tag_and_commit || return

	# Background `git fetch` is disabled by DEFAULT here (upstream defaults it
	# on). It triggered a prompt-redraw bug when cd-ing into some repos, and the
	# accuracy cost is minimal — only the "behind remote" arrow goes stale; the
	# "unpushed" arrow stays correct. Re-enable with `export PURE_GIT_PULL=1`.
	if (( ${PURE_GIT_PULL:-0} )) && [[ $prompt_pure_vcs_info[top] != $HOME ]]; then
		zstyle -t :prompt:pure:git:fetch only_upstream
		local only_upstream=$((? == 0))
		async_job "prompt_pure" prompt_pure_async_git_fetch $only_upstream || return
	fi

	# If dirty checking is sufficiently fast,
	# tell the worker to check it again, or wait for timeout.
	integer time_since_last_dirty_check=$(( EPOCHSECONDS - ${prompt_pure_git_last_dirty_check_timestamp:-0} ))
	if (( time_since_last_dirty_check > ${PURE_GIT_DELAY_DIRTY_CHECK:-1800} )); then
		unset prompt_pure_git_last_dirty_check_timestamp
		# Check if the working tree is dirty.
		zstyle -t ":prompt:pure:git:dirty" detailed
		local detailed_dirty=$((? == 0))
		async_job "prompt_pure" prompt_pure_async_git_dirty ${PURE_GIT_UNTRACKED_DIRTY:-1} $detailed_dirty || return
	fi

	# If stash is enabled, tell async worker to count stashes
	if zstyle -t ":prompt:pure:git:stash" show; then
		async_job "prompt_pure" prompt_pure_async_git_stash || return
	else
		unset prompt_pure_git_stash
	fi
}

prompt_pure_check_git_arrows() {
	setopt localoptions noshwordsplit
	local -a arrows
	local left=${1:-0} right=${2:-0}

	(( right > 0 )) && arrows+=(${PURE_GIT_DOWN_ARROW:-⇣})
	(( left > 0 )) && arrows+=(${PURE_GIT_UP_ARROW:-⇡})

	[[ -n $arrows ]] || return
	# Join with a space so the two glyphs don't overlap when the branch is both
	# ahead and behind.
	typeset -g REPLY="${(j. .)arrows}"
}

prompt_pure_async_callback() {
	setopt localoptions noshwordsplit
	local job=$1 code=$2 output=$3 exec_time=$4 next_pending=$6
	local do_render=0

	if [[ $job != '[async]' ]] &&
		(( ! ${prompt_pure_async_inited:-0} )); then
		return
	fi

	case $job in
		prompt_pure_async_vcs_info|prompt_pure_async_git_aliases|prompt_pure_async_git_dirty|prompt_pure_async_git_fetch|prompt_pure_async_git_arrows|prompt_pure_async_git_stash|prompt_pure_async_git_tag_and_commit)
			[[ ${prompt_pure_worker_env[pwd]-} == $PWD ]] || return
			;;
	esac

	case $job in
		\[async])
			# Handle all the errors that could indicate a crashed
			# async worker. See zsh-async documentation for the
			# definition of the exit codes.
			if (( code == 2 )) || (( code == 3 )) || (( code == 130 )); then
				# Our worker died unexpectedly, try to recover immediately.
				# TODO(mafredri): Do we need to handle next_pending
				#                 and defer the restart?
				typeset -g prompt_pure_async_inited=0
				async_stop_worker prompt_pure
				typeset -gA prompt_pure_worker_env=()
				typeset -gA prompt_pure_worker_env_pending=()
				if prompt_pure_async_init; then
					prompt_pure_async_tasks  # Restart all tasks.
				else
					prompt_pure_clear_git_state
					do_render=1
					next_pending=0
				fi

				# Reset render state due to restart.
				unset prompt_pure_async_render_requested
			fi
			;;
		\[async/eval])
			typeset -gA prompt_pure_worker_env_pending
			local worker_sync_output=${(M)${(f)output}:#prompt_pure_worker_sync:*}
			local -a worker_sync_result
			worker_sync_result=("${(@s.:.)worker_sync_output}")
			if [[ -n $worker_sync_output ]] &&
				(( ${#prompt_pure_worker_env_pending} )); then
				[[ $worker_sync_result[2] == ${prompt_pure_worker_env_pending[token]-} ]] || return
				local worker_sync_status=$worker_sync_result[3]
				if (( worker_sync_status )); then
					prompt_pure_clear_git_state
					do_render=1
					next_pending=0
				else
					typeset -gA prompt_pure_worker_env
					prompt_pure_worker_env[pwd]=$prompt_pure_worker_env_pending[pwd]
					prompt_pure_worker_env[git_dir]=$prompt_pure_worker_env_pending[git_dir]
					prompt_pure_worker_env[git_work_tree]=$prompt_pure_worker_env_pending[git_work_tree]
					typeset -gA prompt_pure_worker_env_pending=()
					prompt_pure_async_tasks
				fi
			elif (( code )); then
				# Looks like async_worker_eval failed,
				# rerun async tasks just in case.
				typeset -gA prompt_pure_worker_env=()
				typeset -gA prompt_pure_worker_env_pending=()
				prompt_pure_clear_git_state
				do_render=1
				next_pending=0
			fi
			;;
		prompt_pure_async_vcs_info)
			local -A info
			typeset -gA prompt_pure_vcs_info

			# Parse output (z) and unquote as array (Q@).
			info=("${(Q@)${(z)output}}")
			local -H MATCH MBEGIN MEND
			if [[ $info[pwd] != $PWD ]]; then
				# The path has changed since the check started, abort.
				return
			fi
			# Check if Git top-level has changed.
			if [[ $info[top] = $prompt_pure_vcs_info[top] ]]; then
				# If the stored pwd is part of $PWD, $PWD is shorter and likelier
				# to be top-level, so we update pwd.
				if [[ $prompt_pure_vcs_info[pwd] = ${PWD}* ]]; then
					prompt_pure_vcs_info[pwd]=$PWD
				fi
			else
				# Store $PWD to detect if we (maybe) left the Git path.
				prompt_pure_vcs_info[pwd]=$PWD
			fi
			unset MATCH MBEGIN MEND

			# The update has a Git top-level set, which means we just entered a new
			# Git directory. Run the async refresh tasks.
			[[ -n $info[top] ]] && [[ -z $prompt_pure_vcs_info[top] ]] && prompt_pure_async_refresh

			# Always update branch, top-level and stash.
			prompt_pure_vcs_info[branch]=$info[branch]
			prompt_pure_vcs_info[top]=$info[top]
			prompt_pure_vcs_info[action]=$info[action]

			do_render=1
			;;
		prompt_pure_async_git_aliases)
			if [[ -n $output ]]; then
				# Append custom Git aliases to the predefined ones.
				prompt_pure_git_fetch_pattern+="|$output"
			fi
			;;
		prompt_pure_async_git_dirty)
			local prev_dirty=$prompt_pure_git_dirty
			if (( code == 0 )); then
				unset prompt_pure_git_dirty
			else
				typeset -g prompt_pure_git_dirty="${output:-*}"
			fi

			[[ $prev_dirty != $prompt_pure_git_dirty ]] && do_render=1

			# When `prompt_pure_git_last_dirty_check_timestamp` is set, the Git info is displayed
			# in a different color. To distinguish between a "fresh" and a "cached" result, the
			# preprompt is rendered before setting this variable. Thus, only upon the next
			# rendering of the preprompt will the result appear in a different color.
			(( $exec_time > 5 )) && prompt_pure_git_last_dirty_check_timestamp=$EPOCHSECONDS
			;;
		prompt_pure_async_git_fetch|prompt_pure_async_git_arrows)
			# `prompt_pure_async_git_fetch` executes `prompt_pure_async_git_arrows`
			# after a successful fetch.
			case $code in
				0)
					local REPLY
					prompt_pure_check_git_arrows ${(ps:\t:)output}
					if [[ $prompt_pure_git_arrows != $REPLY ]]; then
						typeset -g prompt_pure_git_arrows=$REPLY
						do_render=1
					fi
					;;
				97)
					# No remote available, make sure to clear git arrows if set.
					if [[ -n $prompt_pure_git_arrows ]]; then
						typeset -g prompt_pure_git_arrows=
						do_render=1
					fi
					;;
				99|98)
					# Git fetch failed.
					;;
				*)
					# Non-zero exit status from `prompt_pure_async_git_arrows`,
					# indicating that there is no upstream configured.
					if [[ -n $prompt_pure_git_arrows ]]; then
						unset prompt_pure_git_arrows
						do_render=1
					fi
					;;
			esac
			;;
		prompt_pure_async_git_stash)
			local prev_stash=$prompt_pure_git_stash
			typeset -g prompt_pure_git_stash=$output
			[[ $prev_stash != $prompt_pure_git_stash ]] && do_render=1
			;;
		prompt_pure_async_git_tag_and_commit)
			local prev_tag=${prompt_pure_git_tag_and_commit-}
			if (( code == 0 )); then
				typeset -g prompt_pure_git_tag_and_commit=$output
			else
				unset prompt_pure_git_tag_and_commit
			fi
			[[ $prev_tag != ${prompt_pure_git_tag_and_commit-} ]] && do_render=1
			;;
	esac

	if (( next_pending )); then
		(( do_render )) && typeset -g prompt_pure_async_render_requested=1
		return
	fi

	[[ ${prompt_pure_async_render_requested:-$do_render} = 1 ]] && prompt_pure_async_render
	unset prompt_pure_async_render_requested
}

# Set up a self-pipe used to coalesce async-driven prompt redraws. Each async
# callback that wants a repaint pokes the pipe instead of resetting the prompt
# directly; a single `zle -F` watcher drains the pipe and repaints once per
# event-loop turn. This collapses bursts of git results (branch, arrows, tag,
# dirty) that complete within milliseconds of each other into a single redraw,
# which avoids the corruption caused by two `zle reset-prompt` calls landing too
# close together. Safe to call repeatedly; only the first call does the work.
# The fd and watcher persist for the shell's lifetime (freed on exit). Like
# pure's own precmd/preexec hooks they are not torn down on a prompt switch,
# which this single-prompt fork does not use.
prompt_pure_render_init() {
	(( ${prompt_pure_render_inited:-0} )) && return
	(( $+commands[mkfifo] )) || return  # No mkfifo: fall back to direct renders.

	local fifo=${TMPDIR:-/tmp}/prompt-pure-render.$$.$RANDOM
	command rm -f -- $fifo
	command mkfifo -- $fifo || return

	# Open read-write so the fifo always has a writer and never reports EOF.
	if ! exec {prompt_pure_render_fd}<>$fifo; then
		command rm -f -- $fifo
		unset prompt_pure_render_fd
		return
	fi
	command rm -f -- $fifo  # Unlink; the open fd keeps the pipe alive.

	zle -F $prompt_pure_render_fd prompt_pure_render_watcher
	typeset -g prompt_pure_render_inited=1
}

# `zle -F` handler: drains queued render requests and repaints once.
prompt_pure_render_watcher() {
	setopt localoptions noshwordsplit
	local fd=$1 reason=$2

	if [[ -n $reason ]]; then
		# Pipe error (hup/nval/err): drop the watcher and fall back to direct
		# renders from the async callback.
		zle -F $fd
		exec {prompt_pure_render_fd}>&-
		unset prompt_pure_render_fd prompt_pure_render_inited
		return
	fi

	# Drain all queued pokes so a burst collapses into a single repaint. A single
	# sysread reads only one chunk, so loop until the pipe is empty; otherwise
	# leftover bytes would immediately re-trigger the watcher. The -t 0 poll
	# returns non-zero once there is nothing left to read.
	local discard
	while sysread -i $fd -t 0 discard; do : ; done

	prompt_pure_preprompt_render
}

# Request a coalesced repaint. Falls back to an immediate render if the
# self-pipe could not be set up.
prompt_pure_async_render() {
	if [[ -n ${prompt_pure_render_fd-} ]]; then
		print -nu $prompt_pure_render_fd .
	else
		prompt_pure_preprompt_render
	fi
}

prompt_pure_reset_prompt() {
	if [[ $CONTEXT == cont ]]; then
		# When the context is "cont", PS2 is active and calling
		# reset-prompt will have no effect on PS1, but it will
		# reset the execution context (%_) of PS2 which we don't
		# want. Unfortunately, we can't save the output of "%_"
		# either because it is only ever rendered as part of the
		# prompt, expanding in-place won't work.
		return
	fi

	# Force the redisplay to complete before returning. Without this, a second
	# reset arriving a few milliseconds later (a separate async callback) can
	# preempt a half-painted prompt and eat a line. Async-driven renders are
	# additionally coalesced via the self-pipe in prompt_pure_render_init, so in
	# practice only one or two of these flushes happen per command.
	zle && { zle .reset-prompt; zle -R }
}

prompt_pure_reset_prompt_symbol() {
	prompt_pure_state[prompt]=${PURE_PROMPT_SYMBOL:-❯}
}

prompt_pure_update_vim_prompt_widget() {
	setopt localoptions noshwordsplit
	prompt_pure_state[prompt]=${${${KEYMAP/vicmd/${PURE_PROMPT_VICMD_SYMBOL:-❮}}/visual/${PURE_PROMPT_VICMD_SYMBOL:-❮}}/(main|viins)/${PURE_PROMPT_SYMBOL:-❯}}

	prompt_pure_reset_prompt
}

prompt_pure_reset_vim_prompt_widget() {
	setopt localoptions noshwordsplit
	prompt_pure_reset_prompt_symbol

	# We can't perform a prompt reset at this point because it
	# removes the prompt marks inserted by macOS Terminal.
}

prompt_pure_state_setup() {
	setopt localoptions noshwordsplit

	# Check SSH_CONNECTION and the current state.
	local ssh_connection=${SSH_CONNECTION:-$PROMPT_PURE_SSH_CONNECTION}
	local username hostname
	if [[ -z $ssh_connection ]] && (( $+commands[who] )); then
		# When changing user on a remote system, the $SSH_CONNECTION
		# environment variable can be lost. Attempt detection via `who`.
		local who_out
		who_out=$(who -m 2>/dev/null)
		if (( $? )); then
			# Who am I not supported, fallback to plain who.
			local -a who_in
			who_in=( ${(f)"$(who 2>/dev/null)"} )
			who_out="${(M)who_in:#*[[:space:]]${TTY#/dev/}[[:space:]]*}"
		fi

		local reIPv6='(([0-9a-fA-F]+:)|:){2,}[0-9a-fA-F]+'  # Simplified, only checks partial pattern.
		local reIPv4='([0-9]{1,3}\.){3}[0-9]+'   # Simplified, allows invalid ranges.
		# Here we assume two non-consecutive periods represents a
		# hostname. This matches `foo.bar.baz`, but not `foo.bar`.
		local reHostname='([.][^. ]+){2}'

		# Usually the remote address is surrounded by parenthesis, but
		# not on all systems (e.g. busybox).
		local -H MATCH MBEGIN MEND
		if [[ $who_out =~ "\(?($reIPv4|$reIPv6|$reHostname)\)?\$" ]]; then
			ssh_connection=$MATCH

			# Export variable to allow detection propagation inside
			# shells spawned by this one (e.g. tmux does not always
			# inherit the same tty, which breaks detection).
			export PROMPT_PURE_SSH_CONNECTION=$ssh_connection
		fi
		unset MATCH MBEGIN MEND
	fi

	local user_color
	# Show `username@host` if logged in through SSH.
	[[ -n $ssh_connection ]] && user_color=user

	# Show `username@host` if inside a container and not in GitHub Codespaces.
	[[ -z "${CODESPACES}" ]] && prompt_pure_is_inside_container && user_color=user

	# Show `username@host` if root, with username in default color.
	[[ $UID -eq 0 ]] && user_color=user:root

	# Set psvar[13] flag for username display in PROMPT.
	[[ -n $user_color ]] && psvar[13]=1

	# Check if hostname display is enabled (default: yes).
	local show_host=1
	zstyle -T ":prompt:pure:host" show || show_host=0

	typeset -gA prompt_pure_state
	prompt_pure_state[version]="1.28.1"
	prompt_pure_state+=(
		user_color "$user_color"
		show_host  "$show_host"
		prompt	   "${PURE_PROMPT_SYMBOL:-❯}"
	)
}

# Return true if executing inside a Docker, OCI, LXC, or systemd-nspawn container.
prompt_pure_is_inside_container() {
	local -r nspawn_file='/run/host/container-manager'
	local -r podman_crio_file='/run/.containerenv'
	local -r docker_file='/.dockerenv'
	local -r k8s_token_file='/var/run/secrets/kubernetes.io/serviceaccount/token'
	local -r cgroup_file='/proc/1/cgroup'
	[[ "$container" == "lxc" ]] \
		|| [[ "$container" == "oci" ]] \
		|| [[ "$container" == "podman" ]] \
		|| [[ -r "$nspawn_file" ]] \
		|| [[ -r "$podman_crio_file" ]] \
		|| [[ -r "$docker_file" ]] \
		|| [[ -r "$k8s_token_file" ]] \
		|| [[ -r "$cgroup_file" && "$(< $cgroup_file)" = *(lxc|docker|containerd)* ]]
}

prompt_pure_system_report() {
	setopt localoptions noshwordsplit

	local shell=$SHELL
	if [[ -z $shell ]]; then
		shell=$commands[zsh]
	fi
	print - "- Zsh: $($shell --version) ($shell)"
	print -n - "- Operating system: "
	case "$(uname -s)" in
		Darwin)	print "$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))";;
		*)	print "$(uname -s) ($(uname -r) $(uname -v) $(uname -m) $(uname -o))";;
	esac
	print - "- Terminal program: ${TERM_PROGRAM:-unknown} (${TERM_PROGRAM_VERSION:-unknown})"
	print -n - "- Tmux: "
	[[ -n $TMUX ]] && print "yes" || print "no"

	local git_version
	git_version=($(git --version))  # Remove newlines, if hub is present.
	print - "- Git: $git_version"

	print - "- Pure state:"
	for k v in "${(@kv)prompt_pure_state}"; do
		print - "    - $k: \`${(q-)v}\`"
	done
	print - "- zsh-async version: \`${ASYNC_VERSION}\`"
	print - "- PROMPT: \`$(typeset -p PROMPT)\`"
	print - "- Colors: \`$(typeset -p prompt_pure_colors)\`"
	print - "- TERM: \`$(typeset -p TERM)\`"
	print - "- Virtualenv: \`$(typeset -p VIRTUAL_ENV_DISABLE_PROMPT)\`"
	print - "- Conda: \`$(typeset -p CONDA_CHANGEPS1)\`"

	local ohmyzsh=0
	typeset -la frameworks
	(( $+ANTIBODY_HOME )) && frameworks+=("Antibody")
	(( $+ADOTDIR )) && frameworks+=("Antigen")
	(( $+ANTIGEN_HS_HOME )) && frameworks+=("Antigen-hs")
	(( $+functions[upgrade_oh_my_zsh] )) && {
		ohmyzsh=1
		frameworks+=("Oh My Zsh")
	}
	(( $+ZPREZTODIR )) && frameworks+=("Prezto")
	(( $+ZPLUG_ROOT )) && frameworks+=("Zplug")
	(( $+ZPLGM )) && frameworks+=("Zplugin")

	(( $#frameworks == 0 )) && frameworks+=("None")
	print - "- Detected frameworks: ${(j:, :)frameworks}"

	if (( ohmyzsh )); then
		print - "    - Oh My Zsh:"
		print - "        - Plugins: ${(j:, :)plugins}"
	fi
}

prompt_pure_preview() {
	setopt localoptions noshwordsplit

	prompt_pure_set_colors

	local -A c=("${(@kv)prompt_pure_colors}")
	local node_symbol
	zstyle -s ":prompt:pure:environment:node_version" symbol node_symbol || node_symbol='⬢'

	local path_sample="%F{$c[path]}~/dev/pure%f"
	if zstyle -t ':prompt:pure:path:separator' dim; then
		path_sample=$(prompt_pure_render_dimmed_path '~/dev/pure')
	fi

	local host_sample=''
	if zstyle -T ":prompt:pure:host" show; then
		host_sample="%F{$c[host]}@heartofgold%f"
	fi

	# Sample preprompt with all components visible.
	print -P "%F{$c[custom:prefix]}prefix%f %F{$c[suspended_jobs]}${PURE_SUSPENDED_JOBS_SYMBOL-✦}%f %F{$c[user]}zaphod%f${host_sample} ${path_sample} %F{$c[git:branch]}main%f%F{$c[git:dirty]}*%f %F{$c[git:action]}rebase-i%f %F{$c[git:arrow]}${PURE_GIT_DOWN_ARROW:-⇣}${PURE_GIT_UP_ARROW:-⇡}%f %F{$c[git:stash]}${PURE_GIT_STASH_SYMBOL-≡}%f %F{$c[node_version]}${node_symbol}22%f %F{$c[execution_time]}42s%f %F{$c[custom:suffix]}suffix%f"
	print -P "%F{$c[virtualenv]}venv%f %F{$c[prompt:success]}${PURE_PROMPT_SYMBOL:-❯}%f"
	print
	print -P "%F{$c[prompt:error]}${PURE_PROMPT_SYMBOL:-❯}%f  prompt after error"
	print; print
	print -P "%F{$c[git:branch:cached]}main%f  branch color when data is cached"
	print; print
	print -P "%F{$c[user:root]}root%f${host_sample}  root user"
	print; print
	print -P "%F{$c[prompt:continuation]}… if%f %F{$c[prompt:success]}${PURE_PROMPT_SYMBOL:-❯}%f  continuation prompt"
}

prompt_pure_setup() {
	# Prevent percentage showing up if output doesn't end with a newline.
	export PROMPT_EOL_MARK=''

	prompt_opts=(subst percent)

	# Borrowed from `promptinit`. Sets the prompt options in case Pure was not
	# initialized via `promptinit`.
	setopt noprompt{bang,cr,percent,subst} "prompt${^prompt_opts[@]}"

	if [[ -z $prompt_newline ]]; then
		# This variable needs to be set, usually set by promptinit.
		typeset -g prompt_newline=$'\n%{\r%}'
	fi

	zmodload zsh/datetime
	zmodload zsh/zle
	zmodload zsh/parameter
	zmodload zsh/zutil
	zmodload zsh/system  # sysread, used by the render-coalescing watcher

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	# The `add-zle-hook-widget` function is not guaranteed to be available.
	# It was added in Zsh 5.3.
	autoload -Uz +X add-zle-hook-widget 2>/dev/null

	# Set the colors.
	typeset -gA prompt_pure_colors_default prompt_pure_colors
	prompt_pure_colors_default=(
		custom:prefix        242
		custom:suffix        242
		execution_time       yellow
		git:arrow            cyan
		git:stash            cyan
		git:branch           242
		git:branch:cached    red
		git:action           yellow
		git:dirty            218
		host                 242
		node_version         green
		path                 blue
		prompt:error         red
		prompt:success       magenta
		prompt:continuation  242
		suspended_jobs       red
		user                 242
		user:root            default
		virtualenv           242
	)
	prompt_pure_colors=("${(@kv)prompt_pure_colors_default}")

	add-zsh-hook precmd prompt_pure_precmd
	add-zsh-hook preexec prompt_pure_preexec

	prompt_pure_state_setup

	zle -N prompt_pure_reset_prompt
	zle -N prompt_pure_update_vim_prompt_widget
	zle -N prompt_pure_reset_vim_prompt_widget
	if (( $+functions[add-zle-hook-widget] )); then
		add-zle-hook-widget zle-line-finish prompt_pure_reset_vim_prompt_widget
		add-zle-hook-widget zle-keymap-select prompt_pure_update_vim_prompt_widget
	fi

	# Initialize git globals referenced by PROMPT via prompt subst.
	typeset -gA prompt_pure_vcs_info
	typeset -g prompt_pure_git_branch_color=$prompt_pure_colors[git:branch]

	# A two-line, box-drawing prompt built ONCE as a static template. Every
	# dynamic segment is a psvar slot rendered with %(NV.true.false), so empty
	# slots vanish and `zle reset-prompt` always repaints a fixed structure —
	# which is what makes the redraw safe. The renderer only sets psvar values.
	#   psvar 14=branch 15=dirty 16=arrows 17=tag/commit 18=conda 19=kube
	PROMPT='$(prompt_pure_colour_for_exit_code)'$PROMPT_PREFIX_TOP        # top corner (exit-code colour)
	PROMPT+=' %F{12}%~%f'                                                 # path
	PROMPT+='%(18V. %F{242}%18v%f.)'                                      # conda
	PROMPT+='%(19V. %F{242}%19v%f.)'                                      # kube
	PROMPT+='%(14V. %F{${prompt_pure_git_branch_color}}'$''' %14v%(15V.%F{088}%15v.)%f.)'  # branch + dirty
	PROMPT+='%(16V. %F{104}%16v%f.)'                                      # git arrows
	PROMPT+='%(17V. %F{${prompt_pure_git_branch_color}}%17v%f.)'          # git tag + commit
	PROMPT+='${prompt_pure_username}'                                     # user@host (SSH / root)
	PROMPT+=$prompt_newline                                              # newline → command line
	PROMPT+='$(prompt_pure_colour_for_exit_code)'$PROMPT_PREFIX_BOTTOM'%f '  # bottom corner + space

	# Continuation prompt.
	PROMPT2='%F{242}… %(1_.%_ .%_)%f $(prompt_pure_colour_for_exit_code)'$PROMPT_PREFIX_BOTTOM'%f '

	# Store prompt expansion symbols for in-place expansion via (%). For
	# some reason it does not work without storing them in a variable first.
	typeset -ga prompt_pure_debug_depth
	prompt_pure_debug_depth=('%e' '%N' '%x')

	# Compare is used to check if %N equals %x. When they differ, the main
	# prompt is used to allow displaying both filename and function. When
	# they match, we use the secondary prompt to avoid displaying duplicate
	# information.
	local -A ps4_parts
	ps4_parts=(
		depth 	  '%F{yellow}${(l:${(%)prompt_pure_debug_depth[1]}::+:)}%f'
		compare   '${${(%)prompt_pure_debug_depth[2]}:#${(%)prompt_pure_debug_depth[3]}}'
		main      '%F{blue}${${(%)prompt_pure_debug_depth[3]}:t}%f%F{242}:%I%f %F{242}@%f%F{blue}%N%f%F{242}:%i%f'
		secondary '%F{blue}%N%f%F{242}:%i'
		prompt 	  '%F{242}>%f '
	)
	# Combine the parts with conditional logic. First the `:+` operator is
	# used to replace `compare` either with `main` or an empty string. Then
	# the `:-` operator is used so that if `compare` becomes an empty
	# string, it is replaced with `secondary`.
	local ps4_symbols='${${'${ps4_parts[compare]}':+"'${ps4_parts[main]}'"}:-"'${ps4_parts[secondary]}'"}'

	# Improve the debug prompt (PS4), show depth by repeating the +-sign and
	# add colors to highlight essential parts like file and function name.
	PROMPT4="${ps4_parts[depth]} ${ps4_symbols}${ps4_parts[prompt]}"

	# Pure does not use a right-side prompt. Clear RPROMPT to prevent
	# frameworks (e.g. Prezto) from leaking a previous theme's RPROMPT.
	RPROMPT=

	# Guard against Oh My Zsh themes overriding Pure.
	unset ZSH_THEME

	# Guard against (ana)conda changing the PS1 prompt
	# (we manually insert the env when it's available).
	export CONDA_CHANGEPS1=no

	# Guard against pyenv-virtualenv changing the PS1 prompt
	# (we manually insert the env when it's available).
	export PYENV_VIRTUALENV_DISABLE_PROMPT=1

	# Show username@host when on SSH; root in white.
	typeset -g prompt_pure_username=
	[[ -n $SSH_CONNECTION ]] && prompt_pure_username=' %F{242}%n@%m%f'
	[[ $UID -eq 0 ]] && prompt_pure_username=' %F{white}%n%f%F{242}@%m%f'

	# Custom git arrow glyphs (consumed by prompt_pure_check_git_arrows).
	: ${PURE_GIT_DOWN_ARROW=$''}
	: ${PURE_GIT_UP_ARROW=$''}

	# Override accept-line so each executed command line carries a timestamp.
	zle -N accept-line prompt_pure_accept_line
}

prompt_pure_setup "$@"

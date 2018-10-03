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

PROMPT_PREFIX_TOP='╭─'
PROMPT_PREFIX_BOTTOM='╰─'
RPROMPT_LINE_UP='%{'$'\e[1A''%}' # one line up
RPROMPT_LINE_DOWN='%{'$'\e[1B''%}' # one line down

export VIRTUAL_ENV_DISABLE_PROMPT=1

# turns seconds into human readable time
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
prompt_pure_human_time_to_var() {
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

prompt_pure_check_cmd_exec_time() {
	integer elapsed
	(( elapsed = EPOCHREALTIME - ${prompt_pure_last_cmd_timestamp:-$EPOCHREALTIME} ))
	(( elapsed > ${PURE_CMD_MAX_EXEC_TIME:-2} )) && {
		print -- "$(prompt_pure_human_time_to_var $elapsed)"
	}
}

prompt_pure_set_title() {
	setopt localoptions noshwordsplit

	# emacs terminal does not support settings the title
	(( ${+EMACS} )) && return

	case $TTY in
		# Don't set title over serial console.
		/dev/ttyS[0-9]*) return;;
	esac

	if [[ $1 != "restore" ]]; then
		prompt_pure_debug_output "Setting terminal title to: $2"
		# Store current title
		print -n '\033[22;0t'
		# tell the terminal we are setting the title
		print -n '\e]0;'
		# show hostname if connected through ssh
		[[ -n $SSH_CONNECTION ]] && print -Pn '(%m) '
		case $1 in
			expand-prompt)
				print -Pn $2;;
			ignore-escape)
				print -rn $2;;
			restore)
		esac
		# end set title
		print -n '\a'
	else
		prompt_pure_debug_output "Restoring previous terminal title"
		print -n '\033[23;0t'
	fi
	prompt_pure_debug_output "prompt_pure_set_title done"
}

prompt_pure_accept_line() {
	prompt_pure_debug_output "Handling accept-line"

	typeset -g prompt_pure_last_cmd_timestamp=$EPOCHREALTIME

	# Re-render prompt, now with timestamp
	typeset -g prompt_pure_show_timestamp=true
	prompt_pure_preprompt_render
	typeset -g prompt_pure_show_timestamp=

	# Run original handler
	zle && zle .accept-line
	prompt_pure_debug_output "Ran accept-line widget: $?"
}

prompt_pure_preexec() {
	prompt_pure_debug_output "Handling preexec"

	if [[ -n $prompt_pure_git_fetch_pattern ]]; then
		# detect when git is performing pull/fetch (including git aliases).
		local -H MATCH MBEGIN MEND match mbegin mend
		if [[ $2 =~ (git|hub)\ (.*\ )?($prompt_pure_git_fetch_pattern)(\ .*)?$ ]]; then
			# we must flush the async jobs to cancel our git fetch in order
			# to avoid conflicts with the user issued pull / fetch.
			async_flush_jobs 'prompt_pure'
		fi
	fi

	# shows the current dir and executed command in the title while a process is active
	if [[ $2 != set-tab-title* ]]; then
		prompt_pure_set_title 'ignore-escape' "$2"
	fi
}

# string length ignoring ansi escapes
prompt_pure_string_length_to_var() {
	local str=$1 var=$2 length
	# perform expansion on str and check length
	length=$(( ${#${(S%%)str//(\%([KF1]|)\{*\}|\%[Bbkf])}} ))

	# store string length in variable as specified by caller
	typeset -g "${var}"="${length}"
}

prompt_pure_colour_for_exit_code() {
	# Ignore spurious `git log` exit code of 141. (Reasonably unlikely to be seen elsewhere,
	# so can't be bothered to check if that was the command executed.)
	print -n '%(141?.%F{white}.%(?.%F{white}.%F{red}))'
}

prompt_pure_preprompt_render() {
	setopt localoptions noshwordsplit

	prompt_pure_debug_output "Rendering$([[ -n $1 ]] && echo ' for '$1)"

	# Set color for git branch/dirty status, change color if dirty checking has
	# been delayed.
	local git_color=101 #242
	[[ -n ${prompt_pure_git_last_dirty_check_timestamp+x} ]] && git_color=red

	# Initialize the preprompt array.
	local -a preprompt_parts
	local -a preprompt_r_parts

	preprompt_parts+=('$(prompt_pure_colour_for_exit_code)'$PROMPT_PREFIX_TOP)

	# Set the path.
	preprompt_parts+=('%F{12}%~%f')

	# if a virtualenv is activated, display it in grey
	local _conda=$CONDA_ENV_PATH$CONDA_PREFIX
	if [[ ! -z "$_conda" && $CONDA_PREFIX =~ .+/envs/.+ ]]; then
		preprompt_parts+=('%F{242}'$(print -- "\UE73C ")$(basename $_conda)'%f')
	fi

	# Add git branch and dirty status info.
	typeset -gA prompt_pure_vcs_info
	if [[ -n $prompt_pure_vcs_info[branch] ]]; then
		preprompt_parts+=("%F{088}${prompt_pure_git_dirty}%F{$git_color}"$(print -- "\uF126")' ${prompt_pure_vcs_info[branch]}%f')
	fi
	# Git pull/push arrows.
	if [[ -n $prompt_pure_git_arrows ]]; then
		preprompt_parts+=('%F{104}${prompt_pure_git_arrows}%f')
	fi
	# Git tag info.
	if [[ -n prompt_pure_git_tag_and_commit ]]; then
		preprompt_parts+=("%F{$git_color}"'${prompt_pure_git_tag_and_commit}%f')
	fi

	# Username and machine, if applicable.
	[[ -n $prompt_pure_username ]] && preprompt_parts+=('$prompt_pure_username')

	# Timestamp.
	if [[ $prompt_pure_show_timestamp == true ]]; then
		local timestamp_str=$(command date --date="@$prompt_pure_last_cmd_timestamp" +' %a %H:%M:%S')
		preprompt_r_parts+=(" %F{242}$(print -- \\uF017$timestamp_str)%f")
	fi

	local cleaned_ps1=$PROMPT
	local -H MATCH MBEGIN MEND
	if [[ $PROMPT = *$prompt_newline* ]]; then
		# When the prompt contains newlines, we keep everything before the first
		# and after the last newline, leaving us with everything except the
		# preprompt. This is needed because some software prefixes the prompt
		# (e.g. virtualenv).
		cleaned_ps1=${PROMPT%%${prompt_newline}*}${PROMPT##*${prompt_newline}}
	fi
	unset MATCH MBEGIN MEND

	# Construct the new prompt with a clean preprompt.
	local -ah ps1
	ps1=(
		$prompt_newline           # Initial newline, for spaciousness.
		${(j. .)preprompt_parts}  # Join parts, space separated.
		$prompt_newline           # Separate preprompt and prompt.
		$cleaned_ps1
	)

	PROMPT="${(j..)ps1}"

	if [[ -n $preprompt_r_parts ]]; then
		preprompt_r_parts=("$RPROMPT_LINE_UP" "${preprompt_r_parts[@]}" "$RPROMPT_LINE_DOWN")
		RPROMPT="${(j..)preprompt_r_parts}"
	else
		RPROMPT=''
	fi

	# Expand the prompt for future comparision.
	local expanded_prompt
	expanded_prompt="${(S%%)PROMPT}${(S%%)RPROMPT}"

	if [[ $1 != precmd ]] && [[ $prompt_pure_last_prompt != $expanded_prompt ]]; then
		prompt_pure_debug_output "Redrawing prompt"
		zle && zle .reset-prompt
		prompt_pure_debug_output "Ran reset-prompt widget: $?"
	fi

	typeset -g prompt_pure_last_prompt=$expanded_prompt

	prompt_pure_debug_output "Rendering complete"
}

prompt_pure_precmd() {
	prompt_pure_debug_output "Handling precmd"

	# check exec time and store it in a variable
	elapsed=$(prompt_pure_check_cmd_exec_time)
	[[ -n $elapsed ]] && print -P -- "%F{088}\\uF252 $elapsed%f"

	prompt_pure_set_title "restore"

	# preform async git dirty check and fetch
	prompt_pure_async_tasks

	# print the preprompt
	prompt_pure_preprompt_render "precmd"
}

prompt_pure_async_git_aliases() {
	setopt localoptions noshwordsplit
	local dir=$1
	local -a gitalias pullalias

	# we enter repo to get local aliases as well.
	builtin cd -q $dir

	# list all aliases and split on newline.
	gitalias=(${(@f)"$(command git config --get-regexp "^alias\.")"})
	for line in $gitalias; do
		parts=(${(@)=line})           # split line on spaces
		aliasname=${parts[1]#alias.}  # grab the name (alias.[name])
		shift parts                   # remove aliasname

		# check alias for pull or fetch (must be exact match).
		if [[ $parts =~ ^(.*\ )?(pull|fetch)(\ .*)?$ ]]; then
			pullalias+=($aliasname)
		fi
	done

	print -- ${(j:|:)pullalias}  # join on pipe (for use in regex).
}

prompt_pure_async_vcs_info() {
	setopt localoptions noshwordsplit
	builtin cd -q $1 2>/dev/null

	# configure vcs_info inside async task, this frees up vcs_info
	# to be used or configured as the user pleases.
	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	# only export two msg variables from vcs_info
	zstyle ':vcs_info:*' max-exports 2
	# export branch (%b) and git toplevel (%R)
	zstyle ':vcs_info:git*' formats '%b' '%R'
	zstyle ':vcs_info:git*' actionformats '%b|%a' '%R'

	vcs_info

	local -A info
	info[top]=$vcs_info_msg_1_
	info[branch]=$vcs_info_msg_0_

	print -r - ${(@kvq)info}
}

# fastest possible way to check if repo is dirty
prompt_pure_async_git_dirty() {
	setopt localoptions noshwordsplit
	local untracked_dirty=$1 dir=$2

	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q $dir

	if [[ $untracked_dirty = 0 ]]; then
		command git diff --no-ext-diff --quiet --exit-code
	else
		test -z "$(command git status --porcelain --ignore-submodules -unormal)"
	fi

	return $?
}

prompt_pure_debug_output() {
	#echo -e "$(command date +"%Y-%m-%dT%H:%M:%S") $1" >>~/my_prompt.log
}

#prompt_pure_is_bluetooth_network_connection() {
#	services=$(networksetup -listnetworkserviceorder | grep 'Hardware Port')
#
#	while read line; do
#		sname=$(echo $line | awk -F  "(, )|(: )|[)]" '{print $2}')
#		sdev=$(echo $line | awk -F  "(, )|(: )|[)]" '{print $4}')
#		if [ -n "$sdev" ]; then
#			ifout="$(ifconfig $sdev 2>/dev/null)"
#			echo "$ifout" | grep 'status: active' > /dev/null 2>&1
#			rc="$?"
#			if [ "$rc" -eq 0 ]; then
#				currentservice="$sname"
#				currentdevice="$sdev"
#				currentmac=$(echo "$ifout" | awk '/ether/{print $2}')
#			fi
#		fi
#	done <<< "$(echo "$services")"
#
#	prompt_pure_debug_output "Current service is ${currentservice:-?}"
#	if [ -n "$currentservice" ]; then
#		if [[ $currentservice == *Bluetooth* ]]; then
#			return 0
#		fi
#	fi
#	return 1
#}
#
#prompt_pure_async_git_fetch() {
#	setopt localoptions noshwordsplit
#	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
#	builtin cd -q $1
#
#	if prompt_pure_is_bluetooth_network_connection; then
#		prompt_pure_debug_output "Skipping fetch; on bluetooth"
#		return 99
#	fi
#	prompt_pure_debug_output "Allowing fetch; not on bluetooth"
#
#	# set GIT_TERMINAL_PROMPT=0 to disable auth prompting for git fetch (git 2.3+)
#	export GIT_TERMINAL_PROMPT=0
#	# set ssh BachMode to disable all interactive ssh password prompting
#	export GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-"ssh -o BatchMode=yes"}
#
#	command git -c gc.auto=0 fetch &>/dev/null || return 99
#
#	# check arrow status after a successful git fetch
#	prompt_pure_async_git_arrows $1
#}

prompt_pure_async_git_arrows() {
	setopt localoptions noshwordsplit
	builtin cd -q $1
	command git rev-list --left-right --count HEAD...@'{u}'
}

prompt_pure_async_git_tag_and_commit() {
	setopt localoptions noshwordsplit

	builtin cd -q $1

	local tag=$(command git describe --tags --exact-match HEAD 2>/dev/null)
	if [[ -n "${tag}" ]] ; then
		tag="\uF02B ${tag} "
	fi

	print -- "${tag}\uE729 $(command git rev-parse --short=8 HEAD 2>/dev/null)"
}

prompt_pure_reset_async_state() {
	reset_all=${1:-false}

	unset prompt_pure_git_dirty
	unset prompt_pure_git_arrows
	unset prompt_pure_git_tag_and_commit
	prompt_pure_vcs_info[branch]=
	prompt_pure_vcs_info[top]=

	if [[ $reset_all == true ]]; then
		unset prompt_pure_git_last_dirty_check_timestamp
		unset prompt_pure_git_fetch_pattern
	fi
}

prompt_pure_async_tasks() {
	setopt localoptions noshwordsplit

	# initialize async worker
	((!${prompt_pure_async_init:-0})) && {
		async_start_worker "prompt_pure" -u -n
		async_register_callback "prompt_pure" prompt_pure_async_callback
		typeset -g prompt_pure_async_init=1
	}

	typeset -gA prompt_pure_vcs_info

	local -H MATCH MBEGIN MEND
	if ! [[ $PWD = ${prompt_pure_vcs_info[pwd]}* ]]; then
		async_flush_jobs "prompt_pure"
		prompt_pure_reset_async_state true
	fi
	unset MATCH MBEGIN MEND

	async_job "prompt_pure" prompt_pure_async_vcs_info $PWD

	# # only perform tasks inside git working tree
	[[ -n $prompt_pure_vcs_info[top] ]] || return

	prompt_pure_async_refresh
}

prompt_pure_async_refresh() {
	setopt localoptions noshwordsplit

	#if [[ -z $prompt_pure_git_fetch_pattern ]]; then
	#	# we set the pattern here to avoid redoing the pattern check until the
	#	# working three has changed. pull and fetch are always valid patterns.
	#	typeset -g prompt_pure_git_fetch_pattern="pull|fetch"
	#	async_job "prompt_pure" prompt_pure_async_git_aliases $working_tree
	#fi

	async_job "prompt_pure" prompt_pure_async_git_arrows $PWD
	async_job "prompt_pure" prompt_pure_async_git_tag_and_commit $PWD

	## do not preform git fetch if it is disabled or working_tree == HOME
	#if (( ${PURE_GIT_PULL:-1} )) && [[ $working_tree != $HOME ]]; then
	#	# tell worker to do a git fetch
	#	async_job "prompt_pure" prompt_pure_async_git_fetch $PWD
	#fi

	# if dirty checking is sufficiently fast, tell worker to check it again, or wait for timeout
	integer time_since_last_dirty_check=$(( EPOCHSECONDS - ${prompt_pure_git_last_dirty_check_timestamp:-0} ))
	if (( time_since_last_dirty_check > ${PURE_GIT_DELAY_DIRTY_CHECK:-1800} )); then
		unset prompt_pure_git_last_dirty_check_timestamp
		# check check if there is anything to pull
		async_job "prompt_pure" prompt_pure_async_git_dirty ${PURE_GIT_UNTRACKED_DIRTY:-1} $PWD
	fi
}

prompt_pure_print_all_colours() {
	for code in {000..255}; do
		print -P -- "%F{$code}$code%{$reset_color%}"
	done
}

prompt_pure_check_git_arrows() {
	setopt localoptions noshwordsplit
	local -a arrows
	local left=${1:-0} right=${2:-0}

	(( right > 0 )) && arrows+=(${PURE_GIT_DOWN_ARROW:-$(print -- "\uF01A")})
	(( left > 0 )) && arrows+=(${PURE_GIT_UP_ARROW:-$(print -- "\uF01B")})

	[[ -n $arrows ]] || return
	typeset -g REPLY=${(j. .)arrows}
}

prompt_pure_async_callback() {
	setopt localoptions noshwordsplit
	local job=$1 code=$2 output=$3 exec_time=$4 next_pending=$6
	local do_render=0

	case $job in
		prompt_pure_async_vcs_info)
			local -A info
			typeset -gA prompt_pure_vcs_info

			# parse output (z) and unquote as array (Q@)
			info=("${(Q@)${(z)output}}")
			local -H MATCH MBEGIN MEND
			# check if git toplevel has changed
			if [[ $info[top] = $prompt_pure_vcs_info[top] ]]; then
				# if stored pwd is part of $PWD, $PWD is shorter and likelier
				# to be toplevel, so we update pwd
				if [[ $prompt_pure_vcs_info[pwd] = ${PWD}* ]]; then
					prompt_pure_vcs_info[pwd]=$PWD
				fi
			else
				# store $PWD to detect if we (maybe) left the git path
				prompt_pure_vcs_info[pwd]=$PWD
			fi
			unset MATCH MBEGIN MEND

			# update has a git toplevel set which means we just entered a new
			# git directory, run the async refresh tasks
			[[ -n $info[top] ]] && [[ -z $prompt_pure_vcs_info[top] ]] && prompt_pure_reset_async_state && prompt_pure_async_refresh

			# always update branch and toplevel
			prompt_pure_vcs_info[branch]=$info[branch]
			prompt_pure_vcs_info[top]=$info[top]

			do_render=1
			;;
		prompt_pure_async_git_aliases)
			if [[ -n $output ]]; then
				# append custom git aliases to the predefined ones.
				prompt_pure_git_fetch_pattern+="|$output"
			fi
			;;
		prompt_pure_async_git_dirty)
			local prev_dirty=$prompt_pure_git_dirty
			if (( code == 0 )); then
				unset prompt_pure_git_dirty
			else
				typeset -g prompt_pure_git_dirty="* "
			fi

			[[ $prev_dirty != $prompt_pure_git_dirty ]] && do_render=1

			# When prompt_pure_git_last_dirty_check_timestamp is set, the git info is displayed in a different color.
			# To distinguish between a "fresh" and a "cached" result, the preprompt is rendered before setting this
			# variable. Thus, only upon next rendering of the preprompt will the result appear in a different color.
			(( $exec_time > 5 )) && prompt_pure_git_last_dirty_check_timestamp=$EPOCHSECONDS
			;;
		prompt_pure_async_git_fetch|prompt_pure_async_git_arrows)
			# prompt_pure_async_git_fetch executes prompt_pure_async_git_arrows
			# after a successful fetch.
			if (( code == 0 )); then
				local REPLY
				prompt_pure_check_git_arrows ${(ps:\t:)output}
				if [[ $prompt_pure_git_arrows != $REPLY ]]; then
					prompt_pure_debug_output "New git arrows: $REPLY"
					typeset -g prompt_pure_git_arrows=$REPLY
					do_render=1
				fi
			elif (( code != 99 )); then
				# Unless the exit code is 99, prompt_pure_async_git_arrows
				# failed with a non-zero exit status, meaning there is no
				# upstream configured.
				prompt_pure_debug_output "Git arrows failed with $code"
				if [[ -n $prompt_pure_git_arrows ]]; then
					unset prompt_pure_git_arrows
					do_render=1
				fi
			fi
			;;
		prompt_pure_async_git_tag_and_commit)
			if (( code == 0 )); then
				typeset -g prompt_pure_git_tag_and_commit=$output
			else
				unset prompt_pure_git_tag_and_commit
			fi
			do_render=1
			;;
	esac

	if (( next_pending )); then
		(( do_render )) && typeset -g prompt_pure_async_render_requested=1
		return
	fi

	[[ ${prompt_pure_async_render_requested:-$do_render} = 1 ]] && prompt_pure_preprompt_render "async"
	unset prompt_pure_async_render_requested
}

prompt_pure_setup() {
	# Prevent percentage showing up if output doesn't end with a newline.
	export PROMPT_EOL_MARK=''

	prompt_opts=(subst percent)

	# borrowed from promptinit, sets the prompt options in case pure was not
	# initialized via promptinit.
	setopt noprompt{bang,cr,percent,subst} "prompt${^prompt_opts[@]}"

	if [[ -z $prompt_newline ]]; then
		# This variable needs to be set, usually set by promptinit.
		typeset -g prompt_newline=$'\n%{\r%}'
	fi

	zmodload zsh/datetime
	zmodload zsh/zle
	zmodload zsh/parameter

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	add-zsh-hook precmd prompt_pure_precmd
	add-zsh-hook preexec prompt_pure_preexec

	# show username@host if logged in through SSH
	[[ "$SSH_CONNECTION" != '' ]] && prompt_pure_username='%F{242}%n@%m%f'

	# show username@host if root, with username in white
	[[ $UID -eq 0 ]] && prompt_pure_username='%F{white}%n%f%F{242}@%m%f'

	PROMPT='$(prompt_pure_colour_for_exit_code)'$PROMPT_PREFIX_BOTTOM'%f '

	# Override enter behaviour so that we can modify the existing prompt before each command is run
	zle -N accept-line prompt_pure_accept_line
}

prompt_pure_setup "$@"

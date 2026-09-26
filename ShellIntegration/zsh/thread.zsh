# Source explicitly from an interactive zsh after setting THREAD_SHELL_SENDER.
# No command strings, shell history, terminal output, or environment dump is collected.
[[ -o interactive ]] || return 0
[[ -n ${_THREAD_HOOK_INSTALLED:-} ]] && return 0
[[ -x ${THREAD_SHELL_SENDER:-} ]] || return 0

typeset -g _THREAD_HOOK_INSTALLED=1
typeset -g _THREAD_SESSION_ID="$(/usr/bin/uuidgen)"
typeset -gi _THREAD_SEQUENCE=0

_thread_emit() {
    local kind="$1" completion="$2"
    (( ++_THREAD_SEQUENCE ))
    "$THREAD_SHELL_SENDER" "$kind" "$_THREAD_SESSION_ID" "$$" "$_THREAD_SEQUENCE"         "$PWD" "${TERM_PROGRAM:-}" "$completion" >/dev/null 2>&1
    return 0
}
_thread_precmd() { local completion=$?; _thread_emit completed "$completion"; return 0; }
_thread_chpwd() { _thread_emit directory 0; }
_thread_exit() { _thread_emit ended 0; }

autoload -Uz add-zsh-hook
add-zsh-hook precmd _thread_precmd
add-zsh-hook chpwd _thread_chpwd
add-zsh-hook zshexit _thread_exit
_thread_emit directory 0

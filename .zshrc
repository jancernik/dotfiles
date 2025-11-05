export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export ZSH="$HOME/.oh-my-zsh"

zstyle ':omz:update' mode auto

ZSH_THEME="robbyrussell"

plugins=(z fzf-tab sudo zsh-autosuggestions zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh
source <(fzf --zsh)

if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='nano'
else
  export EDITOR='micro'
fi

eval "$(oh-my-posh init zsh --config ~/.config/ohmyposh/theme.toml)"

ZSH_HIGHLIGHT_STYLES[command]='none'
ZSH_HIGHLIGHT_STYLES[alias]='none'
ZSH_HIGHLIGHT_STYLES[builtin]='none'
ZSH_HIGHLIGHT_STYLES[function]='none'
ZSH_HIGHLIGHT_STYLES[precommand]='none'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=8'

alias i="yay -S"
alias b="~/.scripts/brightness.sh"
alias m="~/.scripts/monitor-backlight.sh"
alias vpn="~/.scripts/vpn.sh"
alias r="trash-put"
alias cat="bat --plain --paging=never"
alias cl="printf '\033[2J\033[3J\033[1;1H'"

alias f='fzf --multi --style full --preview "
if file --mime-type {} | grep -qF image/; then
  kitty icat --clear --transfer-mode=memory --stdin=no --place=\${FZF_PREVIEW_COLUMNS}x\${FZF_PREVIEW_LINES}@0x0 {}
else
  printf \"\x1b_Ga=d,d=A\x1b\\\\\"
  bat --color=always --style=numbers {}
fi
"'

export FZF_DEFAULT_COMMAND='ag --hidden --ignore .git -l -g ""'

export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# pnpm
export PNPM_HOME="/home/jan/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

## [Completion]
## Completion scripts setup. Remove the following line to uninstall
[[ -f /home/jan/.config/.dart-cli-completion/zsh-config.zsh ]] && . /home/jan/.config/.dart-cli-completion/zsh-config.zsh || true
## [/Completion]

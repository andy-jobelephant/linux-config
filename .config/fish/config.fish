string match -q "$TERM_PROGRAM" "vscode" and . (code --locate-shell-integration-path fish)
if status is-interactive
    load_nvm > /dev/stderr
    # Commands to run in interactive sessions can go here
end
bind \b backward-kill-word
bind \e\[3\;5~ kill-word

set -x GOROOT /usr/local/go
set -x GOPATH $HOME/go
fish_add_path $GOPATH/bin
fish_add_path $GOROOT/bin
fish_add_path /usr/bin/yazi
fish_add_path /usr/bin/k9s
fish_add_path /usr/bin/helm-dashboard
fish_add_path /home/andy/repos/je-wordpress-utils
fish_add_path /usr/local/bin/mkcert

eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

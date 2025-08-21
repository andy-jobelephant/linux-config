function dotadd
    git --git-dir=$HOME/.cfg --work-tree=$HOME add $argv
    # git --git-dir=$HOME/.cfg --work-tree=$HOME commit -m "Track $argv"
end
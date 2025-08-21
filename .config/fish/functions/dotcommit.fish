function dotcommit
    git --git-dir=$HOME/.cfg --work-tree=$HOME commit -m "Track $argv" --allow-empty
end
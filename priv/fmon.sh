#!/usr/bin/env bash
# =============================================================================
# @doc (very) Simple (continous) Files Monitor
# @author Damian T. Dobroczy\\'nski <qoocku@gmail.com>
# @since 2011-04-11 
# =============================================================================

# function getting answer on question
function ask {
    answer=qoopa
    while [ "$answer" != "$2" -a "$answer" != "$3" ] ; do
        echo -n $1
        read answer
    done
    return $answer
}

# get arguments
while [ "$1" != "" ] ; do
    case "$1" in
        --command) var=command ;;
        --args) var=args ;;
        --files) var=files ;;
        *) eval x=\$$var
           eval "$var=\"$1 $x\""
    esac
    shift
done

echo "fmon> running $command $args iff some change happens in/to $files"

# get files & directories to watch
to_watch=
for f in $files ; do
    if [ -f $f -o -d $f ]; then
        to_watch="$to_watch $f"
    else # if there's no such file ask for permission to create it
        ask "fmon> there's no $f file/directory. create it? [y/n]:" y n
        if [ "$answer" == "y" ] ; then
            ask "fmon> should it be file or directory? [f/d]:" f d
            if [ "$answer" == "f" ] ; then
                touch $f
            else
                mkdir -p $f
            fi
            to_watch="$to_watch $f"
        else
            echo "fmon> so, i'm omitting this entry"
        fi
    fi
done

while true ; do
    echo '---------------------- test run ----------------------'
    $command $args
    echo
    echo
    echo '----------------- waiting for change -----------------'
    EVENT=$(inotifywait -r -e close_write --format '%e' $to_watch)
done
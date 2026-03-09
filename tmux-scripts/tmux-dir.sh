#!/bin/sh
# Returns last 2 path components (matches starship truncation_length=2)
p=$(echo "$1" | sed "s|^$HOME|~|")
echo "$p" | awk -F'/' '{n=NF; if(n>=2) print $(n-1)"/"$n; else print $n}'

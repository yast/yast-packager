#!/bin/bash

unset Y2DEBUG
unset Y2DEBUGGER

RUNAG="./runag_targetpkg"

if [ ! -x "$RUNAG" ]; then
	if [ -x ".$RUNAG" ]; then
		RUNAG=".$RUNAG"
	else
		echo "Can't find $(basename $RUNAG) in . or .." >&2
		exit 1
	fi
fi

($RUNAG -l - $1 >$2) 2>&1 \
	| fgrep -v " <0> " \
	| grep -v "^$" \
	| sed 's/^....-..-.. ..:..:.. [^)]*) //g' \
	> $3

#!/bin/bash

export Y2DEBUG=1
unset Y2DEBUGGER
(./runag_package $1 >$2) 2>&1 | fgrep -v " <0> " | grep -v "^$" | sed 's/^....-..-.. ..:..:.. [^)]*) //g' > $3

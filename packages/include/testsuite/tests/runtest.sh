#! /bin/bash
#echo XXXXXXXXXXXXXXXXXXXXXXXXXX/$1/$2/$3 /$4/X
echo $2 > xyzzy
(/usr/lib/YaST2/bin/y2bignfat -l - $1 -f xyzzy testsuite > $3) 2>&1 | fgrep -v " <0> " | grep -v "^$" | sed 's/^....-..-.. ..:..:.. [^)]*) //g' > $4
#(/usr/lib/YaST2/bin/y2bignfat -l /dev/fd/1 $1 -f xyzzy testsuite 2>&1 ) | grep "OUT:" | grep -v "^$" | sed 's/^....-..-.. ..:..:.. [^)]*).*OUT:/  /g' >"$3" 2>"$4"
rm xyzzy

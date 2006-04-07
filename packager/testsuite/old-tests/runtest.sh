#! /bin/bash
(/usr/lib/YaST2/bin/y2bignfat -l /dev/fd/2 $1 qt >$3)  2>&1  | grep "dejagnu" | sed 's/^....-..-.. ..:..:.. [^)]*)[^:]*:[1234567890]* //g' > $2

#! /bin/bash
echo start test
( cd ..;  tests/runtest.sh tests/$1 tests/tmp.out tests/tmp.err); cat tmp.out  tmp.err 
echo "test ended, look at tmp.out tmp.err"

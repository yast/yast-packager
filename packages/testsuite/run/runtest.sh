#! /bin/bash

# Run test on one ycp file
#
# $1 = script.ycp
# $2 = stdout
# $3 = stderr
#
# $Id$

export Y2DEBUG=1
export Y2DEBUGALL=1

export PATH="$PATH:/usr/lib/YaST2/bin"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/YaST2/lib"

parse() {
  file="`mktemp /tmp/yast2-test.XXXXXX`"
  cat >$file
  if [ -z "$Y2TESTSUITE" ]; then
    sed1="s/ <[2-5]> [^ ]\+ \[YCP\] [^ ]\+ / <0> host [YCP] file LoGlOg=/"
    sed2="s/\[bash\]\( stdout[^ ]\+ \)/\[bash_stdout\]\1File	/"
    components="\[ag_dummy\]|\[bash_stdout\]"
    ycp="\[YCP\].*(rEaL_rEt=|aNY_OutPuT=|LoGlOg=)"
    cat "$file" | grep -v "checkPath" | sed "$sed1" |sed "$sed2"| grep -E "<[012]>[^\[]*($ycp|$components)" | cut -d" " -f7- | sed -e 's/rEaL_rEt=/Return	/' | sed -e 's/aNY_OutPuT=/Dump	/' | sed -e 's/LoGlOg=/Log	/'
    cat "$file" | grep "<[345]>" | grep -v "\[YCP\]" >&2
  else
    echo "Y2TESTSUITE set to \"$Y2TESTSUITE\""
    echo
    cat "$file"
  fi
  rm -f "$file"
}

( y2bignfat -l /dev/fd/1 "$1" scr 2>&1 ) | parse >"$2" 2>"$3"
#( y2bignfat "$1" qt 2>&1 ) | parse >"$2" 2>"$3"

retcode="$PIPESTATUS"
if [ "$retcode" -ge 128 ]; then
  sig=$[$retcode-128]
  echo -ne "\nCommand terminated on signal '$sig'"
  echo -e '!\n'
fi

# EOF

#! /bin/bash

# Run test on one ycp file
# Michal Svec <msvec@suse.cz>
#
# $1 = script.ycp
# $2 = stdout
# $3 = stderr
#
# $Id$

unset LANG
unset LC_CTYPE
unset LC_NUMERIC
unset LC_TIME
unset LC_COLLATE
unset LC_MONETARY
unset LC_MESSAGES
unset LC_PAPER
unset LC_NAME
unset LC_ADDRESS
unset LC_TELEPHONE
unset LC_MEASUREMENT
unset LC_IDENTIFICATION
unset LC_ALL

export Y2DEBUG=1
export Y2DEBUGALL=1

export PATH="$PATH:/usr/lib/YaST2/bin"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/YaST2/lib"

parse() {
  file="`mktemp /tmp/yast2-test.XXXXXX`"
  cat >"$file"
  if [ -z "$Y2TESTSUITE" ]; then
    sed1="s/ <[2-5]> [^ ]\+ \[YCP\] [^ ]\+ / <0> host [YCP] file LoGlOg=/"
    components="\[ag_dummy\]|\[bash\]"
    ycp="\[YCP\].*(rEaL_rEt=|aNY_OutPuT=|LoGlOg=|fIlE_OutPuT=)"
    cat "$file" | grep -v "checkPath" | grep -v "Exit status is " | sed "$sed1" |grep -E "<[012]>[^\[]*($ycp|$components)" | cut -d" " -f7- | sed -e 's/rEaL_rEt=/Return	/' | sed -e 's/aNY_OutPuT=/Dump	/' | sed -e 's/fIlE_OutPuT=/File	/' | sed -e 's/LoGlOg=/Log	/'
    cat "$file" | grep "<[345]>" | grep -v "\[YCP\]" >&2
  else
    echo "Y2TESTSUITE set to \"$Y2TESTSUITE\""
    echo
    cat "$file"
  fi
  rm -f "$file"
}

( y2bignfat -l /dev/fd/1 "$1" scr 2>&1 ) | parse >"$2" 2>"$3"

retcode="$PIPESTATUS"
if [ "$retcode" -ge 128 ]; then
  sig=$[$retcode-128]
  echo -ne "\nCommand terminated on signal '$sig'"
  echo -e '!\n'
fi

exit "$retcode"
# EOF

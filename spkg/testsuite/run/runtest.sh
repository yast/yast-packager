#! /bin/bash
export PATH="$PATH:/usr/lib/YaST2/bin"
export PATH="$PATH:/usr/lib/YaST2/clients"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/YaST2/lib"
export Y2DEBUG=1

# $1 = script.ycp
# $2 = stdout
# $3 = stderr

parse() {
  file="`mktemp /tmp/yast2-test.XXXXXX`"
  cat >$file
  if [ -z "$Y2TESTSUITE" ]; then
    seds="s/ <[2-5]> [^ ]\+ \[YCP\] [^ ]\+ / <0> host [YCP] file LoGlOg=/"
    cat "$file" | sed "$seds" | grep -E "<[012]>.*(\[ag_dummy\]|\[bash_stdout\]|rEaL_rEt=|aNY_OutPuT=|LoGlOg=|SW_SINGLE|installList|deleteList)" | cut -d" " -f7-| grep -v "^checkPath" | sed -e 's/rEaL_rEt=/Return	/' | sed -e 's/aNY_OutPuT=/Dump	/' | sed -e 's/LoGlOg=/Log	/'
    cat "$file" | grep "<[^012]>" | grep -v "\[YCP\]" | grep -vF "type declaration with '|' will go away soon" >&2
  else
    echo "Y2TESTSUITE set to \"$Y2TESTSUITE\""
    echo
    cat "$file"
  fi
  rm -f "$file"
}

( y2bignfat -l /dev/fd/2 "$1" qt 2>&1 ) | parse >"$2" 2>"$3"

#( y2bignfat "$1" qt 2>&1 ) | parse >"$2" 2>"$3"

#(y2bignfat -l /dev/fd/2 $1 scr >$2) 2>&1 | cat > $3
#(y2bignfat -l /dev/fd/2 $1 scr >$2) 2>&1 | fgrep "[ag_dummy]" | cut -d" " -f7- > $3
#(y2bignfat -l /dev/fd/2 $1 scr >$2) 2>&1 | fgrep "[ag_dummy]" | sed 's/^....-..-.. ..:..:.. [^)]*) //g' > $3

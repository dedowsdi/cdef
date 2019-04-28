let s:scriptDir = expand('<sfile>:p:h')
let s:headFile = s:scriptDir . '/test.h'
let s:sourceFile = s:scriptDir . '/test.cpp'
let s:cdefAutoload = s:scriptDir . '/../autoload/cdef.vim'
let v:errors = []

normal! mM
echom 'reload cdef.vim'
let t0 = reltime() | exec 'edit ' s:cdefAutoload | VimlReloadScript
echom 'reload finished at' reltimestr(reltime(t0)) 'seconds'

echom 'start test switch proto func'
profile start /tmp/cdef_profile
profile func cdef#*
profile func *strToTag
let t0 = reltime()
try
  exec 'edit ' s:headFile | normal! gg
  while search('\v<test_\w+', 'W')
    normal! mA
    try
      normal! yt(
      let isTemplate = @" =~# 'template'
      let lnum = line('.')
      call assert_true(cdef#switchProtoFunc(), lnum .':'. @")
      normal! yt(
      let lnum = line('.')
      call assert_true(cdef#switchProtoFunc(), lnum .':'. @")
    finally
      normal! `A
    endtry
  endwhile
finally
  normal! `M
endtry
echohl WarningMsg
for err in v:errors
  echo err
endfor
echohl None
echom 'test switch proto func finished in ' reltimestr(reltime(t0)) 'seconds'
profile stop
echo 'finished'

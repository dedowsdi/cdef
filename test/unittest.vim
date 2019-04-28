let s:scriptDir = expand('<sfile>:p:h')
let s:headFile = s:scriptDir . '/test.h'
let s:sourceFile = s:scriptDir . '/test.cpp'
let s:cdefAutoload = s:scriptDir . '/../autoload/cdef.vim'
let v:errors = []

normal! mM
echom "reload cdef.vim"
exec 'edit ' s:cdefAutoload | VimlReloadScript

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
echo 'finished'

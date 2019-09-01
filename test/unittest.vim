let s:script_dir = expand('<sfile>:p:h')
let s:head_file = s:script_dir . '/test.h'
let s:source_file = s:script_dir . '/test.cpp'
let s:cdef_autoload = s:script_dir . '/../autoload/cdef.vim'
let v:errors = []

normal! mM
echom 'reload cdef.vim'
let t0 = reltime() | exec 'edit ' s:cdef_autoload | VimlReloadScript
echom 'reload finished at' reltimestr(reltime(t0)) 'seconds'

echom 'start test switch proto func'
profile start /tmp/cdef_profile
profile func cdef#*
profile func *str_to_tag
let t0 = reltime()
try
  exec 'edit ' s:head_file | normal! gg
  while search('\v<test_\w+', 'W')
    normal! mA
    try
      normal! yt(
      let is_template = @" =~# 'template'
      let lnum = line('.')
      call assert_true(cdef#switch_proto_func(), lnum .':'. @")
      normal! yt(
      let lnum = line('.')
      call assert_true(cdef#switch_proto_func(), lnum .':'. @")
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
echo 'finished'
" It's removed, you must exit vim to flush profile?
" profile stop

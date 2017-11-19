" define test:
"   copy cdef.h, cdef.cpp as test.h, test.cpp, after cdef#defineFile test.h,
"   test.h should be 100% the same as cdef_result.h, test.cpp 100% the same as
"   cdef_result.cpp
" 
" switch test:
"   every prototype in cdef_result.h should be able to switch to it's definition
"   and switch back

function! s:cmpFile(lhs, rhs)
  echom "compare ". a:lhs . " with " . a:rhs
  let success = 1

  silent! execute "edit " . a:lhs 
  let list0 = getline(1, line('$'))
  silent! execute "edit " . a:rhs 
  let list1 = getline(1, line('$'))

  let l0 = len(list0)
  let l1 = len(list1)
  if l0 == l1
    let l = l0
  else
    echom "total lines didn't match, ". a:lhs ." : " . l0 . " ".a:rhs." " . l1
    let l = min([l0, l1])
    let success = 0
  endif

  for i in range(l)
    if list0[i] != list1[i]
      let success = 0
      echom "line ".(i+1).' does not match, stop comparing'
      echom a:lhs . ' : '
      echom list0[i]
      echom a:rhs . ' : '
      echom list1[i]
      break
    endif 
  endfor

  if success 
    echom "********" . a:lhs . ' is totally the same as ' . a:rhs ."********" 
  else
    echoe "failed to compare " . a:lhs . " and " . a:rhs
  endif

  return success
endfunction


let [startLine, startCol, curFile] = [line('.'), col('.'), expand('%:p')]|try

  let s:oldSeverity = get(g:, "cdefNotifySeverity", 3)
  let g:cdefNotifySeverity = 5

  call cdef#pushOptions({"more":0, "eventignore":"all"})
  " reset buffer
  silent! bdelete! test/tmp/test.h
  silent! bdelete! test/tmp/test.cpp
  
  echom "copy cdef.h to test.h"
  call system('cp test/cdef.h test/tmp/test.h')
  echom "copy cdef.cpp to test.cpp"
  call system('cp test/cdef.cpp test/tmp/test.cpp')

  silent! edit test/tmp/test.h 
  profile start test/tmp/cdef_profile
  profile func cdef#*
  call cdef#defineFile()
  profile stop

  echom "start comparing"

  let success = s:cmpFile("test/tmp/test.h", "test/cdef_result.h") 
        \ && s:cmpFile("test/tmp/test.cpp", "test/cdef_result.cpp")

  if success
    echom "finish comparing"
  else
    echom "failed comparing"
  endif

  echom "start switch test"

  view test/cdef_result.h
  let tags = cdef#getTags()
  let prototypes = cdef#getTagPrototypes(tags)
  for prototype in prototypes
    call cursor(prototype.line, 1)
    if !cdef#isPure(prototype)
      echom "switching between prototype and function of " . cdef#getPrototypeString(prototype)
      if !cdef#switchBetProtoAndFunc()
        echoe "failed to switch to function at " . expand('%') . ':' . line('.') . ' : '
              \ . cdef#getPrototypeString(prototype)
      endif
      if !cdef#switchBetProtoAndFunc()
        echoe "failed to switch to prototype at " . expand('%') . ':' . line('.') . ' : '
              \ . cdef#getPrototypeString(prototype)
      endif
    endif 
  endfor

  echom "finish switch test"
finally
  let g:cdefNotifySeverity = s:oldSeverity
  silent! exec 'edit '. curFile 
  call cdef#popOptions() |call cursor(startLine, startCol)
endtry

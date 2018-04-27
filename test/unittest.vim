" define test:

"   copy cdef#.h, cdef#.cpp as test#.h, test#.cpp, after cdef#defineFile test#.h
"   should be 100% the same as cdef_result.h, test#.cpp 100% the same as
"   cdef#_result.cpp
"
" random define test:
"   copy cdef#.h, cdef#.cpp as test#.h, testr#.cpp, call cdef#define prototype
"   in random order, testr#.h should be 100% the same as cdef_result.h,
"   testr#.cpp 100% the same as cdef#_result.cpp
" 
" switch test:
"   every prototype in cdef#_result.h should be able to switch to it's definition
"   and switch back
"

function! s:getSid(file)
  let temp = @t|execute 'redir @t'
  try
    let plugfile = fnamemodify(a:file , ':p')
    let plugfile = plugfile[stridx(plugfile, '.'):]
    silent execute 'scriptnames'
    "becareful string is different from file
    let sid = matchstr(@t, '\v\zs\d+\ze:[^:]+' . escape(plugfile, '.'))
    if empty(sid)
      throw a:file . ' not found'
    endif	
    return sid
  finally
    let @t = temp|execute 'redir End'|return sid
  endtry
endfunction


function! s:random() abort
    return str2float(reltimestr(reltime())[-3:]) / 1000
endfunction
function! s:randomSortFunc(i1, i2)
  return float2nr(s:random() * 1000) % 2 == 0
endfunction

function! s:cmpFile(lhs, rhs)
  echom "compare ". a:lhs . " with " . a:rhs
  let success = 1

  call s:callCdef("open", a:lhs)
  let list0 = getline(1, line('$'))
  call s:callCdef("open", a:rhs)
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
      echom "line ".(i+1).' does not match, stop comparing'
      let success = 0
      echom a:lhs . ' : '
      echom list0[i]
      echom a:rhs . ' : '
      echom list1[i]
      throw "line ".(i+1).' does not match, stop comparing'
      break
    endif 
  endfor

  if success
    echom printf('%s is totally the same as %s', a:lhs, a:rhs)
  else
    throw printf('%s is not the same as %s', a:lhs, a:rhs)
  endif

  return success
endfunction

function! s:callCdef(name, ...)
  call call(printf('<SNR>%d_%s', s:cdefSid, a:name), a:000) 
endfunction

redir! > test/tmp/message


let [startLine, startCol, curFile] = [line('.'), col('.'), expand('%:p')]|try

  let s:oldSeverity = get(g:, "cdefNotifySeverity", 3)
  let g:cdefNotifySeverity = 5
  call cdef#pushOptions({"more":0, "eventignore":"all"})
  let s:cdefSid = s:getSid(expand('<sfile>:p:h:h').'/autoload/cdef.vim')

  for i in [0, 1, 2, 3, 9]

    echom ' '
    echom printf('******************************start test file group %d******************************', i)

    echom ' '
    echom printf("*****start define test for cdef%d*****", i)

    let testh = printf('test/tmp/test%d.h', i)
    let testcpp = printf('test/tmp/test%d.cpp', i)
    let testrh = printf('test/tmp/testr%d.h', i)
    let testrcpp = printf('test/tmp/testr%d.cpp', i)
    let resulth = printf('test/cdef%d_result.h', i)
    let resultcpp = printf('test/cdef%d_result.cpp', i)

    " reset buffer
    silent! execute "bdelete!" testh
    silent! execute "bdelete!" testcpp

    echom printf('copy test/cdef%d.h %s', i, testh)
    call system(printf('cp test/cdef%d.h %s', i, testh))
    echom printf('copy test/cdef%d.cpp %s', i, testcpp)
    call system(printf('cp test/cdef%d.cpp %s', i, testcpp))

    silent! exec "edit" testh
    exec printf('profile start test/tmp/cdef%d.profile', i)
    silent! exec printf('profile func <SNR>%d_*', sid)
    call cdef#defineFile()
    profile stop

    echom "start comparing"

    call s:cmpFile(testh, resulth) 
    call s:cmpFile(testcpp, resultcpp)

    echom ' '
    echom printf("*****start random define test for cdef%d*****", i)

    silent! execute "bdelete!" testrh
    silent! execute "bdelete!" testrcpp

    echom printf('copy test/cdef%d.h %s', i, testrh)
    call system(printf('cp test/cdef%d.h %s', i, testrh))
    echom printf('copy test/cdef%d.cpp %s', i, testrcpp)
    call system(printf('cp test/cdef%d.cpp %s', i, testrcpp))

    silent! exec "edit" testrh
    let tags = cdef#getTags()
    let prototypes = cdef#getTagPrototypes(tags)
    let l = range(len(prototypes))
    call sort(l, function("s:randomSortFunc"))
    try 
      let oldSeverity2 =  g:cdefNotifySeverity
      let g:cdefNotifySeverity = 3
      for j in l
        echom 'define ' . cdef#getPrototypeString(prototypes[j])
        call cursor(prototypes[j].line, 1) 
        call cdef#defineTag()
        call s:callCdef('open', testrh)
        let tags = cdef#getTags()
        let prototypes = cdef#getTagPrototypes(tags)
      endfor
    finally | let g:cdefNotifySeverity = oldSeverity2 | endtry

    echom "start comparing"

    call s:cmpFile(testrh, resulth) 
    call s:cmpFile(testcpp,resultcpp)

    echom ' '
    echom printf("*****start switch test for cdef%d*****", i)

    exec 'view' resulth 
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

    echom "finish test file group " . i
  endfor

finally
  let g:cdefNotifySeverity = s:oldSeverity
  silent! exec 'edit '. curFile 
  call cursor(startLine, startCol)
  call cdef#popOptions() 
  redir END
endtry

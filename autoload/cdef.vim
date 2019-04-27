if exists('g:loaded_cdef')
  finish
endif
let g:loaded_cdef = 1

let g:cdefMacros = get(g:, 'cdefMacros', ' -D "META_Object(library,name)=" ')
let g:cdefCtagCmdPre = 'ctags 2>/dev/null -f - --excmd=number --sort=no --fields=KsSiea
    \ --fields-c++=+{properties}{template} --kinds-c++=+pNU --language-force=c++ ' . g:cdefMacros
let g:cdefDefaultSourceExtension = get(g: , 'cdefDefaultSourceExtension', 'cpp')
let g:cdefProjName = get(g:, 'cdefProjName', '')
let s:srcExts = ['c', 'cpp', 'cxx', 'cc', 'inl']
let s:headExts = ['h', 'hpp', '']

let s:templateSrc = expand('<sfile>:p:h:h').'/template/'
let s:funcBody = readfile(glob(s:templateSrc) . 'funcbody')
let s:funcHat = readfile(glob(s:templateSrc) . 'funchat')
let s:optionStack = []
let s:updatingFunction = {}
let s:candidates = []

let g:cdefNotifySeverity = get(g:, 'cdefNotifySeverity', 3)
let s:NOTIFY_ALWAYS = 0
let s:NOTIFY_FATEL = 1
let s:NOTIFY_WARN = 2
let s:NOTIFY_NOTICE = 3
let s:NOTIFY_INFO = 4
let s:NOTIFY_DEBUG = 5
let s:NOTIFY_TRIVIAL = 6

function! s:notify(msg, ...) abort
  let lvl = get(a:000, 0, s:NOTIFY_NOTICE)
  if lvl > g:cdefNotifySeverity | return | endif
  if lvl == s:NOTIFY_FATEL
    echoe a:msg
  else
    echom a:msg
  endif
endfunction

function! s:always(msg) abort
  call s:notify(a:msg, s:NOTIFY_ALWAYS)
endfunction
function! s:fatel(msg) abort
  call s:notify(a:msg, s:NOTIFY_FATEL)
endfunction
function! s:warn(msg) abort
  call s:notify(a:msg, s:NOTIFY_WARN)
endfunction
function! s:notice(msg) abort
  call s:notify(a:msg, s:NOTIFY_NOTICE)
endfunction
function! s:info(msg) abort
  call s:notify(a:msg, s:NOTIFY_INFO)
endfunction
function! s:debug(msg) abort
  call s:notify(a:msg, s:NOTIFY_DEBUG)
endfunction
function! s:trivial(msg) abort
  call s:notify(a:msg, s:NOTIFY_TRIVIAL)
endfunction

function! s:open(file) abort
  let [f0, f1] = [expand('%:p'), fnamemodify(a:file, '%:p')]
  if f0 ==# f1 | return | endif
  let nr = bufnr(f1)
  if nr != -1 | exec printf('buffer %d', nr) | return | endif
  silent! exec 'edit ' . a:file
endfunction

function! s:strToTag(str) abort
  let l = split(a:str, "\t")

  if len(l) < 3 | echom 'failed to parse "' . a:str . "'" | return {} | endif

  let d = {'name':l[0], 'file':l[1], 'line':str2nr(l[2][:-3]), 'kind':l[3]}
  " name of `int operator[] (...)`  will contain trailing space, it must be removed
  if d.name[-1:] ==# ' ' | let d.name = d.name[0 : -2] | endif

  " always use class
  if d.kind ==#'struct' | let d.kind = 'class' | endif

  for item in l[4:]
    let idx = stridx(item, ':')
    let [field, content] = [item[0:idx-1], item[idx+1:]]
    let d[field] = content
  endfor

  " in source file, class is balabala:: before function name, class includes the
  " outer namespace, no matter in head or source file. ctag didn't add namespace
  " if it already add class.
  if has_key(d, 'struct') | let d['class'] = d.struct | endif

  if d.kind ==# 'prototype' || d.kind ==# 'function'
    call extend(d, {'class':'', 'namespace':'', 'classTag':{}, 'namespaceTag':{}}, 'keep')
    if !empty(d.class)
      let d.scope = d.class
    elseif !empty(!d.namespace)
      let d.scope = d.namespace
    else
      let d.scope = ''
    endif
    let d.fullName = has_key(d, 'scope') ? d.scope.'::'.d.name : d.name
  endif

  return d
endfunction

function! cdef#hasProperty(tag, property) abort
  return has_key(a:tag, 'properties') &&  stridx(a:tag.properties, a:property) != -1
endfunction

function! cdef#isPure(tag) abort
  return cdef#hasProperty(a:tag, 'pure')
endfunction

function! cdef#isDeleted(tag) abort
  return cdef#hasProperty(a:tag, 'delete')
endfunction

function! cdef#isInline(tag) abort
  return cdef#hasProperty(a:tag, 'inline')
endfunction

function! cdef#isVirtual(tag) abort
  return cdef#hasProperty(a:tag, 'virtual')
endfunction

function! cdef#isStatic(tag) abort
  return cdef#hasProperty(a:tag, 'static')
endfunction

function! cdef#isConst(tag) abort
  return cdef#hasProperty(a:tag, 'const')
endfunction

function! cdef#hasTemplate(tag) abort
  return has_key(a:tag, 'template')
endfunction

function! cdef#getTags(...) abort
  let ctagCmd = get(a:000, 0, g:cdefCtagCmdPre . expand('%:p')  )
  let l = systemlist(ctagCmd)
  if !empty(l) && l[0][0:4] ==# 'ctags:'
    throw printf('ctag cmd failed : %s\n. Error message:%s', ctagCmd, string(l))
  endif
  "let tags = [cdef#createTag('##global##', '', 0, 'namespace', {'end': 1000000, 'fullName': '##global##'})]
  "let namespaceStack = [tags[0]]
  let [tags, namespaceStack, classStack] = [[], [], []]

  for item in l
    let tag = s:strToTag(item)
    if tag.kind ==# 'slot' | continue | endif
    " ignore signal prototype, which always fallowed by a signal kind tag
    if tag.kind ==# 'signal' | call remove(tags, -1) | continue | endif

    let tags += [tag]
    " setup class name namespace for prototype and function
    while !empty(namespaceStack) && namespaceStack[-1].end < tag.line
      call s:trivial(printf('tag : pop namespace %s', namespaceStack[-1].name))
      call remove(namespaceStack, -1)
    endwhile

    while !empty(classStack) && classStack[-1].end < tag.line
      call s:trivial(printf('tag : pop class %s', classStack[-1].name))
      call remove(classStack, -1)
    endwhile

    if tag.kind ==# 'namespace'
      if !has_key(tag, 'end')
        call s:fatel(printf('namespace %s at line %d has no end, something must be seriously wrong',
              \ tag.name, tag.line))
        return
      endif
      call s:trivial(printf('tag : push namespace %s', tag.name))
      let namespaceStack += [tag]
    elseif tag.kind ==# 'class'
      if !has_key(tag, 'end')
        call s:fatel(printf('class %s at line %d has no end, something must be seriously wrong', 
              \ tag.name, tag.line))
        return
      endif
      call s:trivial(printf('tag : push class %s', tag.name))
      let classStack += [tag]
    elseif tag.kind ==# 'prototype' || tag.kind ==# 'function'
      let tag['classTag'] = get(classStack, -1, {})
      let tag['namespaceTag'] = get(namespaceStack, -1, {})
      if tag.namespaceTag != {} | let tag.namespace = tag.namespaceTag.name | endif
    endif
  endfor
  return tags
endfunction

function! cdef#createTag(name, file, line, kind, ...) abort
  let tag = {'name':a:name, 'file':a:file, 'line':a:line, 'kind':a:kind}
  call extend(tag, get(a:000, 0, {}), 'keep') | return tag
endfunction

function! cdef#findTag(tags, lnum) abort
  let l = filter(copy(a:tags), 'v:val.line == a:lnum')
  return empty(l) ? {} : l[0]
endfunction

"([line])
function! cdef#getTagAtLine(...) abort
  let lnum = get(a:000, 0, line('.'))
  let ctagCmd = g:cdefCtagCmdPre . expand('%:p') . ' | grep -P ''\t'.lnum.';"'''
  let tags = cdef#getTags(ctagCmd)
  return cdef#findTag(tags, lnum)
endfunction

function! cdef#pfToString(tag) abort
  let str = a:tag.name . cdef#handleDefaultValue(a:tag.signature, ')', 1)
  if has_key(a:tag, 'scope')
    let str = a:tag.scope . '::' . str
  endif
  if has_key(a:tag, 'properties')
    let str = str . ':' . a:tag.properties
  endif
  let str = cdef#getTemplate(a:tag) . str
  return str
endfunction

function! cdef#getPrototypeString(prototype) abort
  let str = a:prototype.name . cdef#handleDefaultValue(a:prototype.signature, ')', 1)
  if has_key(a:prototype, 'scope')
    let str = a:prototype.scope . '::' . str
  endif
  if has_key(a:prototype, 'properties')
    let str = str . ':' . a:prototype.properties
  endif
  let str = cdef#getTemplate(a:prototype) . str
  return str
endfunction

function! s:scroll(lnum) abort
  let wlnum = winline()
  if a:lnum > wlnum
    exec printf('normal! %d', a:lnum - wlnum)
  elseif a:lnum < wlnum
    exec printf('normal! %d', wlnum - a:lnum)
  endif
endfunction

" t0 : current tag, will be passes by function arglist
" t1 : lhs
" t2 : rhs
" scopes will be splited by :: and compared from right to left, the one with the
" more matched scope win(return -1), if they have the same matches, the one with
" less scopes win
function! s:compareCandidate(t0, t1, t2)
  if empty(a:t0.scope) | throw 'empty original scope during candidate comparing' | endif
  let s0 = reverse(split(a:t0.scope, '::'))
  let s1 = reverse(split(a:t1.scope, '::'))
  let s2 = reverse(split(a:t2.scope, '::'))
  let [i, m1, m2] = [0, 0, 0]
  while i < len(s0)
    if(m1 < len(s1) && s1[m1] == s0[i]) | let m1 += 1 | endif
    if(m2 < len(s2) && s2[m2] == s0[i]) | let m2 += 1 | endif
    let i += 1
  endwhile
  if m1 == m2
    return len(s1) == len(s2) ? 0 : len(s1) < len(s2) ? -1 : 1
  endif
  return m1 > m2 ? -1 : 1
endfunction

function! cdef#resetCandidates(tag, candidates)
  let [s:candidates, s:candidateIndex] = [a:candidates, 0]
  " if current tag has no scope, remove all class or namespace items
  if empty(a:tag.scope) | call filter(s:candidates, 'empty(v:val.scope)') | endif

  call sort(s:candidates, function('s:compareCandidate', [a:tag]))
  for cand in s:candidates
    call s:debug('add candidates : ' . cdef#pfToString(cand))
  endfor
endfunction

function! cdef#selectCandidate(idx) abort
  if empty(s:candidates) || a:idx >= len(s:candidates)
    echohl WarningMsg | echo a:idx 'overflow' | echohl None | return
  endif
  let s:candidateIndex = a:idx
  let tag = s:candidates[a:idx]
  call s:open(tag.file) | call cursor(tag.line, 1) | normal! ^
  if len(s:candidates) > 1
    echo printf('select (%d/%d)', s:candidates+1, len(s:candidates))
  endif
endfunction

function! cdef#selectNextCandidate() abort
  if empty(s:candidates) | return | endif
  let nextIndex = s:candidateIndex + 1
  if nextIndex == len(s:candidates)
    let nextIndex = 0
    if len(s:candidates) != 1
      echohl WarningMsg | echo 'hit last, continue at first' | echohl None
    endif
  endif
  call cdef#selectCandidate(nextIndex)
endfunction

function! s:searchFunctions(protoTag, tags) abort
  let res = []
  for funcTag in a:tags
    if funcTag.kind !=# 'function' | continue | endif
    if cdef#cmpProtoAndFunc(a:protoTag, funcTag) | call add(res, funcTag) | endif
  endfor
  return res
endfunction

function! cdef#searchFunctions(protoTag, tags, altFile) abort
  call s:debug('search functions for : ' . cdef#pfToString(a:protoTag))
  let l = s:searchFunctions(a:protoTag, a:tags)
  " search in alternate file
  if !empty(a:altFile)
    let ctagCmd = printf('%s %s | grep -P ''class|struct|^%s.*\bfunction\b''', g:cdefCtagCmdPre,
          \ a:altFile, substitute(a:protoTag.name, '\v[^0-9a-zA-Z \t]', '\\\0', 'g'))
    let l += s:searchFunctions(a:protoTag, cdef#getTags(ctagCmd))
  endif
  call cdef#resetCandidates(a:protoTag, l)
endfunction

function! s:searchPrototypes(protoTag, tags) abort
  let res = []
  for funcTag in a:tags
    if funcTag.kind !=# 'prototype' | continue | endif
    if cdef#cmpProtoAndFunc(funcTag, a:protoTag) | call add(res, funcTag) | endif
  endfor
  return res
endfunction

function! cdef#searchPrototypes(funcTag, tags0, altFile) abort
  call s:debug('search prototypes for : ' . cdef#pfToString(a:funcTag))
  let l = s:searchPrototypes(a:funcTag, a:tags0)
  " search in alternate file
  if !empty(a:altFile)
    let ctagCmd = printf('%s %s | grep -P ''class|struct|^%s.*\bprototype\b''', g:cdefCtagCmdPre,
          \ a:altFile, substitute(a:funcTag.name, '\v[^0-9a-zA-Z \t]', '\\\0', 'g'))
    let l += s:searchPrototypes(a:funcTag, cdef#getTags(ctagCmd))
  endif
  call cdef#resetCandidates(a:funcTag, l)
endfunction

function! cdef#switchProtoFunc() abort
  let tags = cdef#getTags()
  let t0 = cdef#findTag(tags, line('.'))
  if t0 == {} || (t0.kind !=# 'prototype' && t0.kind !=# 'function') | return 0 | endif

  let wlnum0 = winline()
  let altFile = cdef#getSwitchFile()
  let t1 = t0.kind ==# 'prototype' ?
        \ cdef#searchFunctions(t0, tags, altFile) : cdef#searchPrototypes(t0, tags, altFile)
  if empty(s:candidates) | return 0 | endif
  call cdef#selectCandidate(0) | call s:scroll(wlnum0) | return 1
endfunction

function! s:genFunc(prototype, nsFullName) abort
  let head = cdef#genFuncHead(a:prototype, a:nsFullName)
  let body = deepcopy(s:funcBody, a:nsFullName)
  return head + s:funcBody
endfunction

function! cdef#getTemplate(tag) abort
  let template = ''

  if has_key(a:tag.classTag, 'template')
    let template = printf('template%s', a:tag.classTag.template)
  endif

  if has_key(a:tag, 'template')
    let template = printf('%stemplate%s', template, a:tag.template)
  endif

  let template = cdef#handleDefaultValue(template , '>', 1)

  return template
endfunction

function! cdef#cmpSig(s0, s1) abort
  if a:s0 == a:s1 | return 1 | endif

  if xor(a:s0[-5:-1] ==# 'const', a:s1[-5:-1] ==# 'const') | return 0 | endif

  let [l0, l1] = [split(a:s0, ','), split(a:s1, ',')]
  if len(l0) != len(l1) | return 0 | endif

  " trim ()
  let l0[0] = l0[0][stridx(l0[0], '(')+1 : ]
  let l0[-1] = l0[-1][0 : stridx(l0[-1], ')') - 1]
  let l1[0] = l1[0][stridx(l1[0], '(')+1 : ]
  let l1[-1] = l1[-1][0 : stridx(l1[-1], ')') - 1]

  " compare arg one by one
  for i in range(len(l0))
    let [arg0, arg1] = [l0[i], l1[i]]
    if arg0 == arg1 | continue | endif

    " check arg without name
    " assume if two arguments are the same type, than one starts with the other,
    " and the remain part has to be \s+identifier or \s*identifier if smaller
    " one ends with [*&]
    if len(arg0) > len(arg1)
      let [big, small] = [arg0, arg1]
    else
      let [big, small] = [arg1, arg0]
    endif

    if stridx(big, small) == 0
      if small[-1:-1] =~# '\v[*&]' && big[len(small):] =~# '\v\s*\w+'
        continue
      elseif big[len(small):] =~# '\v\s+\w+'
        continue
      endif
    endif

    " check arg with different name
    " assume every thing except the identifer is the same.
    " There will be false positive for something like :
    "     void (unsigned int);
    "     void (unsigned short){}
    "
    let [i0,i1] = [strridx(arg0, ' '), strridx(arg1, ' ')]
    if i0 == -1 || i1 == -1 | return 0 | endif
    if arg0[0:i0] != arg1[0:i1] | return 0 | endif
    if arg0[i0 :] =~# '\v\w+' && arg1[i1 :] =~# '\v\w+' | continue | endif

    return 0
  endfor

  return 1
endfunction

function! s:printCmpResult(desc, t0, t1) abort
  if g:cdefNotifySeverity >= s:NOTIFY_TRIVIAL
    call s:trivial(a:desc)
    call s:trivial(printf('    %s', cdef#getPrototypeString(a:t0)))
    call s:trivial(printf('    %s', cdef#getPrototypeString(a:t1)))
  endif
endfunction

" namespaces and classes are ignored
function! cdef#cmpProtoAndFunc(t0, t1) abort
  if a:t0.name !=# a:t1.name | return 0 | endif

  let sig0 = cdef#handleDefaultValue(a:t0.signature, ')', '1')
  let sig1 = cdef#handleDefaultValue(a:t1.signature, ')', '1')

  if !cdef#cmpSig(sig0, sig1)
    call s:printCmpResult('compare signature failed', a:t0, a:t1) | return 0
  endif

  if substitute(cdef#getTemplate(a:t0), '\v<class>', 'typename', 'g') !=#
        \ substitute(cdef#getTemplate(a:t1), '\v<class>', 'typename', 'g')
    call s:printCmpResult('compare template failed', a:t0, a:t1)
    return 0
  endif

  return 1
endfunction

function! s:getPrototypeNamespaceFullName() dict abort
  return self.namespace.fullName
endfunction

function! s:hookMethod(tags, name, refName) abort
  for tag in a:tags
    let tag[a:name] = function(a:refName)
  endfor
endfunction

" operation:
"   0 : comment
"   1 : remove
" boundary : > for template, ) for function parameter
function! cdef#handleDefaultValue(str, boundary, operation) abort
  let pos = stridx(a:str, '(') " skip 1st ( of operator()()
  let dvs = []  " default values, [[startPos, endPos], ...]
  let [openPairs, closePairs, stack, target] = ['<([{"', '>)]}"',0 , ','.a:boundary]

  " get =, ignore !=, +=,etc
  while 1
    let frag = matchstrpos(a:str, '\v\s*([!%^&|+\-*/<>])@<!\=', pos + 1)
    if frag[2] == -1 | break | endif
    let pos = myvim#searchStringOverPairs(a:str, frag[2], target, openPairs, closePairs, 'l')
    if pos == -1  && a:boundary ==# '>'
      " universal-ctags failed to parse template with default template value:
      " template<typename T = vector<int> > class ...
      " the last > will be ignored by ctags
      let pos = len(a:str) - 1
    endif
    let dvs += [ [frag[1], pos-1] ]
  endwhile

  if empty(dvs) | return a:str | endif

  let [resStr, pos] = ['', 0]
  if a:operation == 1
    for pair in dvs
      let resStr .= a:str[pos : pair[0] - 1]
      let pos = pair[1] + 1
    endfor
    let resStr .= a:str[pos : ]
  else
    for pair in dvs
      let resStr .= a:str[pos : pair[0] - 1] . '/*' . a:str[pair[0] : pair[1]] . '*/'
      let pos = pair[1] + 1
    endfor
    let resStr .= a:str[pos : ]
  endif

  " handle > bug
  if a:boundary ==# '>' && resStr[ len(resStr)-1 ] !=# '>' | let resStr .= '>' | endif
  return resStr
endfunction

" start = template line, end = ; line
function! cdef#addStartEndToProto(proto) abort
  if a:proto.kind !=# 'prototype' | return | endif
  if has_key(a:proto, 'start') && has_key(a:proto, 'end') | return | endif

  try
    let oldpos = getpos('.')
    call s:open(a:proto.file) | call cursor(a:proto.line, 1)
    if search('\v(operator\s*\(\s*\))?\zs\(')
      normal! %
      if search('\v\_s*;')  | let a:proto['end'] = line('.')
      else
        throw 'failed to add end to ' . cdef#pfToString(a:proto)
      endif
    endif

    call cursor(a:proto.line, 1)
    if cdef#hasTemplate(a:proto)
      if search('\v^\s*<template>\_s*\<', 'bW', '')
        let a:proto['start'] = line('.')
      else
        throw 'faled to add start to ' . cdef#getprotoString(a:proto)
      endif
    else
      let a:proto['start'] = line('.')
    endif
  finally
    call setpos('.', oldpos)
  endtry
endfunction

" (proro, stripNamespace [, withHat])
function! cdef#genFuncHead(proto, stripNamespace, ...) abort
  let withHat = get(a:000, 0, 1)
  call cdef#addStartEndToProto(a:proto)
  let funcHeadList = getline(a:proto.start, a:proto.end)

  "trim left
  let numSpaces = 10
  for i in range(len(funcHeadList))
    let numSpaces = min([numSpaces, len(matchstr(funcHeadList[i], '\v^\s*'))])
  endfor
  for i in range(len(funcHeadList))
    let funcHeadList[i] = funcHeadList[i][numSpaces :]
  endfor

  let funcHead = join(funcHeadList, "\n")
  if cdef#hasProperty(a:proto, 'static')
    let funcHead = substitute(funcHead, '\v\s*\zs<static>\s*', '', '')
  endif

  let scope = ''
  if empty(a:proto.class)
    if !a:stripNamespace | let scope = a:proto.namespace | endif
  else
    let scope = a:proto.class
    if a:stripNamespace && !empty(a:proto.namespace)
      if stridx(scope, a:proto.namespace) != 0
        throw 'unknown state, tag class does''t start with namespace : '.cdef#pfToString(a:proto)
      endif
      let scope = scope[len(a:proto.namespace)+2:]
    endif
  endif

  "comment default value, must be called before remove trailing
  let funcHead = cdef#handleDefaultValue(funcHead, ')', 0)
  "remove static or virtual
  let funcHead = substitute(funcHead, '\vstatic\s*|virtual\s*', '', '' )
  "remove trailing
  let funcHead = substitute(funcHead, '\v(override)?\s*\;\s*$', '', '')

  " add class template
  if has_key(a:proto.classTag, 'template')
    let template = cdef#handleDefaultValue(a:proto.classTag.template, '>', 1)
    let scope .= substitute(template, '\v<typename>\s*|<class>\s*', '', '')
    let funcHead = printf("template%s\n%s", template, funcHead)
  endif

  " add scope
  if !empty(scope)
    " ctag always add extra blank after operator, it 'changed' function name
    if stridx(a:proto.name, 'operator') == 0
      let funcHead = substitute(funcHead, '\V\<operator', scope.'::\0', '')
    else
      " should i use ~ instead of of \W?
      let funcHead = substitute(funcHead, '\V\(\W\|\^\)\zs'.a:proto.name.'\>', scope.'::\0', '')
    endif
  endif

  let arr = split(funcHead, "\n")
  if withHat | let arr = s:funcHat + arr | endif
  return arr
endfunction

function! cdef#isHeadFile() abort
  return index(s:headExts, expand('%:e') ) >= 0
endfunction

function! cdef#isSourceFile() abort
  return index(s:srcExts, expand('%:e') ) >= 0
endfunction

function! cdef#getSwitchDirs() abort
  "take care of file path like include/subdir/file.h
  let dirPath = expand('%:p:h')
  let l = matchlist(dirPath, '\v(.*)(<include>|<src>)(.*)')
  if l == []
    let altDir = dirPath
  elseif l[2] ==# 'include'
    let altDir = l[1] . 'src' . l[3]
  elseif l[2] ==# 'src'
    let altDir = l[1] . 'include' . l[3]
  endif
  let altDir .= '/'

  " add current dir, in case .h and .cpp resides in the same src or include
  return [altDir, dirPath.'/']
endfunction

function! cdef#getSwitchFile() abort
  let altDirs = cdef#getSwitchDirs()
  let altExts = cdef#isHeadFile() ? s:srcExts : s:headExts
  let baseName = expand('%:t:r')

  for altDir in altDirs
    for ext in altExts
      let altFile = altDir.baseName
      if ext !=# '' | let altFile .= '.' . ext | endif
      if filereadable(altFile) | return altFile | endif
    endfor
  endfor

  return ''
endfunction

function! cdef#switchFile(...) abort
  let keepjumps = get(a:000, 0, 0)
  let cmdPre = keepjumps ? 'keepjumps ' : ''
  let altFile = cdef#getSwitchFile()

  if altFile !=# ''
    if bufexists(altFile)
      let bnr = bufnr(altFile) | exec cmdPre . 'buffer ' .  bnr | return 1
    elseif filereadable(altFile)
      silent! exec cmdPre . 'edit ' . altFile | return 1
    endif
  endif

  call s:notify("alternate file doesn't exist or can't be read")
endfunction

" [register [, stripNamespace]]
" create definition at register:
"    whole namespace if current tag is namespace
"    whole class if current tag is namespace
"    single function if current tag is a prototype
function! cdef#def(...) abort
  let [register, stripNamespace] = [get(a:000, 0, '"'), get(a:000, 1, 1)]
  let tags = cdef#getTags()
  let tag = cdef#findTag(tags, line('.'))
  if tag == {} | echo 'no valid tag on current line' | return | endif
  let range = []
  if tag.kind ==# 'prototype'
    let range = [tag.line, tag.line]
  elseif tag.kind ==# 'namespace' || tag.kind ==# 'class'
    let range = [tag.line, tag.end]
  endif

  if empty(range)
    echo 'no valid prototype, class, or namespace on current line' | return
  endif

  call filter(tags, 'v:val.kind ==# ''prototype'' && v:val.line >= range[0] && v:val.line <= range[1]')

  let def = ''
  for proto in tags
    let def .= join(s:genFunc(proto, stripNamespace), "\n") . "\n"
  endfor
  call setreg(register, def, 'V')
endfunction

function! cdef#createSourceFile() abort
  if !cdef#isHeadFile() || cdef#switchFile() | return | endif

  let altDir =  cdef#getSwitchDirs()[0]
  let baseName = expand('%:t:r')

  let file = printf('%s%s.%s', altDir, baseName, g:cdefDefaultSourceExtension)
  echo system(printf('echo ''#include "%s"''>%s', expand('%:t'), file))
  exec 'edit ' . file
  return 1
endfunction

" g:cdefProjName + dirname + filename
function! cdef#addHeadGuard() abort
  let dirname = expand('%:p:h:t')
  if dirname ==# 'include' || dirname ==# 'inc'
    let dirname = expand('%:p:h:h:t')
  endif
  let gatename = printf('%s_%s', dirname, substitute(expand('%:t'), "\\.", '_', 'g'))
  if g:cdefProjName !=# ''
    let gatename = g:cdefProjName . '_' . gatename
  endif
  let gatename = toupper(gatename)
  exec 'keepjumps normal! ggO#ifndef ' . gatename
  exec 'normal! o#define ' . gatename
  exec 'normal! o'
  exec 'keepjumps normal! Go#endif /* ' . gatename . ' */'
  keepjumps normal! ggjj
endfunction

" opts.style:
"   0 : generate getA()/setA()/toggleA() for mA, a()/a()/toggle_a() for m_a
"   1 : generate getA/setA/toggleA()
"   2 : generate a()/a()/toggle_a()
function! cdef#genGetSet(...) abort
  let opts = get(a:000, 0, {})
  call extend(opts, {'const':0, 'register':'"', 'entries':'gs', 'style':0}, 'keep')
  " q-args will pass empty register
  if opts.register ==# '' | let opts.register = '"' | endif
  "add extra blink line if register is uppercase
  if opts.register =~# '\v[A-Z]'
    exec 'let @'.opts.register.' = "\n"'
  endif

  let str = getline('.')
  let varType = cdef#trim(matchstr(str, '\v\s*\zs[^=/]+\ze<\h\w*>|\.\.\.'))
  let varName = matchstr(str,  '\v<\w+>\ze\s*[;\=,]')

  let argType = opts.const ? 'const '.varType.'&':varType
  let fname = varName
  let style = 2
  if len(fname) >= 2 && fname[0:1] =~# '\vm[A-Z]'
    "remove m from mName
    let fname = fname[1:]
    let style = opts.style == 2 ? 2 : 1
  elseif len(fname) >= 3 && fname[0:1] ==# 'm_'
    let fname = fname[2:]
    let style = opts.style == 1 ? 1 : 2
  endif

  if style == 1
    "make sure 1st character uppercase
    let fname = toupper(fname[0]) . fname[1:]
    let [gfname, sfname, tfname] = ['agbect' . fname, 'set' . fname, 'toggle' . fname]
  else
    let [gfname, sfname, tfname] = [fname, fname, 'toggle_' . fname]
  endif

  "generate get set toggle
  let res = ''
  if stridx(opts.entries, 'g') !=# -1
    let res .= printf("%s %s() const { return %s; }\n", argType, gfname, varName)
  endif
  if stridx(opts.entries, 's') !=# -1
    let res .= printf("void %s(%s v){ %s = v; }\n", sfname, argType, varName)
  endif
  if stridx(opts.entries, 't') != -1
    let res .= printf("void toggle%s() { %s = !%s; }\n", tfname, varName, varName)
  endif

  exec 'let @'.opts.register.' = res'
endfunction

function! cdef#trim(s, ...) abort
  let [noLeft, noRight, res] = [get(a:000, 0, 0), get(a:000, 1, 0), a:s]
  if !noLeft|let res = matchstr(res, '\v^\s*\zs.*')|endif
  if !noRight|let res = matchstr(res, '\v.{-}\ze\s*$')|endif
  return res
endfunction

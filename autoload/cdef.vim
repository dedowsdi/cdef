if exists('g:loaded_cdef')
  finish
endif
let g:loaded_cdef = 1

let g:cdefMacros = get(g:, 'cdefMacros', ' -D "META_Object(library,name)=" ')
let g:cdefCtagCmdPre = 'ctags 2>/dev/null -f - --excmd=number --sort=no --fields=KsSiea
			\ --fields-c++=+{properties}{template} --kinds-c++=+pNU --language-force=c++ ' . g:cdefMacros
let g:cdefDefaultSourceExtension = get(g: , 'cdefDefaultSourceExtension', 'cpp')
let s:srcExts = ['c', 'cpp', 'cxx', 'cc', 'inl']
let s:headExts = ['h', 'hpp', '']

let s:templateSrc = expand('<sfile>:p:h:h').'/template/'
let s:funcBody = readfile(glob(s:templateSrc) . 'funcbody')
let s:funcHat = readfile(glob(s:templateSrc) . 'funchat')
let s:optionStack = []
let s:updatingFunction = {}

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
  let f0 = expand('%:p')
  let f1 = fnamemodify(a:file, '%:p')

  if f0 ==# f1
    return
  endif

  let nr = bufnr(f1)
  if nr != -1
    exec printf('buffer %d', nr)
    return
  endif

  silent! exec 'edit ' . a:file
endfunction

" ([lnum, cnum])
function! s:getC(...) abort
  let lnum = get(a:000, 0, line('.'))
  let cnum = get(a:000, 1, col('.'))
  return matchstr(getline(lnum), printf('\%%%dc.', cnum))
endfunction

function! s:getBlock(block) abort
  let [lnum0,cnum0] = a:block[0]
  let [lnum1,cnum1] = a:block[1]

  let fragment = getline(lnum0, lnum1)
  if len(fragment) == 0
    return []
  endif
  "lnum0 might equal to lnum1, must chagne last line first
  let fragment[-1] = fragment[-1][: cnum1 - 1]
  let fragment[0] = fragment[0][cnum0 - 1:]
  return fragment
endfunction

" behave like visual block delete, but leaves no blank line
function! s:rmBlock(block) abort
  try
    let blc = [bufnr(''), line('.'), col('.')]
    let [lnum0,cnum0] = a:block[0]
    let [lnum1,cnum1] = a:block[1]

    let line0 =  getline(lnum0)
    let line1 =  getline(lnum1)

    if cnum0 == 1 && cnum1 == len(line1)
      exec printf('%d,%dd',lnum0, lnum1)
      return
    endif

    let lstart = lnum0
    let lend = lnum1
    if cnum1 < len(line1)
      call setline(lnum1, getline(lnum1)[cnum1 :])
      let lend -=1
    endif
    if cnum0 > 1
      call setline(lnum0, getline(lnum0)[0:cnum0-2])
      let lstart += 1
    endif

    if lend >= lstart
      "d will change cursor position
      exec printf('%d,%dd',lstart, lend)
    endif
  finally
    exec printf('buffer %d', blc[0]) | call cursor(blc[1], blc[2])
  endtry
endfunction

" push original settings into stack, apply options in opts
function! cdef#pushOptions(opts) abort
  let backup = {}
  for [key,value] in items(a:opts)
    exec 'let backup[key] = &'.key
    exec 'let &'.key . ' = value'
  endfor
  let s:optionStack += [backup]
endfunction

function! cdef#popOptions() abort
  if empty(s:optionStack)
    throw 'nothing to pop, empty option stack'
  endif

  let opts = remove(s:optionStack, len(s:optionStack) - 1)
  for [key,value] in items(opts)
    exec 'let &'.key . ' = value'
  endfor
endfunction

function! s:strToTag(str) abort
  let l = split(a:str, "\t")

  if len(l) < 3
    echom 'failed to parse "' . a:str . "'"
    return {}
  endif

  let d = {'name':l[0], 'file':l[1], 'line':str2nr(l[2][:-3]), 'kind':l[3]}
  " name of
  "   int operator[] (...) will 
  " will contain trailing space, it must be removed
  if d.name[len(d.name) - 1] ==# ' '
    let d.name = d.name[0 : len(d.name)-2 ]
  endif

  " always use class and function
  if d.kind ==#'struct'
    let d.kind = 'class'
  endif

  for item in l[4:]
    let idx = stridx(item, ':')
    let field = item[0:idx-1]
    let content = item[idx+1:]
    let d[field] = content
  endfor

  if has_key(d, 'class')
    let d['scope'] = d.class
  elseif has_key(d, 'struct')
    let d['scope'] = d.struct
    let d['class'] = d.struct
  elseif has_key(d, 'namespace')
    let d['scope'] = d.namespace
  endif

  let d.fullName = has_key(d, 'scope') ? d.scope.'::'.d.name : d.name

  return d
endfunction

" return [beg, end], or []
function! cdef#getBlankBlock(lnum) abort
  if !cdef#isBlankLine(a:lnum) | return [] | endif
  let range = [a:lnum, a:lnum]
  try
    let oldpos = getpos('.')
    call cursor(a:lnum, 1)
    if search('\v\S', 'bW')
      let range[0] = line('.') + 1
    endif
    call cursor(a:lnum, 1000000)
    if search('\v\S', 'W')
      let range[1] = line('.') - 1
    endif
    return range
  finally
    call setpos('.', oldpos)
  endtry
endfunction

" add cmt:[l,l], blank:[l,l], head:[[l,c],[l,c]], body:[[l,c], [l,c]],
" semicolon:[l,c], range[l,l] to prototype or function
" (tag [, {'blank':, 'cmt':}]). Blank only exists if cmt is available
function! cdef#getFuncDetail(tag, ...) abort
  if a:tag.kind !=# 'prototype' && a:tag.kind !=# 'function' | return  | endif

  call cdef#addStartEndToProtoAndFunc(a:tag)

  let opts = get(a:000, 0, {})
  call extend(opts, {'blank': 1, 'cmt' : 1}, 'keep')
  try
    let oldpos = getpos('.')
    call s:open(a:tag.file)
    let a:tag['range'] = [0,0]
    if opts.cmt
      let cmtRange = cdef#getCmtRange(a:tag.start - 1)
      if cmtRange != []
        let a:tag['cmt'] = cmtRange
        let a:tag.range[0] = cmtRange[0]
      endif

      if opts.blank
        let a:tag['blank'] =  cdef#getBlankBlock(a:tag.range[0] - 1)
        if a:tag.blank != []
          let a:tag.range[0] = a:tag.blank[0]
        endif
      endif
    endif

    "get head[0]. head[1]will be set before ; or {
    call cursor(a:tag.start, 1) | normal! ^

    let a:tag['head'] = [[line('.'), col('.')], []]
    if search('(')|keepjumps normal! %
    else|throw 'can not find (, illigal function'|endif

    if a:tag.kind ==# 'prototype'
      call search(';')
      let a:tag['semicolon'] = [line('.'), col('.')]
      call search('\v\S', 'bW')
      let a:tag.head[1] = [line('.'), col('.')]
      let a:tag.range[1] = a:tag.semicolon[0]
    else
      "get body, funcbody for ctor starts at :, expand('%:t'), not {
      let a:tag['body'] = [[],[]]
      call search('\v[{:]')
      let a:tag.body[0] = [line('.'), col('.')]
      call search('\v\S', 'bW')
      let a:tag.head[1] = [line('.'), col('.')]
      call cursor(a:tag.body[0])
      if s:getC() ==# ':' " check ctor initialization list
        call search('{')
      endif
      keepjumps normal! %
      let a:tag.body[1] = [line('.'), col('.')]
      let a:tag.range[1] = a:tag.body[1][0]
    endif

    return a:tag

  finally
    call setpos('.', oldpos)
  endtry

endfunction

" ([lnum])
function! cdef#getCmtRange(...) abort
  try
    let oldpos = getpos('.')
    let lnum = a:0 >= 1 ? a:1 : line('.')

    "check /* */ style
    call cursor(lnum, 1) | normal! $
    if search('\v^\s*\/\*', 'bW')
      "found /*
      let starStart = line('.')
      if search('\v\*\/', 'W')
        "found */
        let starEnd = line('.')
        if lnum >= starStart && lnum <= starEnd
          "check range
          return [starStart, starEnd]
        endif
      endif
    endif

    "check //style
    call cursor(lnum, 1000)
    if getline('.') =~# '^\v\s*\/\/'
      normal! $
      let reNotSlashCmt = '\v%(^\s*\/\/)@!^.?'
      let slashStart = search(reNotSlashCmt, 'bW') + 1
      let slashEnd = search(reNotSlashCmt, 'W') - 1
      if slashEnd == -1
        "special case, last line is //
        let slashEnd = line('$')
      endif
      if lnum >= slashStart && lnum <= slashEnd
        return [slashStart, slashEnd]
      endif
    endif
    return []
  finally
    call setpos('.', oldpos)
  endtry
endfunction

"rm // and /* style comment
function! cdef#rmComment(code) abort
  " remove all the // style comment
  let str = substitute(a:code, '\v\/\/[^\n]*\n', '', 'g')
  " romve all the /* styel comment

  let idx0 = match(str, '\v\/\*')
  while idx0 != -1
    let idx1 = match(str, '\v\*\/', idx0)
    if idx1 != -1
      let preStr = idx0 == 0 ? '' : str[0:idx0-1] " str[0:-1] == str
      let str = preStr.str[idx1+2:]
      let idx0 = match(str, '\v\/\*')
    else
      call s:warn('failed to faind */ for /*')
      break
    endif
  endwhile

  return str
endfunction

function! cdef#getSwitchDir() abort
  "take care of file path like  include/subdir/file.h
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

  " sometimes, .h and .cpp resides in the same src or include
  return [altDir, dirPath.'/']
endfunction

function! cdef#getSwitchFile() abort
  let altDirs = cdef#getSwitchDir()
  let altExts = cdef#isInHead() ? s:srcExts : s:headExts
  let baseName = expand('%:t:r')

  for altDir in altDirs
    for ext in altExts
      let altFile = altDir.baseName
      if ext !=# ''
        let altFile .= '.' . ext
      endif

      if filereadable(altFile)
        return altFile
      endif
    endfor
  endfor

  return ''
endfunction

function! cdef#switchFile(...) abort

  let keepjumps = get(a:000, 0, 0)
  let cmdPre = keepjumps ? "keepjumps " : ""

  let altFile = cdef#getSwitchFile()
  if altFile != ''
    if bufexists(altFile)
      let bnr = bufnr(altFile) | exec cmdPre . 'buffer ' .  bnr
      return 1
    elseif filereadable(altFile)
      silent! exec cmdPre . 'edit ' . altFile
      return 1
    endif
  endif

  call s:notify("alternate file doesn't exist or can't be read")

  "not found
  "if cdef#isInHead()
    "let file = printf('%s%s.%s', altDir, baseName, g:cdefDefaultSourceExtension)
    "echo system(printf('echo ''#include "%s"''>%s', expand('%:t'), file))
    "exec 'edit ' . file
    "silent exec
    "return 1
  "else
    "call s:notify('no head file to switch')
    "return 0
  "endif
endfunction

function! cdef#printAccessSpecifier(...) abort
  let tag = cdef#getTagAtLine()
  if tag && tag.has_key('access')
    echo tag.access
  endif
endfunction

function! cdef#printCurrentTag() abort
  let tag = cdef#getTagAtLine()
  if tag != {}
    echo tag
  endif
endfunction

function! cdef#isInHead() abort
  return index(s:headExts, expand('%:e') ) >= 0
endfunction

function! cdef#isInSrc() abort
  return index(s:srcExts, expand('%:e') ) >= 0
endfunction

function! cdef#assertInHead() abort
  if !cdef#isInHead()|throw expand('%') . ' is not a head file'|endif
endfunction

function! cdef#assertInSrc() abort
  if !cdef#isInSrc()|throw expand('%') . ' is not a source file'|endif
endfunction

function! cdef#isBlankLine(...) abort
  let lnum =get(a:000, 0, line('.'))
  if lnum < 1 || lnum > line('$') | return 0 | endif
  return getline(lnum) =~# '\v^\s*$'
endfunction

function! cdef#hasProperty(tag, property) abort
  return has_key(a:tag, 'properties') &&  stridx(a:tag.properties, a:property) != -1
endfunction

function! cdef#isPure(tag) abort
  return cdef#hasProperty(a:tag, 'pure')
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
  let ctagCmd =  get(a:000, 0, g:cdefCtagCmdPre . expand('%:p')  )
  let l = systemlist(ctagCmd)
  if !empty(l) && l[0][0:4] ==# 'ctags:'
    throw printf('ctag cmd failed : %s\n. Error message:%s', ctagCmd, string(l))
  endif
  let tags = [cdef#createTag('##global##', '', 0, 'namespace', {'end': 1000000, 'fullName': '##global##'})]
  let namespaceStack = [tags[0]]
  let classStack = [{}]

  for item in l

    let tag = s:strToTag(item)
    if tag.kind ==# 'slot'
      continue
    elseif tag.kind ==# 'signal'
      " ignore signal prototype, which always fallowed by a signal kind tag
      call remove(tags, -1)
      continue
    endif

    let tags += [tag]

    while namespaceStack[-1].end < tag.line
      " pop namespace
      call s:trivial(printf('tag : pop namespace %s', namespaceStack[-1].name))
      let namespaceStack = namespaceStack[0:-2]
    endwhile

    while classStack[-1] != {} && classStack[-1].end < tag.line
      " pop class
      call s:trivial(printf('tag : pop class %s', classStack[-1].name))
      let classStack = classStack[0:-2]
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
      let tag['class'] = classStack[-1]
      let tag['namespace'] = namespaceStack[-1]
    endif

  endfor
  return tags
endfunction

function! cdef#splitTags(tags) abort
  let d ={'namespaces':[], 'usings':[], 'classes':[], 'prototypes':[], 'functions':[]}
  for tag in a:tags
    if tag.kind ==# 'namespace'
      let d.namespaces += [tag]
    elseif tag.kind ==# 'using'
      let d.usings += [tag]
    elseif tag.kind ==# 'class' || tag.kind ==# 'struct'
      let d.classes += [tag]
    elseif tag.kind ==# 'prototype'
      let d.prototypes += [tag]
    elseif tag.kind ==# 'function'
      let d.functions += [tag]
    endif
  endfor
  return d
endfunction

function! cdef#createTag(name, file, line, kind, ...) abort
  let tag = {'name':a:name, 'file':a:file, 'line':a:line, 'kind':a:kind}
  let fields = get(a:000, 0, {})
  call extend(tag, fields, 'keep')
  return tag
endfunction

function! cdef#findTag(tags, lnum) abort
  let idx = cdef#binarySearch(a:tags, a:lnum)
  return idx == -1 ? {} : a:tags[idx]
endfunction

"([line])
function! cdef#getTagAtLine(...) abort
  let lnum = get(a:000, 0, line('.'))
  let ctagCmd = g:cdefCtagCmdPre . expand('%:p') . ' | grep -P ''\t'.lnum.';"'''
  let tags = cdef#getTags(ctagCmd)
  return cdef#findTag(tags, lnum)
endfunction

function! cdef#filterTags(tags, opts) abort
  let result = []
  let kind = get(a:opts, 'kind', '')
  let scope = get(a:opts, 'scope', '')
  for tag in a:tags
    if !empty(kind) && tag.kind != kind | continue | endif
    if !has_key(a:opts, 'scope') && get(tag, 'scope', '') != kind | continue | endif
    let result += [tag]
  endfor
  return result
endfunction

function! cdef#getTagsByKind(tags, kind) abort
  let result = []
  for tag in a:tags
    if tag.kind == a:kind
      let result += [tag]
    endif
  endfor
  return result
endfunction

function! cdef#getTagUsedNamespaces(tags) abort
  return cdef#getTagsByKind(a:tags, 'using')
endfunction

function! cdef#getTagNamespaces(tags) abort
  return cdef#getTagsByKind(a:tags, 'namespace')
endfunction

function! cdef#getTagUsings(tags) abort
  return cdef#getTagsByKind(a:tags, 'using')
endfunction

" keep relative order
function! cdef#getTagClasses(tags) abort
  let result = []
  for tag in a:tags
    if tag.kind ==# 'class' || tag.kind ==# 'struct'
      let result += [tag]
    endif
  endfor
  return result
endfunction

function! cdef#getTagPrototypes(tags) abort
  return cdef#getTagsByKind(a:tags, 'prototype')
endfunction

function! cdef#getTagFunctions(tags) abort
  return cdef#getTagsByKind(a:tags, 'function')
endfunction

function! cdef#getTagProtoAndFunc(tags) abort
  let result = []
  for tag in a:tags
    if tag.kind ==# 'prototype' || tag.kind ==# 'function'
      let result += [tag]
    endif
  endfor
  return result
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

" start = template line, end = ; line
function! cdef#addStartEndToProtoAndFunc(prototype) abort
  if a:prototype.kind !=# 'prototype' && a:prototype.kind !=# 'function' | return | endif
  if has_key(a:prototype, 'start') && has_key(a:prototype, 'end') | return | endif

	try
    let oldpos = getpos('.')

    call s:open(a:prototype.file)

    if !has_key(a:prototype, 'end')
      call cursor(a:prototype.line, 1)
      if search('\V(')
        normal! %
        if search('\v\_s*;')  | let a:prototype['end'] = line('.')
        else
          throw 'faled to add end to ' . cdef#getPrototypeString(a:prototype)
        endif
      endif
    endif

    if !has_key(a:prototype, 'start')
      call cursor(a:prototype.line, 1)
      if cdef#hasTemplate(a:prototype)
        if search('\v^\s*<template>\_s*\<', 'bW', '')
          let a:prototype['start'] = line('.')
        else
          throw 'faled to add start to ' . cdef#getPrototypeString(a:prototype)
        endif
      else
        let a:prototype['start'] = line('.')
      endif
    endif
  finally
    call setpos('.', oldpos)
  endtry

endfunction

function! cdef#getProtoFromFunc(tag) abort
  if a:tag.kind !=# 'function'
    call s:fatel(printf('you can not call cdef#getProtoFromFunc with kind:%s', a:tag.kind))
  endif

  call cdef#getFuncDetail(a:tag, {'blank':0, 'cmt':0})
  let result = getline(a:tag.line, a:tag.body[0][0])
  " replace { or : with ; discard everything after it
  let result[-1] = result[-1][0 : (a:tag.body[0][1] - 2)] . ';'

  if result[-1] =~# '\v^\s*;\s*$'
    let result[-2] .= ';'
    call remove(result, -1)
  endif

  return result
endfunction

function! cdef#locateNamespaceFirstSlot(namespaces) abort
  let oldpos = getpos('.')
  try
    for namespace in a:namespaces
      if namespace.name ==# '##global##' | continue | endif
      "search first slot : last using after {
      call s:open(namespace.file)
      call cursor(namespace.line, 1)
      if !search('\V{')
        call s:fatel('faled to find { for namespace ' . namespace.fullName )
      endif
      "continue search until 1st line that's not using or macro or blank
      if search('\v(^\s*using|^\s*#|^\s*$)@!^.', 'W')
        "retreat to last non blank line, it should be the 1st slot for this
        "namespace
        call search('\v^\s*\S', 'bW')
      endif
      let namespace['firstSlot'] = line('.')
    endfor
  finally
    call setpos('.', oldpos)
  endtry
endfunction

function! cdef#addEndToGlobalUsings(usings) abort
  for using in a:usings
    if !has_key(using, 'scope') " globe using
      let using['end'] = line('$')
    "else  " internal using
      "if has_key(d, using.scope)
        "let using['end'] = d[using.scope].end
      "else " unknown scope
        "let using['end'] = line('$')
      "endif
    endif
  endfor
endfunction

" add end to using, add firstSlot to namespace
function! cdef#getNamespaceUsingDict(namespaces, usings) abort
  let d = {}

  for namespace in a:namespaces
    let d[namespace.fullName] = namespace
    let namespace['dict'] = d
  endfor

  for using in a:usings
    let d[using.fullName] = using
    let using['dict'] = d
  endfor

  return d
endfunction

function! cdef#getMostFitTag(tags, lnum) abort
  let idx = cdef#getMostFitTagIndex(a:tags, a:lnum)
  return idx == -1 ? {} : a:tags[idx]
endfunction

function! cdef#getMostFitTagIndex(tags, lnum) abort
  let res = -1
  for i in range(len(a:tags))
    let tag = a:tags[i]
    if tag.end < a:lnum | continue | endif
    if tag.line > a:lnum | break | endif
    if res == -1 || (tag.line >= a:tags[res].line && tag.end <= a:tags[res].end)
      let res = i
    endif
  endfor
  return res
endfunction

function! cdef#getLeastFitTag(tags, lnum) abort
  let idx = cdef#getLeastFitTagIndex(a:tags, a:lnum)
  return idx == -1 ? {} : a:tags[idx]
endfunction

function! cdef#getLeastFitTagIndex(tags, lnum) abort
  let res = -1
  for i in range(len(a:tags))
    let tag = a:tags[i]
    if tag.end < a:lnum | continue | endif
    if tag.line > a:lnum | break | endif
    if res == -1 || (tag.line < a:tags[res].line && tag.end > a:tags[res].end)
      let res = i
    endif
  endfor
  return res
endfunction

function! s:getUsedNamespacePattern(usings) abort
  let pattern = ''
  for using in a:usings
    let pattern .= printf('<%s::|', using.name)
  endfor
  if len(pattern) != 0
    let pattern = '\v' . pattern[0:-2]
  endif
  let pattern = escape(pattern, ':')
  return pattern
endfunction

function! s:escapeFuncName(name) abort
  return escape(a:name, '+-*/~!%^&()[]<>|-')
endfunction

function! s:decorateFuncName(name) abort
  return substitute(s:escapeFuncName(a:name), '\v^operator\s*', 'operator\\s*', '')
endfunction

function! s:isNamespaceGlobal(namespace) abort
  return a:namespace.name ==# '##global##'
endfunction

function! s:isGlobalUsing(tag) abort
  return a:tag !=# {} && a:tag.kind ==# 'using' && !has_key(a:tag, 'scope')
endfunction

function! s:scroll(lnum) abort
  let wlnum = winline()
  if a:lnum > wlnum
    exec printf('normal! %d', a:lnum - wlnum)
  elseif a:lnum < wlnum
    exec printf('normal! %d', wlnum - a:lnum)
  endif
endfunction

" get function for prototype, prototype for function
function! cdef#searchMatch(t0, tags0) abort

  " search in current file
  if stridx(a:t0.name, 'operator') == 0
    let reName =  '\b' . s:decorateFuncName(a:t0.name)
  else
    let reName = escape(a:t0.name, '~') . '\b'
  endif
  "let ctagCmd = printf('%s%s | grep -P ''^%s|using''',g:cdefCtagCmdPre, expand('%:p'), reName)
  let usings0 = cdef#getTagUsings(a:tags0)
  let pattern = s:getUsedNamespacePattern(usings0)

  for t1 in a:tags0
    if t1.kind == a:t0.kind || (t1.kind !=# 'prototype' && t1.kind !=# 'function') | continue | endif
    if a:t0.line != t1.line && cdef#cmpProtoAndFunc(a:t0, t1, pattern)
      return t1
    endif
  endfor

  " search in alternate file
  let altFile = cdef#getSwitchFile()
  if len(altFile) == 0 | return {} | endif

  let ctagCmd = printf('%s%s | grep -P ''^%s|\busing\b|\d+;"\s+(class|struct|namespace)\b|'''
        \ ,g:cdefCtagCmdPre, altFile, reName)
  let tags1 = cdef#getTags(ctagCmd)
  let usings1 = cdef#getTagUsings(tags1)
  let pattern = s:getUsedNamespacePattern(usings0 + usings1)

  for t1 in tags1
    if t1.kind ==# a:t0.kind || (t1.kind !=# 'prototype' && t1.kind !=# 'function') | continue | endif
    if t1.name ==# a:t0.name && cdef#cmpProtoAndFunc(a:t0, t1, pattern)
      return t1
    endif
  endfor

  return {}
endfunction

function! cdef#switchBetProtoAndFunc() abort
  let tags = cdef#getTags()
  let t0 = cdef#findTag(tags, line('.'))
  if t0 != {} && (t0.kind ==# 'prototype' || t0.kind ==# 'function') && !cdef#isPure(t0)
    let wlnum0 = winline()
    let t1 = cdef#searchMatch(t0, tags)
    if t1 == {} | return 0 | endif
    call s:open(t1.file)
    call cursor(t1.line, 1) | normal! ^
    call s:scroll(wlnum0)
    return 1
  else
    return 0
  endif
endfunction

function! s:generateFunction(prototype, nsFullName) abort
  let head = cdef#genFuncDefHead(a:prototype, a:nsFullName)
  let body = deepcopy(s:funcBody, a:nsFullName)
  call map(body, "substitute(v:val, '\\V___FUNC___', '"
        \ . escape(cdef#getPrototypeString(a:prototype), '&')."' , '')")
  return head + body
endfunction

" shift line and end based on newly insert block [lstart, lend]
function! cdef#insertManualEntry(tags, manualEntry, lstart, lend) abort

  let numShift = a:lend - a:lstart + 1
  let idx = 0
  let slot = a:lstart - 1

  for tag in a:tags
    if tag.line >= a:lstart
      let tag.line += numShift
    endif

    " if using is the last line of source file, using.line == using.end == slot
    "if get(tag, 'end', -1) >= a:lstart || (tag.kind ==# 'using' && tag.line == slot)
    if get(tag, 'end', -1) >= a:lstart 
      let tag.end += numShift
    endif

    if tag.kind ==# 'namespace' && !s:isNamespaceGlobal(tag) && tag.firstSlot >= a:lstart
      let tag.firstSlot += numShift
    endif

    if idx == 0 && tag.line < a:manualEntry.line
      let idx += 1
    endif
  endfor

  call insert(a:tags, a:manualEntry, idx)
endfunction

function! cdef#getTemplate(tag) abort
  let template = ''

  if has_key(a:tag.class, 'template')
    let template = printf('template%s', a:tag.class.template)
  endif

  if has_key(a:tag, 'template')
    let template = printf('%stemplate%s', template, a:tag.template)
  endif

  "let template = substitute(template, '\v\zs\s*\=.{-}\ze[,>]', '', 'g')
  let template = cdef#handleDefaultValue(template , '>', 1)
  
  return template
endfunction

function! cdef#cmpSig(s0, s1) abort
  if a:s0 == a:s1
    return 1
  endif

  if xor(a:s0[-5:-1] ==# 'const', a:s1[-5:-1] ==# 'const')
    return 0
  endif

  let l0 = split(a:s0, ',')
  let l1 = split(a:s1, ',')

  " check arg number
  if len(l0) != len(l1) 
    return 0
  endif

  " trim ()
  let l0[0] = l0[0][stridx(l0[0], '(')+1 : ]
  let l0[-1] = l0[-1][0 : stridx(l0[-1], ')') - 1]
  let l1[0] = l1[0][stridx(l1[0], '(')+1 : ]
  let l1[-1] = l1[-1][0 : stridx(l1[-1], ')') - 1]

  " compare arg one by one
  for i in range(len(l0))
    let arg0 = l0[i]
    let arg1 = l1[i]
    if arg0 == arg1
      continue
    endif

    " check arg without name
    " assume if two arguments are the same type, than one starts with the other,
    " and the remain part has to be \s+identifier or \s*identifier if smaller
    " one ends with [*&]
    if len(arg0) > len(arg1)
      let big = arg0
      let small = arg1
    else
      let big = arg1
      let small = arg0
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
    let i0 = strridx(arg0, ' ')
    let i1 = strridx(arg1, ' ')
    if i0 == -1 || i1 == -1
      return 0
    endif

    if arg0[0:i0] != arg1[0:i1]
      return 0
    endif

    if arg0[i0 :] =~# '\v\w+' && arg1[i1 :] =~# '\v\w+'
      continue
    endif

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

function! cdef#cmpProtoAndFunc(t0, t1, pattern) abort
  if a:t0.name ==# a:t1.name 
    
    let scope0 = get(a:t0, 'scope', '')
    let scope1 = get(a:t1, 'scope', '')
    let sscope0 = substitute(scope0.'::', a:pattern, '', '') "stripped scope 0
    let sscope1 = substitute(scope1.'::', a:pattern, '', '')
    if !(scope0 ==# scope1 || scope0 ==# sscope1 || sscope0 ==# scope1 || sscope0 ==# sscope1)
      call s:printCmpResult('compare scope failed', a:t0, a:t1)
      return 0
    endif

    let sig0 = cdef#handleDefaultValue(a:t0.signature, ')', '1')
    let sig1 = cdef#handleDefaultValue(a:t1.signature, ')', '1')
    let ssig0 = substitute(sig0, a:pattern, '', '') "stripped sig 0
    let ssig1 = substitute(sig1, a:pattern, '', '')

    if a:t0.namespace.name !=# a:t1.namespace.name
      if s:isNamespaceGlobal(a:t0.namespace)
        let ssig0 = substitute(ssig0, printf('\v(::)@<!<%s>::', a:t1.namespace.name) , '', 'g')
      elseif s:isNamespaceGlobal(a:t1.namespace)
        let ssig1 = substitute(ssig1, printf('\v(::)@<!<%s>::', a:t0.namespace.name) , '', 'g')
      endif
    endif

    if !(cdef#cmpSig(sig0, sig1) || cdef#cmpSig(sig0, ssig1) || cdef#cmpSig(ssig0, sig1) || cdef#cmpSig(ssig0, ssig1)) 
      call s:printCmpResult('compare signature failed', a:t0, a:t1)
      return 0
    endif

    if substitute(cdef#getTemplate(a:t0), '\v<class>', 'typename', 'g') !=# 
          \ substitute(cdef#getTemplate(a:t1), '\v<class>', 'typename', 'g')
      call s:printCmpResult('compare template failed', a:t0, a:t1)
      return 0
    endif

    return 1

  endif

  return 0
endfunction

" [prototype, functions, pattern [, lstart, lend]]
function! cdef#searchDefinition(prototype, functions, pattern, ...) abort
  if has_key(a:prototype, 'function') | return a:prototype.function | endif
  let lstart = get(a:000, 0, 1)
  let lend = get(a:000, 1, 1000000)

  for tag in a:functions
    if tag.line < lstart | continue | endif
    if tag.line > lend | break | endif

    if cdef#cmpProtoAndFunc(a:prototype, tag, a:pattern)
      let a:prototype['function'] = tag
      return tag
    endif
  endfor

  return {}
endfunction

function! cdef#searchPrototype(function, prototypes, pattern) abort
  if has_key(a:function, 'prototype') | return a:function.prototype | endif

  for tag in a:prototypes
    if cdef#cmpProtoAndFunc(a:function, tag, a:pattern)
      let a:function['prototype'] = tag
      return tag
    endif
  endfor

  return {}
endfunction

function! s:getGroupNumber(prototype, class) abort
  return cdef#isInline(a:prototype) || cdef#hasTemplate(a:prototype)
        \ || (a:class != {} && cdef#hasTemplate(a:class)) ? 0 : 1
endfunction

function! s:checkEnd(tags) abort
  for tag in a:tags
    if !has_key(tag, 'end')
      call s:fatel(string(tag) . ' has no end, your c++ file might contain some problem')
      break
    endif
  endfor
endfunction

function! s:getPrototypeNamespaceFullName() dict abort
  return self.namespace.fullName
endfunction

" jump from namespace0 to namespace1
function! s:getNamespaceJumpSlot(namespace0, namespace1) abort

  if a:namespace0.fullName == a:namespace1.fullName
    return -1
  endif

  " ignore using if it's sibling or child of namespace1
  if a:namespace0.kind ==# 'using'
    if get(a:namespace0, 'scope', '') == get(a:namespace1, 'scope', '') ||
          \ get(a:namespace0, 'scope', '') == a:namespace1.fullName
      return -1
    endif
  endif

  " ignore father namespace changed into child namespace
  if s:isNamespaceGlobal(a:namespace0) ||
        \ get(a:namespace1, 'scope', '') == a:namespace0.fullName
    return -1
  endif

  " if namespace changed, pop namespace until they are in the same scope
  let slot = -1
  let namespace0 = a:namespace0
  while namespace0.fullName != a:namespace1.fullName
    if namespace0.kind ==# 'using' 
      " namespace internal using will be popped away, only global using will be
      " used to locate next slot
      let slot = line('$')
    else
      let slot = namespace0.end
    endif

    if !has_key(namespace0, 'scope') | break | endif

    if !has_key(namespace0.dict, namespace0.scope)
      call s:warn('failed to find namespace ' . namespace0.scope )
      break
    endif
    let namespace0 = namespace0.dict[namespace0.scope]
  endwhile
  return slot
endfunction

function! s:getSourceNextSlot(t0, t1) abort
  "global first slot
  if a:t0.name ==# '##global##' && a:t0.kind ==# 'namespace'
    return a:t0.firstSlot
  endif

  let namespace1 = a:t1.kind ==# 'prototype' ? a:t1.namespace : a:t1

  "namespace first slot
  if a:t0.kind ==# 'namespace'
    let slot = s:getNamespaceJumpSlot(a:t0, namespace1)
    return slot == -1 ? a:t0.firstSlot : slot
  endif

  "prototype next slot
  let slot = s:getNamespaceJumpSlot(a:t0.namespace, namespace1)
  return slot == -1 ? a:t0.end : slot

endfunction

function! s:hookMethod(tags, name, refName) abort
  for tag in a:tags
    let tag[a:name] = function(a:refName)
  endfor
endfunction

function! cdef#binarySearch(tags, l) abort
  if empty(a:tags)
    return -1
  endif
  let size = len(a:tags)

  let a = 0
  let c = size - 1
  let b = c/2

  "special case
  if a:tags[c].line < a:l || a:tags[a].line > a:l
    return -1
  elseif a:tags[a].line == a:l
    return a
  elseif a:tags[c].line == a:l
    return c
  endif

  "test every points except the initial a and c
  while c-a > 1
    if a:tags[b].line > a:l
      let c = b
      let b = (a+c)/2
    elseif a:tags[b].line < a:l
      let a = b
      let b = (a+c)/2
    else
      return b
    endif
  endwhile
  return -1
endfunction

function! cdef#lowerBound(tags, l) abort
  if empty(a:tags)
    return -1
  endif
  let size = len(a:tags)

  let a = 0
  let c = size - 1
  let b = c/2

  if a:tags[c].line < a:l
    return -1
  endif
  if a:tags[a].line >= a:l
    return a
  endif

  while c-a >= 1
    if a:tags[b].line > a:l
      let c = b
      let b = (a+c)/2
    elseif a:tags[b].line < a:l
      let a = b
      let b = (a+c)/2
    endif
  endwhile
  return c
endfunction

function! cdef#upperBound(tags, l) abort
  if empty(a:tags)
    return -1
  endif
  let size = len(a:tags)

  let a = 0
  let c = size - 1
  let b = c/2

  if a:tags[c].line < a:l
    return -1
  endif
  if a:tags[a].line > a:l
    return a
  endif

  while c-a > 1
    if a:tags[b].line > a:l
      let c = b
      let b = (a+c)/2
    elseif a:tags[b].line <= a:l
      let a = b
      let b = (a+c)/2
    endif
  endwhile
  return c
endfunction

" return index of first tag which has line < l
function! cdef#upperBoundInverse(tags, l) abort
  if empty(a:tags)
    return -1
  endif
  let size = len(a:tags)

  let a = 0
  let c = size - 1
  let b = c/2

  if a:tags[c].line > a:l
    return -1
  endif
  if a:tags[a].line < a:l
    return a
  endif

  while c-a > 1
    if a:tags[b].line < a:l
      let c = b
      let b = (a+c)/2
    elseif a:tags[b].line >= a:l
      let a = b
      let b = (a+c)/2
    endif
  endwhile
  return c
endfunction

" reserve line order
function! cdef#insertTag(tags, tag) abort
  let idx = cdef#upperBound(a:tags, a:tag.line)
  if idx == -1
    let idx  = len(a:tags)
  endif
  call insert(a:tags, a:tag, idx)
endfunction

" reserve line in reverse order
function! cdef#insertTagReverse(tags, tag) abort
  let idx = cdef#upperBoundInverse(a:tags, a:tag.line)
  if idx == -1
    let idx = len(a:tags)
  endif
  call insert(a:tags, a:tag, idx)
endfunction

" return:
"   {
"     box11:[namespaces and prototypes that will be defined in source fie],
"     box10:[namespaces and prototypes before lstart],
"     tags0: tags of head file
"     namespaces0:...
"     usings0:...
"     ..
"     ..
"     numElements0 : number of prototypes to be defined in head file
"     numElements1 : number of prototypes and namespaces to be defined in source file
"   }.
"
" each namespace in namespaces0 have 3 box:
" namespace.box1 : [prototypes that will be defined in this namespace]
" namespace.box0 : [prototypes before lstart in this namespace]
" namespace.box2 : [prototypes after lstart in this namespace]
function! s:getHeadData(lstart, lend) abort

  let file = expand('%')
  call s:debug('gathering data from head file ' . file)
  let tags0 = cdef#getTags()
  " fake global namespace
  let d0 = cdef#splitTags(tags0)
  let package = {
        \ 'namespaces0':d0.namespaces, 'usings0':d0.usings, 'head':file,
        \ 'classes0':d0.classes, 'prototypes0':d0.prototypes, 'functions0':d0.functions,
        \ 'tags0':tags0,  'box10':[],'box11':[],
        \ 'numElements0' : 0, 'numElements1' : 0
        \ }

  "tagfile error check
  call s:checkEnd(package.namespaces0)
  call s:checkEnd(package.classes0)

  let package['nsDict0'] = cdef#getNamespaceUsingDict(package.namespaces0, [])
  call cdef#locateNamespaceFirstSlot(package.namespaces0)

  for namespace in package.namespaces0
    let namespace['box0'] = []
    let namespace['box1'] = []
    let namespace['box2'] = []
  endfor

  " gather group0 prototypes
  for tag in package.prototypes0
    if cdef#isPure(tag)
      continue
    endif

    let tag['group'] = s:getGroupNumber(tag, tag.class)

    if tag.group == 1 | continue | endif

    if tag.line < a:lstart   " pre
      let tag.namespace.box0 = [tag] + tag.namespace.box0 " reverse order
    elseif tag.line > a:lend " post
      let tag.namespace.box2 += [tag]
    else
      call s:debug(printf('distribute %s to group 0',cdef#getPrototypeString(tag)))
      let tag.namespace.box1 += [tag]
      let package.numElements0 += 1
      call cdef#addStartEndToProtoAndFunc(tag)
      let tag['headLines'] = getline(tag.start, tag.end)
    endif
  endfor

  " gather group1 prototypes and namespaces. There will be some tags between
  " most out name space(non global) and a:lstart, they will not be defined, but
  " they will still be added to box11 to determine the slot for next prototype
  let startNamespace = cdef#getLeastFitTag(package.namespaces0[1:], a:lstart)
  let startLine = startNamespace == {} ? a:lstart : startNamespace.line
  for tag in package.prototypes0
    if cdef#isPure(tag)
      continue
    endif

    if tag.group == 0 | continue | endif

    if tag.line < startLine " pre
      let package.box10 = [tag] + package.box10 " reverse order
    elseif tag.line > a:lend " no post
      break
    else
      let package.box11 += [tag]

      if tag.line > startLine && tag.line < a:lstart
        call s:debug(printf('ignore %s ',cdef#getPrototypeString(tag)))
        let tag['ignored'] = 1 | continue
      endif

      let tag['ignored'] = 0
      let package.numElements1 += 1
      call s:debug(printf('distribute %s to group 1',cdef#getPrototypeString(tag)))
      if !has_key(tag, 'headLine')
        call cdef#addStartEndToProtoAndFunc(tag)
        let tag['headLines'] = getline(tag.start, tag.end)
      endif
    endif
  endfor

  " add namespace to box10 and box11
  for tag in package.namespaces0
    if tag.line > a:lend | break | endif
    if tag.end < a:lstart || s:isNamespaceGlobal(tag) " place global at pre box
      call cdef#insertTagReverse(package.box10, tag)
    else
      call cdef#insertTag(package.box11, tag)
    endif
  endfor

  return package
endfunction

function! s:getSourceData(package) abort

  let file = expand('%')
  call s:debug('gathering data from source file ' . file)
  let tags1 = cdef#getTags()

  "fake global namespace
  let d1 = cdef#splitTags(tags1)
  call extend(a:package,  {'namespaces1':d1.namespaces, 'usings1':d1.usings,
        \'classes1':d1.classes, 'prototypes1':d1.prototypes, 'functions1':d1.functions,
        \'tags1':tags1, 'source' : file})

  let a:package['nsDict1'] = cdef#getNamespaceUsingDict(a:package.namespaces1, a:package.usings1)
  call cdef#locateNamespaceFirstSlot(a:package.namespaces1)

  "check tag
  call s:checkEnd(a:package.namespaces1)
  "call s:checkEnd(a:package.usings1)

  " find 1st slot for global
  " place cursor at last #linclude or last line of starting comment
  call cursor(line('$'), 1000000)
  if !search('\v^\s*\#include', 'bW')
    call cursor(1,1)
    let cmtBlock = cdef#Range()
    if cmtBlock != []
      call cursor(cmtBlock[1], 1)
    endif
  endif

  "continue search until 1st line that's not using or macro or blank
  if search('\v(^\s*using|^\s*#|^\s*$)@!^.', 'W')
    "retreat to last non blank line, it should be the 1st slot for global
    call search('\v^\s*\S', 'bW')
  elseif getline(line('.')+1) =~# '\v\s*using|^\s*#|^\s*$'
    "must be a fresh new file, using or #balabala is last line
    call cursor(line('$'), 1)
  endif

  let a:package.namespaces1[0]['firstSlot'] = line('.')
endfunction

" define inlines, template related stuff in headfile namespace by namespace
" return [number of newly defined functions, last defined function]
function! cdef#defineHeadElements(package) abort
  let numDef = 0
  let def = {}
  for namespace in a:package.namespaces0
    if empty(namespace.box1)
      continue
    endif

    " get slot for 1st prototype in box1 in following sequence:
    "   end of 1st previous function
    "   one line above start (can be comment) of next function.
    "   one line above end of namespace of end of current file
    let previous = {}
    let next = {}
    for tag in namespace.box0
      let previous = cdef#searchDefinition(
            \ tag, a:package.functions0, '', namespace.line, namespace.end)
      if previous != {} | break | endif
    endfor

    if previous == {}
      for tag in namespace.box2
        let next = cdef#searchDefinition(
              \ tag, a:package.functions0, '', namespace.line, namespace.end)
        if next != {}
          call cdef#getFuncDetail(next)
          break
        endif
      endfor
      if next != {}
        let firstSlot = next.range[0] - 1
      else
        let firstSlot = s:isNamespaceGlobal(namespace) ? line('$') : namespace.end - 1
      endif
    endif

    for tag in namespace.box1
      let t1 = cdef#searchDefinition(
            \ tag, a:package.functions0, '', namespace.line, namespace.end)
      if t1 != {}
        let def = t1
        let previous = t1
        continue
      endif

      let slot = previous == {} ? firstSlot : previous.end

      call s:debug('define prototype : ' . cdef#getPrototypeString(tag))
      let numDef += 1
      let text = s:generateFunction(tag, tag.namespace.fullName)
      call append(slot, text)
      let t1 = cdef#createTag(tag.name, a:package.head,
            \ slot+len(s:funcHat)+1+tag.line-tag.start, 'function',
            \ {'end':slot + len(text), 'namespace':tag.namespace })
      call cdef#insertManualEntry(a:package.tags0, t1, slot + 1, t1.end)
      let previous = t1
      let def = t1
    endfor
  endfor

  return [numDef, def]
endfunction

" define namespaces and functions in source file
" return [number of newly defined elements, last defined element]
function! cdef#defineSourceElements(package) abort

  let numDef = 0
  let def = {}
  let previous = {}
  let pattern = s:getUsedNamespacePattern(a:package.usings1)

  " get previous prototype or namespace(not using) for 1st element.
  for tag in a:package.box10
    if tag.kind ==# 'namespace'
      let previous = get(a:package.nsDict1, tag.fullName, {})
      if previous != {} && previous.kind ==# 'using'
        let previous = {}
      endif
    else
      let previous = cdef#searchDefinition(tag, a:package.functions1, pattern)
    endif
    if previous != {} | break  | endif
  endfor

  for tag in a:package.box11

    let slot = s:getSourceNextSlot(previous, tag)

    if tag.kind ==# 'namespace'
      let t1 = get(a:package.nsDict1, tag.fullName, {})
      if t1 != {}
        let def = t1
        if t1.kind !=# 'using'
          let previous = t1
        endif
        continue
      endif

      "define namespace
      let numDef += 1
      call s:debug('define namespace ' . tag.fullName)
      let text = [
            \ '',
            \ 'namespace ' . tag.name ,
            \ '{',
            \ '}'
            \ ]
      call append(slot, text)

      let t1 = cdef#createTag(tag.name, a:package.source, slot+2, 'namespace' ,
            \ {'end' : slot+4, 'fullName' : tag.fullName, 'firstSlot' : slot + 3,
            \ 'dict':a:package.nsDict1,
            \ })
      if has_key(tag, 'scope')
        let t1['scope'] = tag.scope
      endif
      call cdef#insertManualEntry(a:package.tags1, t1, slot+1, t1.end)
      let a:package.nsDict1[t1.fullName] = t1
      let previous = t1
      let def = t1
    else

      "define function
      let numDef += 1
      let t1 = cdef#searchDefinition(tag, a:package.functions1, pattern)
      if t1 != {}
        let previous = t1
        let def = t1
        continue
      elseif tag.ignored
        continue
      endif

      call s:debug('define prototype : ' . cdef#getPrototypeString(tag))
      let text = s:generateFunction(tag, tag.namespace.fullName)
      call append(slot, text)
      let t1 = cdef#createTag(tag.name, a:package.source,
            \ slot+len(s:funcHat)+1+tag.line-tag.start, 'function',
            \ {'end':slot + len(text),
            \  'namespace' : a:package.nsDict1[tag.namespace.fullName] })
      call cdef#insertManualEntry(a:package.tags1, t1, slot + 1, t1.end)
      let previous = t1
      let def = t1
    endif
  endfor

  return [numDef, def]
endfunction

" define inline, template function and method of template class at the end of
" their namespace or current file.
" define others in source file in sequence.
function! cdef#define(lstart, lend) abort
  if !cdef#isInHead()
    call s:notify('please switch to head file if you want to define something')
    return
  endif

  let wlnum0 = winline()
  call cdef#pushOptions({'eventignore':'all'}) | try

    let package = s:getHeadData(a:lstart, a:lend)

    let def = {}
    let numHeadDef = 0
    let numSourceDef = 0
    if package.numElements0 > 0
      let [numHeadDef, def] =  cdef#defineHeadElements(package)
      if numHeadDef > 0
        silent w
      endif
    endif

    if package.numElements1 > 0
      call s:debug('switching to source file')
      call cdef#switchFile()
      call s:getSourceData(package)
      call s:debug('define functions in source file')
      let [numSourceDef, def] = cdef#defineSourceElements(package)
      if numSourceDef > 0
        silent w
      endif
    endif

    if def != {}
      call cursor(def.line, 1)
      normal! ^
      call s:scroll(wlnum0)
    endif

  finally
    call cdef#popOptions()
  endtry
endfunction

function! cdef#defineFile() abort
  call cdef#define(1, line('$'))
endfunction

function! cdef#defineTag() abort
  let tag = cdef#getTagAtLine()
  if tag == {} || tag.kind ==# 'function' | return | endif

  if tag.kind ==# 'prototype'
    call cdef#define(line('.'), line('.'))
  elseif has_key(tag, 'end')
    call cdef#define(tag.line, tag.end)
  endif
endfunction

" operation:
"   0 : comment
"   1 : remove
function! cdef#handleDefaultValue(str, boundary, operation) abort

  "return substitute(a:str, '\v[^)]{-}\zs\s*\=%(\s*\()@![^,]*\ze(,|\))', a:value, a:flag)
  let pos = -1
  let size = len(a:str)
  let stack = 0

  let dvs = []  " [[startPos, endPos], ...]

  let openPairs = '<([{"'
  let closePairs = '>)]}"'

  let target = printf(',%s', a:boundary)

  " get =, ignore staff like != positions
  while 1
    let frag = matchstrpos(a:str, '\v\s*([!%^&*+-/<>])@<!\=', pos + 1)
    if frag[2] == -1
      break
    endif

    let start = frag[2]
    let pos = myvim#searchOverPairs(a:str, start, target, openPairs, closePairs, 'l')

    if pos == -1  && a:boundary == '>'
      " universal-ctags failed to parse template with default template value:
      " template<typename T = vector<int> > class ...
      " the last > will be ignored by ctags
      let pos = len(a:str) - 1
    endif

    let dvs += [ [frag[1], pos-1] ]

  endwhile

  if empty(dvs)
    return a:str
  endif

  if a:operation == 1
    let resStr = ''
    let pos = 0
    for pair in dvs
      let resStr .= a:str[pos : pair[0] - 1]
      let pos = pair[1] + 1
    endfor
    let resStr .= a:str[pos : ]

    if a:boundary ==# '>' && resStr[ len(resStr)-1 ] != '>'
      let resStr .= '>'
    endif

    return resStr
  else
    let resStr = ''
    let pos = 0
    for pair in dvs
      let resStr .= a:str[pos : pair[0] - 1] . '/*' . a:str[pair[0] : pair[1]] . '*/'
      let pos = pair[1] + 1
    endfor
    let resStr .= a:str[pos : ]

    if a:boundary ==# '>' && resStr[ len(resStr)-1 ] != '>'
      let resStr .= '>'
    endif

    return resStr
  endif

endfunction

" (prorotype, nsFullName [, withHat])
function! cdef#genFuncDefHead(prototype, nsFullName, ...) abort
  let withHat = get(a:000, 0, 1)

  call cdef#addStartEndToProtoAndFunc(a:prototype)
	if has_key(a:prototype, 'headLines')
		let funcHeadList = a:prototype.headLines
	else
		try
			let oldpos = getpos('.')
			call s:open(a:prototype.file)
			let funcHeadList = getline(a:prototype.line, a:prototype.end)
		finally
			call setpos('.', oldpos)
		endtry
	endif

  "trim left
  for i in range(len(funcHeadList))
    let funcHeadList[i] = substitute(funcHeadList[i], '\v^\s*', '', '')
  endfor


  let funcHead = join(funcHeadList, "\n")
  if cdef#hasProperty(a:prototype, 'static')
    let funcHead = substitute(funcHead, '\v\s*\zs<static>\s*', '', '')
  endif

  "comment default value, must be called before remove trailing
  let funcHead = cdef#handleDefaultValue(funcHead, ')', 0)
  "remove static or virtual
  let funcHead = substitute(funcHead, '\vstatic\s*|virtual\s*', '', '' )
  "remove trailing
  let funcHead = substitute(funcHead, '\v\;\s*$', '', '')

  " add scope for class method only
  if a:prototype.class != {}
    let scope = get(a:prototype, 'scope', '')
    if empty(scope)
      call s:fatel('something is wrong, method has no class scope')
    endif
    if !empty(a:nsFullName)  "strip namespace from scope
      if stridx(scope, a:nsFullName) == 0
        let scope = scope[len(a:nsFullName)+2:]
      endif
    endif

    if has_key(a:prototype.class, 'template')
      let template = cdef#handleDefaultValue(a:prototype.class.template, '>', 1)
      let scope .= substitute(template, '\v<typename>\s*|<class>\s*', '', '')
      let funcHead = printf("template%s\n%s", template, funcHead)
    endif

    " ctag always add extra blank after operator, it 'changed' function name
    if stridx(a:prototype.name, 'operator') == 0
      let funcHead = substitute(funcHead, '\V\<operator', scope.'::\0', '')
    else
      let funcHead = substitute(funcHead, '\V\(\s\|\^\)\zs'.a:prototype.name.'\>', scope.'::\0', '')
    endif

  endif

  let arr = split(funcHead, "\n")
  if withHat
    let arr = s:funcHat + arr
  endif

  return arr
endfunction

function! s:mvFuncToProto(proto, func) abort
  call s:open(a:func.file)
  let funcBody = s:getBlock(a:func.body)
  silent! execute a:func.range[0] ',' a:func.range[1] 'd'
  w
  call s:open(a:proto.file)
  call cursor(a:proto.semicolon)|normal! x
  call append(line('.'), funcBody)
  execute printf('normal! =%dj', len(funcBody))
  w
endfunction

function! cdef#mvFunc() abort
  try
    let blc = [bufnr(''), line('.'), col('.')]
    let tags = cdef#getTags()
    let t0 = cdef#findTag(tags, line('.'))
    if t0 == {} || (t0.kind !=# 'prototype' && t0.kind !=# 'function')
      return
    endif

    call cdef#getFuncDetail(t0)
    let t1 = cdef#searchMatch(t0, tags)
    if t1 != {}
      call cdef#getFuncDetail(t1)
    endif

    if t0.kind ==# 'prototype'
      if t1 == {}
        call s:notify('not defined yet, nothing to mvoe') | return
      endif
      call s:mvFuncToProto(t0, t1)
    else
      if t1 != {}
        call s:mvFuncToProto(t1, t0)
      else
        if cdef#isInSrc()
          call s:notify('found no prototype, no where to move')
          return
        else
          " get body, change function to prorotype, then define it, change the
          " body back to original
          let funcBody = s:getBlock(t0.body)
          call s:rmBlock(t0.body)
          call cursor(t0.body[0])
          if col('.') == 1
            normal! k
          endif
          normal! A;
          w
          call cdef#define(t0.line, t0.line)
          let t1 = cdef#getTagAtLine()
          if t1 == {}
            call s:fatel('found no tag after redefine  ' + cdef#getPrototypeString(t0))
            return
          endif
          " replace definition body with original body
          call cdef#getFuncDetail(t1)
          call cursor(t1.body[0][0] - 1, 1)
          call s:rmBlock(t1.body)
          call append(line('.'), funcBody)
          execute printf('normal! =%dj', len(funcBody))
          w
        endif
      endif
    endif
  finally
    exec printf('buffer %d', blc[0]) | call cursor(blc[1], blc[2])
  endtry
endfunction

" Rename prototype name or function local variable
function! cdef#rename() abort
	let tags = cdef#getTags()
  let tag = cdef#findTag(tags, line('.'))
  if tag!= {} && tag.kind ==# 'prototype'
    call cdef#renameFunc(tag)
  else
    "check if in a function
    let functions = cdef#getTagFunctions(tags)
    let function = cdef#getMostFitTag(functions, line('.'))
    if function != {}
      call cdef#renameFunctionLocal(function)
    endif
  endif
endfunction

" Remove function definition and declaration and comment and blank
function! cdef#rmFunc() abort
  let tags = cdef#getTags()
  let t0 = cdef#findTag(tags, line('.'))
  let t1 = cdef#searchMatch(t0, tags)
  call cdef#getFuncDetail(t0)
  exec printf('%d,%dd', t0.range[0], t0.range[1])
  w
  call s:open(t1.file)
  call cdef#getFuncDetail(t1)
  exec printf('%d,%dd', t1.range[0], t1.range[1])
  w
endfunction

function! cdef#renameFunc(prototype) abort
  try|echohl Question
    call s:updatePrototypeStep0()
    let newName = inputdialog('Input new name for '. a:prototype.name . ':')
    if len(newName) > 0
      exec 's/\v<' .a:prototype.name  . '/' . newName
      w
      call s:updatePrototypeStep1()
    endif
  finally|echohl None|endtry
endfunction

function! cdef#renameFunctionLocal(function) abort
	try
		let oldpos = getpos('.')
		echohl Question
		let varName = expand('<cword>')
		let newName = inputdialog('Input new name for '. varName . ':')
		if len(newName) > 0
			exec a:function.line . ',' . a:function.end . 's/\v<' . varName . '>/' . newName . '/g'
		endif
	finally
		echohl None
		call setpos('.', oldpos)
	endtry
endfunction

function! cdef#updatePrototype() abort
  if s:updatingFunction == {}
    call s:updatePrototypeStep0()
  else
    call s:updatePrototypeStep1()
  endif
endfunction

function! s:updatePrototypeStep0() abort
  let tags = cdef#getTags()
  let t0 = cdef#findTag(tags, line('.'))
  if t0 == {} || t0.kind !=# 'prototype'
    call s:notice('no prototype at line ' . line('.'))
    return
  endif

  let namespaces = cdef#getTagNamespaces(tags)

  let s:updatingFunction = cdef#searchMatch(t0, tags)
  if s:updatingFunction != {}
    let s:updatingFunction['prototype'] = t0
    call s:notice( 'Prepare to update ' . cdef#getPrototypeString(t0))
  else
    call s:notice('this prototype has not been defined.')
  endif
endfunction

function! s:updatePrototypeStep1() abort
  if s:updatingFunction == {} | call s:warn('no function to update') | return | endif
  if s:updatingFunction.prototype == {}
    call s:debug('failed, prototype line must be chagned')
    let s:updatingFunction = {} | return
  endif

  let tags = cdef#getTags()
  let prototype = cdef#findTag(tags, s:updatingFunction.prototype.line)

  let nsFullName = prototype.namespace == {} ? '' : prototype.namespace.fullName
  let funcHead = cdef#genFuncDefHead(prototype, nsFullName, 0)

  call s:open(s:updatingFunction.file)
  let func = cdef#getFuncDetail(s:updatingFunction)
  call cursor(func.head[0])
  call s:rmBlock(func.head)
  if cdef#isBlankLine() " above command might leave a blank line
    normal! "_dd
    normal! k
  endif
  call append(func.head[0][0] - 1, funcHead)
  exec 'normal! =' . len(funcHead) . 'j'
  let s:updatingFunction = {}
endfunction

" (file, [, name [, property0, [property1 [,....]])
function! cdef#copyPrototype(file, ...) abort

  let targetFile = findfile(expand(a:file))
  if len(targetFile) == 0 | call s:notify('found no target file')|return | endif
  let name = get(a:000, 0, '.')

  try
    let blc = [bufnr(''), line('.'), col('.')]
	  call s:open(targetFile)
    let tags = cdef#getTags()
    let prototypes = cdef#getTagProtoAndFunc(tags)

    let candidates = []
    for prototype in prototypes
      if match(prototype.name, '\v'.name) != -1
        if a:0 >= 1
          for property in a:000[1:]
            if !cdef#hasProperty(prototype, property)
              continue
            endif
          endfor
        endif
        let candidates += [prototype]
      endif
    endfor

    let protoSigs = []
    for i in range(len(candidates))
      let protoSigs += [printf('%-4d : %s', i, cdef#getPrototypeString(candidates[i]))]
    endfor

    let inputStr = join(protoSigs, "\n") . "\n"
    let inputStr .= "********************************************************************************\n"
    let inputStr .= "Select item by number. Separate multiple item by space.\n"

    "get all the function! heads
    try|echohl Question
      let indexes = split(input(inputStr))
    finally|echohl None|endtry

    let selection = []
    for index in indexes
      let tag = candidates[index]
      if tag.kind ==# 'prototype'
        call cdef#addStartEndToProtoAndFunc(tag)
        let heads = getline(tag.start, tag.end)
      else
         let heads = cdef#getProtoFromFunc(tag)
      endif
      
      let selection = selection + [''] + heads 
    endfor
  finally
    exec printf('buffer %d', blc[0]) | call cursor(blc[1], blc[2])
  endtry

  "trim left
  for i in range(len(selection))
    let selection[i] = substitute(selection[i], '\v^\s*', '', '')
  endfor

  if len(selection) > 0
    call append('.', selection)
  endif
endfunction

function! cdef#addHeadGuard() abort
  let gatename = substitute(toupper(expand('%:t')), "\\.", '_', 'g')
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
  call extend(opts, {'const':0, 'register':'g', 'entries':'gs', 'style':0}, 'keep')
  " q-args will pass empty register
  if opts.register ==# ''
    let opts.register = 'g'
  endif
  "add extra blink line if register is uppercase
  if cdef#isUppercase(opts.register)
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
    let gfname = 'get' . fname
    let sfname = 'set' . fname
    let tfname = 'toggle' . fname
  else
    let gfname = fname
    let sfname = fname
    let tfname = 'toggle_' . fname
  endif

  "generate get set toggle
  if stridx(opts.entries, 'g') !=# -1
    let res = printf("%s %s() const { return %s; }\n", argType, gfname, varName)
  endif
  if stridx(opts.entries, 's') !=# -1
    let res .= printf("void %s(%s v){ %s = v; }\n", sfname, argType, varName)
  endif
  if stridx(opts.entries, 't') != -1
    let res .= printf("void toggle%s() { %s = !%s; }\n", tfname, varName, varName)
  endif

  exec 'let @'.opts.register.' = res'
endfunction

function! cdef#isUppercase(s) abort
  let re = '\v^\C[A-Z_0-9]+$'
  return match(a:s, re) == 0
endfunction

function! cdef#trim(s, ...) abort
  let noLeft = get(a:000, 0, 0)
  let noRight = get(a:000, 1, 0)
  let res = a:s
  if !noLeft|let res = matchstr(res, '\v^\s*\zs.*')|endif
  if !noRight|let res = matchstr(res, '\v.{-}\ze\s*$')|endif
  return res
endfunction

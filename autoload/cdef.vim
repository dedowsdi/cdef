if exists("g:loaded_cdef")
  finish
endif
let g:loaded_cdef = 1

let g:cdefCtagCmdPre = 'ctags -f - --excmd=number --sort=no --fields=KsSiea
			\ --fields-c++=+{properties}{template} --kinds-c++=+pNU --language-force=c++ '
let g:cdefDefaultSourceExtension = get(g: , "cdefDefaultSourceExtension", "cpp")
let s:srcExts = ['c', 'cpp', 'cxx', 'cc']
let s:headExts = ['h', 'hpp', '']

let s:templateSrc = expand('<sfile>:p:h:h').'/template/'
let s:funcBody = readfile(glob(s:templateSrc) . 'funcbody')
let s:funcHat = readfile(glob(s:templateSrc) . 'funchat')
let s:optionStack = []
let s:updatingFunction = {}

let g:cdefNotifySeverity = get(g:, "cdefNotifySeverity", 3)
let s:NOTIFY_ALWAYS = 0
let s:NOTIFY_FATEL = 1
let s:NOTIFY_WARN = 2
let s:NOTIFY_NOTICE = 3
let s:NOTIFY_INFO = 4
let s:NOTIFY_DEBUG = 5

function! s:notify(msg, ...)
  let lvl = get(a:000, 0, s:NOTIFY_NOTICE)
  if lvl > g:cdefNotifySeverity | return | endif
  if lvl == s:NOTIFY_FATEL
    echoe a:msg
  else
    echom a:msg
  endif
endfunction

function! s:always(msg)
  call s:notify(a:msg, s:NOTIFY_ALWAYS)
endfunction

function! s:fatel(msg)
  call s:notify(a:msg, s:NOTIFY_FATEL)
endfunction

function! s:warn(msg)
  call s:notify(a:msg, s:NOTIFY_WARN)
endfunction

function! s:notice(msg)
  call s:notify(a:msg, s:NOTIFY_NOTICE)
endfunction

function! s:info(msg)
  call s:notify(a:msg, s:NOTIFY_INFO)
endfunction

function! s:debug(msg)
  call s:notify(a:msg, s:NOTIFY_DEBUG)
endfunction

function! s:edit(file)
  if expand('%:p') != a:file && expand('%') != a:file
    silent! exec 'edit ' . a:file
  endif
endfunction

" ([lnum, cnum])
function! s:getC(...)
  let lnum = get(a:000, 0, line('.'))
  let cnum = get(a:000, 1, col('.'))
  return matchstr(getline(lnum), printf('\%%%dc', cnum))
endfunction

function! s:getBlock(block)
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
function! s:rmBlock(block)
  try
    let pos = getpos('.')
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
      call setline(lnum1, getline(lnum1)[cnum1:])
      let lend -=1
    endif
    if cnum0 > 1
      call setline(lnum0, getline(lnum0)[1:cnum0-1])
      let lstart += 1
    endif

    if lend >= lstart
      "d will change cursor position
      exec printf('%d,%dd',lstart, lend)
    endif
  finally
    call setpos('.', pos)
  endtry
endfunction

" push original settings into stack, apply options in opts
function! cdef#pushOptions(opts)
  let backup = {}
  for [key,value] in items(a:opts)
    exec 'let backup[key] = &'.key
    exec 'let &'.key . ' = value'
  endfor
  let s:optionStack += [backup]
endfunction

function! cdef#popOptions()
  if empty(s:optionStack)
    throw 'nothing to pop, empty option stack'
  endif

  let opts = remove(s:optionStack, len(s:optionStack) - 1)
  for [key,value] in items(opts)
    exec 'let &'.key . ' = value'
  endfor
endfunction

function! s:strToTag(str)
  let l = split(a:str, "\t")
  let d = {"name":l[0], "file":l[1], "line":str2nr(l[2][:-3]), "kind":l[3]}

  for item in l[4:]
    let idx = stridx(item, ':')
    let field = item[0:idx-1]
    let content = item[idx+1:]
    let d[field] = content
  endfor

  if has_key(d, "class")
    let d["scope"] = d.class
  elseif has_key(d, "struct")
    let d["scope"] = d.struct
  elseif has_key(d, "namespace")
    let d["scope"] = d.namespace
  endif

  return d
endfunction

" return [beg, end], or []
function! cdef#getBlankBlock(lnum)
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
" (tag [, {"blank":, "cmt":}]). Blank only exists if cmt is available
function! cdef#getFuncDetail(tag, ...)
  if a:tag.kind != "prototype" && a:tag.kind != "function" | return  | endif

  call cdef#addStartEndToProtoAndFunc(a:tag)

  let opts = get(a:000, 0, {})
  call extend(opts, {"blank": 1, "cmt" : 1}, "keep")
  try
    let oldpos = getpos('.')
    call s:edit(a:tag.file)
    let a:tag["range"] = [0,0]
    if opts.cmt
      let cmtRange = cdef#getCmtRange(a:tag.start - 1)
      if cmtRange != []
        let a:tag["cmt"] = cmtRange
        let a:tag.range[0] = cmtRange[0]
      endif

      if opts.blank
        let a:tag["blank"] =  cdef#getBlankBlock(a:tag.range[0] - 1)
        if a:tag.blank != []
          let a:tag.range[0] = a:tag.blank[0]
        endif
      endif
    endif

    "get head[0]. head[1]will be set before ; or {
    call cursor(a:tag.start, 1) | normal! ^

    let a:tag["head"] = [[line('.'), col('.')], []]
    if search("(")|keepjumps normal! %
    else|throw "can not find (, illigal function"|endif

    if a:tag.kind == "prototype"
      call search(";")
      let a:tag["semicolon"] = [line('.'), col('.')]
      call search('\v\S', 'bW')
      let a:tag.head[1] = [line('.'), col('.')]
      let a:tag.range[1] = a:tag.semicolon[0]
    else
      "get body, funcbody for ctor starts at :, not {
      let a:tag["body"] = [[],[]]
      call search('\v[{:]')
      let a:tag.body[0] = [line('.'), col('.')]
      call search('\v\S', 'bW')
      let a:tag.head[1] = [line('.'), col('.')]
      call cursor(a:tag.body[0])
      if s:getC() == ":" " check ctor initialization list
        call search("{")
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
function! cdef#getCmtRange(...)
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
    if getline('.') =~ '^\v\s*\/\/'
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
function! cdef#rmComment(code)
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
      call s:warn("failed to faind */ for /*")
      break
    endif
  endwhile

  return str
endfunction

function! cdef#getSwitchDir()
  "take care of file path like  include/subdir/file.h
  let dirPath = expand('%:p:h')
  let l = matchlist(dirPath, '\v(.*)(<include>|<src>)(.*)')
  if l == []
    let altDir = dirPath
  elseif l[2] == 'include'
    let altDir = l[1] . 'src' . l[3]
  elseif l[2] == 'src'
    let altDir = l[1] . 'include' . l[3]
  endif
  let altDir .= '/'
  return altDir
endfunction

function! cdef#getSwitchFile()
  let altDir = cdef#getSwitchDir()
  let altExts = cdef#isInHead() ? s:srcExts : s:headExts
  let baseName = expand('%:t:r')

  for ext in altExts
    let altFile = altDir.baseName
    if ext != ''
      let altFile .= '.' . ext
    endif

    if filereadable(altFile)
      return altFile
    endif
  endfor
  return ""
endfunction

function! cdef#switchFile(...)

  let keepjumps = get(a:000, 0, 0)
  let cmdPre = keepjumps ? "keepjumps " : ""

  let altDir = cdef#getSwitchDir()

  let altExts = cdef#isInHead() ? s:srcExts : s:headExts
  let baseName = expand('%:t:r')

  "check if it exists
  for ext in altExts
    let altFile = altDir.baseName
    if ext != ''
      let altFile .= '.' . ext
    endif
    if bufexists(altFile)
      let bnr = bufnr(altFile) | exec cmdPre . 'buffer ' .  bnr
      return 1
    elseif filereadable(altFile)
      silent! exec cmdPre . 'edit ' . altFile
      return 1
    endif
  endfor

  "not found
  if cdef#isInHead()
    let file = printf('%s%s.%s', altDir, baseName, g:cdefDefaultSourceExtension)
    let cmd = printf('echo ''#include "%s"''>%s', expand('%:t'), file)
    echo system(printf('echo ''#include "%s"''>%s', expand('%:t'), file))
    exec 'edit ' . file
    silent exec
    return 1
  else
    call s:notify("no head file to switch")
    return 0
  endif
endfunction

function! cdef#printAccessSpecifier(...)
  let tag = cdef#getTagAtLine()
  if tag && tag.has_key("access")
    echo tag.access
  endif
endfunction

function! cdef#printCurrentTag()
  let tag = cdef#getTagAtLine()
  if tag != {}
    echo tag
  endif
endfunction

function! cdef#isInHead()
  return index(s:headExts, expand('%:e') ) >= 0
endfunction

function! cdef#isInSrc()
  return index(s:srcExts, expand('%:e') ) >= 0
endfunction

function! cdef#assertInHead()
  if !cdef#isInHead()|throw expand('%') . ' is not a head file'|endif
endfunction

function! cdef#assertInSrc()
  if !cdef#isInSrc()|throw expand('%') . ' is not a source file'|endif
endfunction

function! cdef#isBlankLine(...)
  let lnum =get(a:000, 0, line('.'))
  if lnum < 1 || lnum > line('$') | return 0 | endif
  return getline(lnum) =~ '\v^\s*$'
endfunction

function! cdef#hasProperty(tag, property)
  return has_key(a:tag, "properties") &&  stridx(a:tag.properties, a:property) != -1
endfunction

function! cdef#isPure(tag)
  return cdef#hasProperty(a:tag, "pure")
endfunction

function! cdef#isInline(tag)
  return cdef#hasProperty(a:tag, "inline")
endfunction

function! cdef#isVirtual(tag)
  return cdef#hasProperty(a:tag, "virtual")
endfunction

function! cdef#isStatic(tag)
  return cdef#hasProperty(a:tag, "static")
endfunction

function! cdef#isConst(tag)
  return cdef#hasProperty(a:tag, "const")
endfunction

function! cdef#hasTemplate(tag)
  return has_key(a:tag, "template")
endfunction

function! cdef#getTags(...)
  let ctagCmd =  get(a:000, 0, g:cdefCtagCmdPre . expand('%:p')  )
  let l = systemlist(ctagCmd)
  if !empty(l) && l[0][0:4] == 'ctags:'
    throw printf('ctag cmd failed : %s\n. Error message:%s', ctagCmd, string(l))
  endif
  let tags = []
  for item in l
    let tags += [s:strToTag(item)]
  endfor
  return tags
endfunction

function! cdef#splitTags(tags)
  let d ={"namespaces":[], "usings":[], "classes":[], "prototypes":[], "functions":[]}
  for tag in a:tags
    if tag.kind == "namespace"
      let d.namespaces += [tag]
    elseif tag.kind == "using"
      let d.usings += [tag]
    elseif tag.kind == "class" || tag.kind == "struct"
      let d.classes += [tag]
    elseif tag.kind == "prototype"
      let d.prototypes += [tag]
    elseif tag.kind == "function"
      let d.functions += [tag]
    endif
  endfor
  return d
endfunction

function! cdef#createTag(name, file, line, kind, ...)
  let tag = {"name":a:name, "file":a:file, "line":a:line, "kind":a:kind}
  let fields = get(a:000, 0, {})
  call extend(tag, fields, "keep")
  return tag
endfunction

"([line, [tags]])
function! cdef#getTagAtLine(...)
  let lnum = get(a:000, 0, line('.'))
  if len(a:000) >= 2
    let tags = a:000[1]
    let idx = cdef#binarySearch(tags, lnum)
    return idx == -1 ? {} : tags[idx]
  else
    let ctagCmd = g:cdefCtagCmdPre . expand('%:p') . ' | grep -P ''\t'.lnum.''';'
    let tags = cdef#getTags(ctagCmd)
    return empty(tags) ? {} : tags[0]
  endif
endfunction

function! cdef#filterTags(tags, opts)
  let result = []
  let kind = get(a:opts, "kind", "")
  let scope = get(a:opts, "scope", "")
  for tag in a:tags
    if !empty(kind) && tag.kind != kind | continue | endif
    if !has_key(a:opts, "scope") && get(tag, "scope", "") != kind | continue | endif
    let result += [tag]
  endfor
  return result
endfunction

function! cdef#getTagsByKind(tags, kind)
  let result = []
  for tag in a:tags
    if tag.kind == a:kind
      let result += [tag]
    endif
  endfor
  return result
endfunction

function! cdef#getTagUsedNamespaces(tags)
  return cdef#getTagsByKind(a:tags, 'using')
endfunction

function! cdef#getTagNamespaces(tags)
  return cdef#getTagsByKind(a:tags, 'namespace')
endfunction

function! cdef#getTagUsings(tags)
  return cdef#getTagsByKind(a:tags, 'using')
endfunction

function! cdef#getTagCreatedNamespaces(tags)
  return cdef#getTagUsedNamespaces(tags) + cdef#getTagNamespaces(tags)
endfunction

" keep relative order
function! cdef#getTagClasses(tags)
  let result = []
  for tag in a:tags
    if tag.kind == "class" || tag.kind == "struct"
      let result += [tag]
    endif
  endfor
  return result
endfunction

function! cdef#getTagPrototypes(tags)
  return cdef#getTagsByKind(a:tags, 'prototype')
endfunction

function! cdef#getTagFunctions(tags)
  return cdef#getTagsByKind(a:tags, 'function')
endfunction

function! cdef#getPrototypeString(prototype)
  let str = a:prototype.name . a:prototype.signature
  if has_key(a:prototype, "template")
    let str = 'template'. a:prototype.template .str
  endif
  if has_key(a:prototype, "scope")
    let str = a:prototype.scope . '::' . str
  endif
  if has_key(a:prototype, "properties")
    let str = str . ':' . a:prototype.properties
  endif
  return str
endfunction

" start = template line, end = ; line
function! cdef#addStartEndToProtoAndFunc(prototype)
  if a:prototype.kind != "prototype" && a:prototype.kind != "function" | return | endif
  if has_key(a:prototype, "start") && has_key(a:prototype, "end") | return | endif

	try
    let oldpos = getpos('.')

    call s:edit(a:prototype.file)

    if !has_key(a:prototype, "end")
      call cursor(a:prototype.line, 1)
      if search('\V(')
        normal! %
        if search('\v\_s*;')  | let a:prototype["end"] = line('.')
        else
          throw "faled to add end to " . cdef#getPrototypeString(a:prototype)
        endif
      endif
    endif

    if !has_key(a:prototype, "start")
      call cursor(a:prototype.line, 1)
      if cdef#hasTemplate(a:prototype)
        if search('\v^\s*<template>\_s*\<', 'bW', '')
          let a:prototype["start"] = line('.')
        else
          throw "faled to add start to " . cdef#getPrototypeString(a:prototype)
        endif
      else
        let a:prototype["start"] = line('.')
      endif
    endif
  finally
    call setpos('.', oldpos)
  endtry


endfunction

" Add fullname property. add end to using, add firstSlot to namespace
function! cdef#extendNamespaces(namespaces, usings)
  let d = {}

  for namespace in a:namespaces
    let namespace["fullName"] = has_key(namespace, "scope") ?
          \ namespace.scope.'::'.namespace.name : namespace.name
    let d[namespace.fullName] = namespace
    let namespace['dict'] = d

    if namespace.name == "##global##" | continue | endif
    "search first slot : last using after {
    try
			let oldpos = getpos('.')
      call s:edit(namespace.file)
      call cursor(namespace.line, 1)
      if !search('\V{')
        call s:fatel("faled to find { for namespace " . namespace.fullName )
      endif
      "continue search until 1st line that's not using or macro or blank
      if search('\v(^\s*using|^\s*#|^\s*$)@!^.', 'W')
        "retreat to last non blank line, it should be the 1st slot for this
        "namespace
        call search('\v^\s*\S', 'bW')
      endif

			let namespace["firstSlot"] = line('.')
		finally
			call setpos('.', oldpos)
		endtry
	endfor

  for using in a:usings
    if !has_key(using, "scope") " globe using
      let using["fullName"] =  using.name
      let using["end"] = line('$')
      let d[using.fullName] = using
    else  " internal using
      let using["fullName"] =  using.scope . '::' . using.name
      if has_key(d, using.scope)
        let using["end"] = d[using.scope].end
      else " unknown scope
        let using["end"] = line('$')
      endif
      let d[using.fullName] = using
    endif
    let using['dict'] = d
  endfor

  return d
endfunction

function! cdef#getMostFitTag(tags, lnum)
  let idx = cdef#getMostFitTagIndex(a:tags, a:lnum)
  return idx == -1 ? {} : a:tags[idx]
endfunction

function! cdef#getMostFitTagIndex(tags, lnum)
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

function! cdef#getLeastFitTag(tags, lnum)
  let idx = cdef#getLeastFitTagIndex(a:tags, a:lnum)
  return idx == -1 ? {} : a:tags[idx]
endfunction

function! cdef#getLeastFitTagIndex(tags, lnum)
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

function! s:getUsedNamespacePattern(usings)
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

function! s:escapeFuncName(name)
  return escape(a:name, '+-*/~!%^&()[]<>|-')
endfunction

function! s:decorateFuncName(name)
  return substitute(s:escapeFuncName(a:name), '\v^operator\s*', 'operator\\s*', '')
endfunction

function! s:isNamespaceGlobal(namespace)
  return a:namespace.name == "##global##"
endfunction

function! s:isGlobalUsing(tag)
  return a:tag != {} && a:tag.kind == "using" && !has_key(a:tag, 'scope')
endfunction

function! s:scroll(lnum)
  let wlnum = winline()
  if a:lnum > wlnum
    exec printf('normal! %d', a:lnum - wlnum)
  elseif a:lnum < wlnum
    exec printf('normal! %d', wlnum - a:lnum)
  endif
endfunction

" get function for prototype, prototype for function
function! cdef#searchMatch(t0, tags0)

  " search in current file
  if stridx(a:t0.name, "operator") == 0
    let reName =  '\b' . s:decorateFuncName(a:t0.name)
  else
    let reName = '\b' . escape(a:t0.name, '~') . '\b'
  endif
  let ctagCmd = printf('%s%s | grep -E ''^%s|using''',g:cdefCtagCmdPre, expand('%:p'), reName)
  let d0 = cdef#splitTags(a:tags0)
  call cdef#extendNamespaces(d0.namespaces, d0.usings)
  let namespace = cdef#getMostFitTag(d0.namespaces, a:t0.line)
  let pattern = s:getUsedNamespacePattern(d0.usings)

  for t1 in a:tags0
    if t1.kind == a:t0.kind || (t1.kind != "prototype" && t1.kind != "function") | continue | endif
    if a:t0.line != t1.line && cdef#cmpProtoAndFunc(a:t0, t1, pattern)
      return t1
    endif
  endfor

  " search in alternate file
  let altFile = cdef#getSwitchFile()
  if len(altFile) == 0 | return 0 | endif

  let ctagCmd = printf('%s%s | grep -E ''^%s|using''',g:cdefCtagCmdPre, altFile, reName)
  let tags1 = cdef#getTags(ctagCmd)
  let d1 = cdef#splitTags(tags1)
  call cdef#extendNamespaces(d1.namespaces, d1.usings)
  let pattern = s:getUsedNamespacePattern(d0.usings + d1.usings)

  for t1 in tags1
    if t1.kind == a:t0.kind || (t1.kind != "prototype" && t1.kind != "function") | continue | endif
    if t1.name == a:t0.name && cdef#cmpProtoAndFunc(a:t0, t1, pattern)
      return t1
    endif
  endfor

  return {}
endfunction

function! cdef#switchBetProtoAndFunc()
  let tags = cdef#getTags()
  let t0 = cdef#getTagAtLine(line('.'), tags)
  if t0 != {} && (t0.kind == "prototype" || t0.kind == "function") && !cdef#isPure(t0)
    let wlnum0 = winline()
    let t1 = cdef#searchMatch(t0, tags)
    if t1 == {} | return 0 | endif
    call s:edit(t1.file)
    call cursor(t1.line, 1) | normal! ^
    call s:scroll(wlnum0)
    return 1
  else
    return 0
  endif
endfunction

function! s:generateFunction(prototype, nsFullName)
  let head = cdef#genFuncDefHead(a:prototype, a:nsFullName)
  let body = deepcopy(s:funcBody, a:nsFullName)
  call map(body, "substitute(v:val, '\\V___FUNC___', '"
        \ . escape(cdef#getPrototypeString(a:prototype), '&')."' , '')")
  return head + body
endfunction

" shift line and end based on newly insert block [lstart, lend]
function! cdef#insertManualEntry(tags, manualEntry, lstart, lend)

  let numShift = a:lend - a:lstart + 1
  let idx = 0
  let slot = a:lstart - 1

  for tag in a:tags
    if tag.line >= a:lstart
      let tag.line += numShift
    endif

    " if using is the last line of source file, using.line == using.end == slot
    if get(tag, "end", -1) >= a:lstart || (tag.kind == "using" && tag.line == slot)
      let tag.end += numShift
    endif

    if tag.kind == "namespace" && !s:isNamespaceGlobal(tag) && tag.firstSlot >= a:lstart
      let tag.firstSlot += numShift
    endif

    if idx == 0 && tag.line < a:manualEntry.line
      let idx += 1
    endif
  endfor

  call insert(a:tags, a:manualEntry, idx)
endfunction

function! cdef#cmpProtoAndFunc(t0, t1, pattern)
  if a:t0.name == a:t1.name && get(a:t0, "template", "") == get(a:t1, "template", "")
    "ctag include default value in signature
    let sig0 = s:substituteDefaultValue(a:t0.signature, '', 'g')
    let sig1 = s:substituteDefaultValue(a:t1.signature, '', 'g')
    let scope0 = get(a:t0, 'scope', '').'::'
    let scope1 = get(a:t1, 'scope', '').'::'
    let ssig0 = substitute(sig0, a:pattern, '', '') "stripped sig 0
    let ssig1 = substitute(sig1, a:pattern, '', '')
    let sscope0 = substitute(scope0.'::', a:pattern, '', '') "stripped scope 0
    let sscope1 = substitute(scope1.'::', a:pattern, '', '')
    if (sig0 == sig1 || sig0 == ssig1 || ssig0 == sig1 || ssig0 == ssig1) &&
          \ (scope0 == scope1 || scope0 == sscope1 || sscope0 == scope1 || sscope0 == sscope1)
      return 1
    endif
  endif

  return 0
endfunction

" [prototype, functions, pattern [, lstart, lend]]
function! cdef#searchDefinition(prototype, functions, pattern, ...)
  if has_key(a:prototype, "function") | return a:prototype.function | endif
  let lstart = get(a:000, 0, 1)
  let lend = get(a:000, 1, 1000000)

  for tag in a:functions
    if tag.line < lstart | continue | endif
    if tag.line > lend | break | endif

    if cdef#cmpProtoAndFunc(a:prototype, tag, a:pattern)
      let a:prototype["function"] = tag
      return tag
    endif
  endfor

  return {}
endfunction

function! cdef#searchPrototype(fuction, prototypes, pattern)
  if has_key(a:function, "prototype") | return a:function.prototype | endif

  for tag in a:prototypes
    if cdef#cmpProtoAndFunc(a:function, tag, a:pattern)
      let a:function["prototype"] = tag
      return tag
    endif
  endfor

  return {}
endfunction

function! s:getGroupNumber(prototype, class)
  return cdef#isInline(a:prototype) || cdef#hasTemplate(a:prototype)
        \ || (a:class != {} && cdef#hasTemplate(a:class)) ? 0 : 1
endfunction

function! s:checkEnd(tags)
  for tag in a:tags
    if !has_key(tag, "end")
      call s:fatel(string(tag) . " has no end, your c++ file might contain some problem")
      break
    endif
  endfor
endfunction

function! s:getPrototypeNamespaceFullName() dict
  return self.namespace.fullName
endfunction

function! s:getNamespaceJumpSlot(namespace0, namespace1)

  " ignore using if it's sibling or child of namespace1
  if a:namespace0.kind == 'using'
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
    let slot = namespace0.end
    if !has_key(namespace0, "scope") | break | endif

    if !has_key(namespace0.dict, namespace0.scope)
      call s:warn("failed to find namespace " . namespace0.scope )
      break
    endif
    let namespace0 = namespace0.dict[namespace0.scope]
  endwhile
  return slot
endfunction

function! s:getSourceNextSlot(t0, t1)
  "global next slot
  if a:t0.name == "##global##" && a:t0.kind == "namespace"
    return a:t0.nextSlot
  endif

  let namespace1 = a:t1.kind == "prototype" ? a:t1.namespace : a:t1

  "namespace next slot
  if a:t0.kind == "namespace"
    let slot = s:getNamespaceJumpSlot(a:t0, namespace1)
    return slot == -1 ? a:t0.firstSlot : slot
  endif

  "prototype next slot
  let slot = s:getNamespaceJumpSlot(a:t0.namespace, namespace1)
  return slot == -1 ? a:t0.end : slot

endfunction

function! s:hookMethod(tags, name, refName)
  for tag in a:tags
    let tag[a:name] = function(a:refName)
  endfor
endfunction

function! cdef#binarySearch(tags, l)
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

function! cdef#lowerBound(tags, l)
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

function! cdef#upperBound(tags, l)
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
function! cdef#upperBoundInverse(tags, l)
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
function! cdef#insertTag(tags, tag)
  let idx = cdef#upperBound(a:tags, a:tag.line)
  if idx == -1
    let idx  = len(a:tags)
  endif
  call insert(a:tags, a:tag, idx)
endfunction

" reserve line in reverse order
function! cdef#insertTagReverse(tags, tag)
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
function! s:getHeadData(lstart, lend)

  let file = expand('%')
  call s:debug("gathering data from head file " . file)
  let tags0 = cdef#getTags()
  " fake global namespace
  let global0 = cdef#createTag("##global##", file, 0, "namespace", {"end": 1000000})
  call insert(tags0, global0, 0)
  let d0 = cdef#splitTags(tags0)
  let package = {
        \ "namespaces0":d0.namespaces, "usings0":d0.usings, "head":file,
        \ "classes0":d0.classes, "prototypes0":d0.prototypes, "functions0":d0.functions,
        \ "tags0":tags0,  "box10":[],"box11":[],
        \ "numElements0" : 0, "numElements1" : 0
        \ }

  "tagfile error check
  call s:checkEnd(package.namespaces0)
  call s:checkEnd(package.classes0)

  let package["nsDict0"] = cdef#extendNamespaces(package.namespaces0, [])

  for namespace in package.namespaces0
    let namespace["box0"] = []
    let namespace["box1"] = []
    let namespace["box2"] = []
  endfor

  " gather group0 prototypes
  for tag in package.prototypes0
    if cdef#isPure(tag)
      continue
    endif

    let tag["class"] =cdef#getMostFitTag(package.classes0, tag.line)
    let tag["group"] = s:getGroupNumber(tag, tag.class)
    let tag["namespace"] = cdef#getMostFitTag(package.namespaces0, tag.line)

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
      let tag["headLines"] = getline(tag.start, tag.end)
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
        let tag["ignored"] = 1 | continue
      endif

      let tag["ignored"] = 0
      let package.numElements1 += 1
      call s:debug(printf('distribute %s to group 1',cdef#getPrototypeString(tag)))
      if !has_key(tag, "headLine")
        call cdef#addStartEndToProtoAndFunc(tag)
        let tag["headLines"] = getline(tag.start, tag.end)
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

function! s:getSourceData(package)

  let file = expand('%')
  call s:debug("gathering data from source file " . file)
  let tags1 = cdef#getTags()

  "fake global namespace
  let global1 = cdef#createTag("##global##", file, 0, "namespace", {"end": 1000000})
  call insert(tags1, global1, 0)
  let d1 = cdef#splitTags(tags1)
  call extend(a:package,  {"namespaces1":d1.namespaces, "usings1":d1.usings,
        \"classes1":d1.classes, "prototypes1":d1.prototypes, "functions1":d1.functions,
        \"tags1":tags1, "source" : file})

  let a:package["nsDict1"] = cdef#extendNamespaces(a:package.namespaces1, a:package.usings1)

  "check tag
  call s:checkEnd(a:package.namespaces1)
  call s:checkEnd(a:package.usings1)

  for func in a:package.functions1
    let func["namespace"] = cdef#getMostFitTag(a:package.namespaces1, func.line)
  endfor

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
  elseif getline(line('.')+1) =~ '\v\s*using|^\s*#|^\s*$'
    "must be a fresh new file, using or #balabala is last line
    call cursor(line('$'), 1)
  endif

  let a:package.namespaces1[0]["nextSlot"] = line('.')
endfunction

" define inlines, template related stuff in headfile namespace by namespace
" return [number of newly defined functions, last defined function]
function! cdef#defineHeadElements(package)
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

      call s:debug("define prototype : " . cdef#getPrototypeString(tag))
      let numDef += 1
      let text = s:generateFunction(tag, tag.namespace.fullName)
      call append(slot, text)
      let t1 = cdef#createTag(tag.name, a:package.head,
            \ slot+len(s:funcHat)+1+tag.line-tag.start, "function",
            \ {"end":slot + len(text), "namespace":tag.namespace })
      call cdef#insertManualEntry(a:package.tags0, t1, slot + 1, t1.end)
      let previous = t1
      let def = t1
    endfor
  endfor

  return [numDef, def]
endfunction

" define namespaces and functions in source file
" return [number of newly defined elements, last defined element]
function! cdef#defineSourceElements(package)

  let numDef = 0
  let def = {}
  let previous = {}
  let pattern = s:getUsedNamespacePattern(a:package.usings1)

  " get previous prototype or namespace(not using) for 1st element.
  for tag in a:package.box10
    if tag.kind == "namespace"
      let previous = get(a:package.nsDict1, tag.fullName, {})
      if previous != {} && previous.kind == 'using'
        let previous = {}
      endif
    else
      let previous = cdef#searchDefinition(tag, a:package.functions1, pattern)
    endif
    if previous != {} | break  | endif
  endfor

  for tag in a:package.box11

    let slot = s:getSourceNextSlot(previous, tag)

    if tag.kind == "namespace"
      let t1 = get(a:package.nsDict1, tag.fullName, {})
      if t1 != {}
        let def = t1
        if t1.kind != 'using'
          let previous = t1
        endif
        continue
      endif

      "define namespace
      let numDef += 1
      call s:debug("define namespace " . tag.fullName)
      let text = [
            \ '',
            \ 'namespace ' . tag.name ,
            \ '{',
            \ '}'
            \ ]
      call append(slot, text)

      let t1 = cdef#createTag(tag.name, a:package.source, slot+2, "namespace" ,
            \ {"end" : slot+4, "fullName" : tag.fullName, "firstSlot" : slot + 3,
            \ "dict":a:package.nsDict1,
            \ })
      if has_key(tag, "scope")
        let t1["scope"] = tag.scope
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

      call s:debug("define prototype : " . cdef#getPrototypeString(tag))
      let text = s:generateFunction(tag, tag.namespace.fullName)
      call append(slot, text)
      let t1 = cdef#createTag(tag.name, a:package.source,
            \ slot+len(s:funcHat)+1+tag.line-tag.start, "function",
            \ {"end":slot + len(text),
            \  "namespace" : a:package.nsDict1[tag.namespace.fullName] })
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
function! cdef#define(lstart, lend)
  if !cdef#isInHead()
    call cdef#notify("please switch to head file if you want to define something")
    return
  endif

  let wlnum0 = winline()
  call cdef#pushOptions({"eventignore":"all"}) | try

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
      call s:debug("switching to source file")
      call cdef#switchFile()
      call s:getSourceData(package)
      call s:debug("define functions in source file")
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

function! cdef#defineFile()
  call cdef#define(1, line('$'))
endfunction

function! cdef#defineTag()
  let tag = cdef#getTagAtLine()
  if tag == {} || tag.kind == "function" | return | endif

  if tag.kind == "prototype"
    call cdef#define(line('.'), line('.'))
  elseif has_key(tag, "end")
    call cdef#define(tag.line, tag.end)
  endif
endfunction

" replace \*= balabala
function! s:substituteDefaultValue(str, value, flag)
  return substitute(a:str, '\v[^)]{-}\zs\s*\=%(\s*\()@![^,]*\ze(,|\))', a:value, a:flag)
endfunction

" (prorotype, nsFullName [, withHat])
function! cdef#genFuncDefHead(prototype, nsFullName, ...)
  let withHat = get(a:000, 0, 1)

  call cdef#addStartEndToProtoAndFunc(a:prototype)
	if has_key(a:prototype, 'headLines')
		let funcHeadList = a:prototype.headLines
	else
		try
			let oldpos = getpos('.')
			call s:edit(a:prototype.file)
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
  if cdef#hasProperty(a:prototype, "static")
    let funcHead = substitute(funcHead, '\v\s*\zs<static>\s*', '', '')
  endif

  " add scope for class method only
  if a:prototype.class != {}
    let scope = get(a:prototype, "scope", "")
    if empty(scope)
      call s:fatel("something is wrong, method has no class scope")
    endif
    if !empty(a:nsFullName)  "strip namespace from scope
      if stridx(scope, a:nsFullName) == 0
        let scope = scope[len(a:nsFullName)+2:]
      endif
    endif

    let scope .= get(a:prototype.class, "template", "")

    " ctag always add extra blank after operator, it "changed" function name
    if stridx(a:prototype.name, "operator") == 0
      let funcHead = substitute(funcHead, '\V\<operator', scope.'::\0', '')
    else
      let funcHead = substitute(funcHead, '\V\<'.a:prototype.name, scope.'::\0', '')
    endif
  endif

  "comment default value, must be called before remove trailing
  let funcHead = s:substituteDefaultValue(funcHead, '/*\0*/', 'g')
  "remove static or virtual
  let funcHead = substitute(funcHead, '\vstatic\s*|virtual\s*', '', '' )
  "remove trailing
  let funcHead = substitute(funcHead, '\v\;\s*$', '', '')
  let arr = split(funcHead, '\n')
  if withHat
    let arr = s:funcHat + arr
  endif

  return arr
endfunction

function! s:mvFuncToProto(proto, func)
  call s:edit(a:func.file)
  let funcBody = s:getBlock(a:func.body)
  silent! execute a:func.range[0] ',' a:func.range[1] 'd'
  w
  call s:edit(a:proto.file)
  call cursor(a:proto.semicolon)|normal! x
  call append(line('.'), funcBody)
  execute printf('normal! =%dj', len(funcBody))
  w
endfunction

function! cdef#mvFunc()
  let tags = cdef#getTags()
  let t0 = cdef#getTagAtLine(line('.'), tags)
  if t0 == {} || (t0.kind != "prototype" && t0.kind != "function")
    return
  endif

  call cdef#getFuncDetail(t0)
  let t1 = cdef#searchMatch(t0, tags)
  if t1 != {}
    call cdef#getFuncDetail(t1)
  endif

  if t0.kind == "prototype"
    if t1 == {}
      call s:notify("not defined yet, nothing to mvoe") | return
    endif
    call s:mvFuncToProto(t0, t1)
  else
    if t1 != {}
      call s:mvFuncToProto(t1, t0)
    else
      if cdef#isInSrc()
        call s:notify("found no prototype, no where to move")
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
        call s:edit(t0.file)
        let t0 = cdef#getTagAtLine(t0.line, tags)
        let t1 = cdef#searchMatch(t0, tags)
        if t1 == {}
          call s:notify("failed to find slot for " + cdef#getPrototypeString(t0))
          return
        endif
        " replace definition body with original body
        call cdef#getFuncDetail(t1)
        call s:edit(t1.file)
        call s:rmBlock(t0.body)
        if cdef#isBlankLine()
          normal! "_dd
          normal! k
        endif
        call append(line('.'), funcBody)
        execute printf('normal! =%dj', len(funcBody))
        w
      endif
    endif
  endif

endfunction

" Rename prototype name or function local variable
function! cdef#rename()
	let tags = cdef#getTags()
  let tag = cdef#getTagAtLine(line('.'), tags)
  if tag!= {} && tag.kind == "prototype"
    call cdef#renameFunc(tag)
  else
    "check if in a function
    let functions = cdef#getTagFunctions(tags)
    let function = cdef#getMostFitTag(functions, line('.'))
    if function != {}
      call cdef#renameFunctionLocal(function)
    endif
  else
    call s:debug("can only rename prtotype and function local ")
  endif
endfunction

" Remove function definition and declaration and comment and blank
function! cdef#rmFunc()
  let tags = cdef#getTags()
  let t0 = cdef#getTagAtLine(line('.'), tags)
  let t1 = cdef#searchMatch(t0, tags)
  call cdef#getFuncDetail(t0)
  exec printf('%d,%dd', t0.range[0], t0.range[1])
  w
  call s:edit(t1.file)
  call cdef#getFuncDetail(t1)
  exec printf('%d,%dd', t1.range[0], t1.range[1])
  w
endfunction

function! cdef#renameFunc(prototype)
  try|echohl Question
    call s:updatePrototypeStep0()
    let newName = inputdialog("Input new name for ". prototype.name . ":")
    if len(newName) > 0
      exec 's/\v<' .prototpye.name  . '/' . newName
      call s:updatePrototypeStep1()
    endif
  finally|echohl None|endtry
endfunction

function! cdef#renameFunctionLocal(function)
	try
		let oldpos = getpos('.')
		echohl Question
		let varName = expand('<cword>')
		let newName = inputdialog("Input new name for ". varName . ":")
		if len(newName) > 0
			exec a:function.line . ',' . a:function.end . 's/\v<' . varName . '>/' . newName . '/g'
		endif
	finally
		echohl None
		call setpos('.', oldpos)
	endtry
endfunction

function! cdef#updatePrototype()
  if s:updateFunction == {}
    call s:updatePrototypeStep0
  else
    call s:updatePrototypeStep1
  endif
endfunction

function! s:updatePrototypeStep0()
  let tags = cdef#getTags()
  let t0 = cdef#getTagAtLine(line('.'), tags)
  if t0 == {} || t0.kind != "prototype"
    call s:notice("no prototype at line " . line('.'))
    return
  endif

  let classes = cdef#getTagClasses(tags)
  let namespaces = cdef#getTagNamespaces(tags)
  call cdef#extendNamespaces(namespaces, [])
  let t0["class"] = cdef#getMostFitTag(classes, t0.line)
  let t0["namespace"] = cdef#getMostFitTag(namespaces, t0.line)

  let s:updatingFunction = cdef#searchMatch(t0, tags)
  if s:updatingFunction != {}
    let s:updatingFunction["prototype"] = t0
    call s:notice( "Prepare to update " . cdef#getPrototypeString(t0))
  else
    call s:notice("this prototype has not been defined.")
  endif
endfunction

function! s:updatePrototypeStep1()
  if s:updatingFunction == {} | call s:warn("no function to update") | return | endif
  let prototype = s:updatingFunction.prototype
  if prototype == {}
    call s:debug("failed, prototype line must be chagned")
    let s:updatingFunction = {} | return
  endif

  let nsFullName = prototype.namespace == {} ? "" : prototype.namespace.fullName
  let funcHead = cdef#genFuncDefHead(prototype, nsFullName, 0)

  call s:edit(s:updatingFunction.file)
  let func = cdef#getFuncDetail(s:updatingFunction)
  call s:rmBlock(func.head)
  if cdef#isBlankLine() " above command might leave a blank line
    normal! "_dd
    normal! k
  endif
  call append(line('.'), funcHead)
  exec 'normal! =' . len(funcHead) . 'j'
  let s:updatingFunction = {}
endfunction

" (file, [, name [, property0, [property1 [,....]])
function! cdef#copyPrototype(file, ...)

  let targetFile = findfile(expand(a:file))
  if len(targetFile) == 0 | call s:notify("found no target file")|return | endif
  let name = get(a:000, 0, '.')

  try
    let oldpos = getpos('.')
	  call  s:edit(targetFile)
    let tags = cdef#getTags()
    let prototypes = cdef#getTagPrototypes(tags)

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
      let prototype = candidates[index]
      call cdef#addStartEndToProtoAndFunc(prototype)
      let selection = [""] + getline(prototype.start, prototype.end) + selection
    endfor
  finally
    call setpos('.', oldpos)
  endtry

  "trim left
  for i in range(len(selection))
    let selection[i] = substitute(selection[i], '\v^\s*', '', '')
  endfor

  if len(selection) > 0
    call append('.', selection)
  endif
endfunction

function! cdef#addHeadGate()
  let gatename = substitute(toupper(expand("%:t")), "\\.", "_", "g")
  exec "keepjumps normal! ggO#ifndef " . gatename
  exec "normal! o#define " . gatename
  exec "normal! o"
  exec "keepjumps normal! Go#endif /* " . gatename . " */"
  keepjumps normal! ggjj
endfunction

function! cdef#genGetSet(...)
  let opts = get(a:000, 0, {})
  call extend(opts, {"const":0, "register":"g", "entries":"gs"}, "keep")
  " q-args will pass empty register
  if opts.register == ''
    let opts.register = 'g'
  endif
  "add extra blink line if register is uppercase
  if misc#isUppercase(opts.register)
    exec 'let @'.opts.register.' = "\n"'
  endif

  let str = getline('.')
  let varType = misc#trim(matchstr(str, g:cdef#rexParamType))
  let varName = matchstr(str, g:cdef#rexVarName)

  let argType = opts.const ? 'const '.varType.'&':varType
  let funcPostName = varName
  "remove m from mName
  if funcPostName[0] == 'm' && misc#isUpperCase(funcPostName[1])
    let funcPostName = funcPostName[1:]
  endif
  "make sure 1st character is upper case
  let funcPostName = toupper(funcPostName[0]) . funcPostName[1:]

  "generate get set toggle
  if stridx(opts.entries, "g") != -1
    let res = argType.' get'.funcPostName."() const { return ".varName."; }\n"
  endif
  if stridx(opts.entries, "s") != -1
    let res .= 'void set'.funcPostName.'( '.argType.' v){'.varName." = v;}\n"
  endif
  if stridx(opts.entries, "t") != -1
    let res .= 'void toggle'.funcPostName."() { ".varName." = !". varName . "; }\n"
  endif

  exec 'let @'.opts.register.' = res'
endfunction

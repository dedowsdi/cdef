if exists("g:loaded_cdef")
  finish
endif
let g:loaded_cdef = 1

let g:cdef#ctagCmdPre = 'ctags -f - --excmd=number --sort=no --fields=KsSiea --fields-c++=+{properties}{template} --kinds-c++=+pNU --language-force=c++ '
let g:cdefNotifySeverity = get(g:, "cdefNotifySeverity", 3)
let s:templateSrc = expand('<sfile>:p:h:h').'/template/'
let s:updatingFunction = {}
let g:cdefDefaultSourceExtension = get(g: , "cdefDefaultSourceExtension", "cpp")

let s:srcExts = ['c', 'cpp', 'cxx', 'cc']
let s:headExts = ['h', 'hpp', '']
let s:funcBody = readfile(glob(s:templateSrc) . 'funcbody')
let s:funcHat = readfile(glob(s:templateSrc) . 'funchat')
let s:optionStack = []

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

function! s:rmBlock(block)
  let [lnum0,cnum0] = a:block[0]
  let [lnum1,cnum1] = a:block[1]
  
  call setline(lnum1, getline(lnum1)[1:cnum1-1])
  call setline(lnum0, getline(lnum0)[1:cnum0-1])
  let lstart = lnum0 + 1
  let lend = lnum1 - 1
  if lend >= lstart
    exec printf('%d,%dd',lstart, lend)
  endif
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
  let [startLine, startCol]= [line('.'), col('.')] | try
    call cursor(a:lnum, 1)
    if search('\v\S', 'bW')
      let range[0] = line('.') + 1
    endif
    call cursor(a:lnum, 1000000)
    if search('\v\S', 'W')
      let range[1] = line('.') - 1
    endif
    return range
  finally | call cursor(startLine, startCol) | endtry
endfunction

" add cmt:[l,l], blank:[l,l], head:[[l,c],[l,c]], body:[[l,c], [l,c]],
" semicolon:[l,c], range[l,l] to prototype or function
" (tag [, {"blank":, "cmt":}]). Blank only exists if cmt is available
function! cdef#getFuncDetail(tag, ...)
  if a:tag.kind != "prototype" && a:tag.kind != "function" | return  | endif

  call cdef#addStartEndToProtoAndFunc(a:tag)

  let opts = get(a:000, 0, {})
  call extend(opts, {"blank": 1, "cmt" : 1}, "keep")
  let [startLine, startCol, curFile] = [line('.'), col('.'), expand('%')]|try

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

  finally|call s:edit(curFile) |call cursor(startLine, startCol)|endtry
endfunction

" ([lnum])
function! cdef#getCmtRange(...)
  let [startLine, startCol] = [line('.'), col('.')]|try
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
  finally|call cursor(startLine, startCol)|endtry
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
    if g:cdefCreateSrc
      silent exec printf('%sedit%s.%s', cmdPre,  altDir.baseName, g:cdefDefaultSourceExtension)
    else
      call s:debug('Source file not found, you can set g:cdefCreateSrc=1 to create it automatically.')
    endif
  else
    throw 'Head file not found'
  endif

  return 0
endfunction

function! cdef#printAccessSpecifier(...)
  let tag = cdef#getTagAtLine()
  if tag && tag.has_key("access") 
    echo tag.access 
  endif
endfunction

function! cdef#printCurrentTag(...)
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
  let ctagCmd =  get(a:000, 0, g:cdef#ctagCmdPre . expand('%:p')  )
  let l = systemlist(ctagCmd)
  let tags = []
  for item in l
    let tags += [s:strToTag(item)]
  endfor
  return tags
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
    for tag in tags
      if tag.line == lnum
        return tag 
      endif 
    endfor
    return {}
  else
    let ctagCmd = g:cdef#ctagCmdPre . expand('%:p') . ' | grep -P ''\t'.lnum.''';'  
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

  let [startLine, startCol, curFile] = [line('.'), col('.'), expand('%')]|try
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
  finally|call s:edit(curFile)|call cursor(startLine, startCol)|endtry

endfunction

" Add fullname property. add end to using.
function! cdef#normalizeNamespaces(namespaces, usings)
  let d = {}

  for namespace in a:namespaces
    let namespace["fullName"] = has_key(namespace, "scope") ?
          \ namespace.scope.'::'.namespace.name : namespace.name
    let d[namespace.fullName] = namespace
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

function! s:getUsedNamespacePattern(usings, namespace)
  let pattern = ''
  for ns in a:usings
    "only use global using or using that have the same scope as namespace
    if a:namespace == {} || get(a:namespace, 'scope', '')  == get(ns, 'scope', '')
      " stip abc:: from abc::balabala  or ::abc from balabala::abc
      let pattern .= printf('(:)@<!<%s::|::%s$|', ns.name, ns.name)
    endif
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

" get function for prototype, prototype for function
function! cdef#searchMatch(t0)

  " search in current file
  if stridx(a:t0.name, "operator") == 0
    let reName =  '\b' . s:decorateFuncName(a:t0.name)
  else
    let reName = '\b' . escape(a:t0.name, '~') . '\b'
  endif
  let ctagCmd = printf('%s%s | grep -E ''^%s|using''',g:cdef#ctagCmdPre, expand('%:p'), reName)
  let tags0 = cdef#getTags(ctagCmd)
  let usings0 = cdef#getTagUsedNamespaces(tags0)
  let namespaces0 = cdef#getTagNamespaces(tags0)
  call cdef#normalizeNamespaces(namespaces0, usings0)
  let namespace = cdef#getMostFitTag(namespaces0, a:t0.line)
  let pattern = s:getUsedNamespacePattern(usings0, namespace)

  for t1 in tags0
    if t1.kind == a:t0.kind || (t1.kind != "prototype" && t1.kind != "function") | continue | endif
    if a:t0.line != t1.line && cdef#cmpProtoAndFunc(a:t0, t1, pattern)
      return t1
    endif
  endfor

  " search in alternate file
  let altFile = cdef#getSwitchFile()
  if len(altFile) == 0 | return 0 | endif

  let ctagCmd = printf('%s%s | grep -E ''^%s|using''',g:cdef#ctagCmdPre, altFile, reName)
  let tags1 = cdef#getTags(ctagCmd)
  let namespaces1 = cdef#getTagUsedNamespaces(tags1)
  let usings1 = cdef#getTagUsedNamespaces(tags1)
  call cdef#normalizeNamespaces(namespaces1, usings1)
  let pattern = s:getUsedNamespacePattern(usings0 + usings1, namespace)

  for t1 in tags1
    if t1.kind == a:t0.kind || (t1.kind != "prototype" && t1.kind != "function") | continue | endif
    if t1.name == a:t0.name && cdef#cmpProtoAndFunc(a:t0, t1, pattern)
      return t1
    endif
  endfor

  return {}
endfunction

function! cdef#switchBetProtoAndFunc()
  let t0 = cdef#getTagAtLine()
  if t0 != {} && (t0.kind == "prototype" || t0.kind == "function") && !cdef#isPure(t0)
    let t1 = cdef#searchMatch(t0)
    if t1 == {} | return 0 | endif
    silent! execute 'edit ' . t1.file
    call cursor(t1.line, 1) | normal! ^
    return 1
  else 
    return 0
  endif
endfunction

function! s:genFuncDef(prototype, nsFullName)
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
    let scope0 = get(a:t0, 'scope', '')
    let scope1 = get(a:t1, 'scope', '')
    let ssig0 = substitute(sig0, a:pattern, '', '') "stripped sig 0
    let ssig1 = substitute(sig1, a:pattern, '', '')
    let sscope0 = substitute(scope0, a:pattern, '', '') "stripped scope 0
    let sscope1 = substitute(scope1, a:pattern, '', '')
    if (sig0 == sig1 || sig0 == ssig1 || ssig0 == sig1 || ssig0 == ssig1) &&
          \ (scope0 == scope1 || scope0 == sscope1 || sscope0 == scope1 || sscope0 == sscope1)
      return 1 
    endif
  endif

  return 0
endfunction

function! cdef#searchDefinition(prototype, functions, pattern)
  if has_key(a:prototype, "function") | return a:prototype.function | endif

  for tag in a:functions
    if cdef#cmpProtoAndFunc(a:prototype, tag, a:pattern)
      let a:prototype["function"] = tag 
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

" pacage: {
" "boxes":{"namespace":,"group0":,"group1", 
"          "preGroup0":, "postGroup0":, "preGroup1":, "postGroup1": "start":, "end" },
"           box number = 1 + number of namespaces that contine lstart, lend. 
"           group0 will be define in head file, group1 in source file.
" "tags0": tags of head file
" "tags1": tags of source file
" "namespaces0":...
" "namespaces1":...
" "usings0":...
" "nsDict1":...
" "namespaces":namespace that will be created
" }. 
function! s:createPrototypePackage(tags0, tags1, lstart, lend)

  let package = {}

  let package["tags0"] = a:tags0
  let package["namespaces0"] = cdef#getTagNamespaces(a:tags0)
  "let package["usings0"] = cdef#getTagUsings(a:tags0)
  let package["classes0"] = cdef#getTagClasses(a:tags0)
  let package["prototypes0"] = cdef#getTagPrototypes(a:tags0)
  let package["functions0"] = cdef#getTagFunctions(a:tags0)

  let package["tags1"] = a:tags1
  let package["namespaces1"] = cdef#getTagNamespaces(a:tags1)
  let package["usings1"] = cdef#getTagUsings(a:tags1)
  "let package["classes1"] = cdef#getTagClasses(a:tags1)
  "let package["prototypes1"] = cdef#getTagPrototypes(a:tags1)
  let package["functions1"] = cdef#getTagFunctions(a:tags1)

  let package["prev0"] = {}
  let package["prev1"] = {}
  let package["namespaces"] = []

  call s:checkEnd(package.namespaces0)
  call s:checkEnd(package.classes0)
  call s:checkEnd(package.namespaces1)

  let package["nsDict0"] = cdef#normalizeNamespaces(package.namespaces0, [])

  "init packages. need some hack to use packages[0] as global scope namespace
  let package["boxes"] = [ {"namespace":{"name":"", "fullName":"", "line":1, "end":line('$')},
        \ "group0":[], "group1":[], "preGroup0":[], "postGroup0":[], "preGroup1":[], "postGroup1":[]} ]

  for namespace in package.namespaces0
    if namespace.line > a:lend || namespace.end < a:lstart | continue | endif
    let package.boxes += [{"namespace":namespace, "group0":[], "group1":[], 
          \ "preGroup0":[], "postGroup0":[], "preGroup1":[], "postGroup1":[] }]
    let package.namespaces += [namespace]
  endfor

  "distribute prototypes to package groups
  for prototype in package.prototypes0
    if cdef#isPure(prototype) | continue | endif

    let class = cdef#getMostFitTag(package.classes0, prototype.line)
    let groupNumber = s:getGroupNumber(prototype, class)

    call cdef#addStartEndToProtoAndFunc(prototype) 
    let prototype["headLines"] = getline(prototype.start, prototype.end)

    if has_key(prototype, "scope")
      let idx = cdef#getMostFitTagIndex(package.namespaces, prototype.line)
      let box = package.boxes[idx+1] " still work if idx is -1
    else
      let box = package.boxes[0]
    endif

    let prototype["class"] = class " need to get template parameter from class

    if groupNumber == 0
      if empty(box.group0)
        let box.preGroup0 = [prototype]  + box.preGroup0 " in reverse order
      else
        let box.postGroup0 += [prototype] 
      endif 
    else
      if empty(box.group1)
        let box.preGroup1 = [prototype] + box.preGroup1
      else
        let box.postGroup1 += [prototype] 
      endif 
    endif

    "let prototype.namespace = box.namespace
    " add restricted prototypes to group0 or group1
    if prototype.line < a:lstart || prototype.line > a:lend | continue | endif

    if groupNumber == 0
      call s:debug("distribute " . cdef#getPrototypeString(prototype)
            \ . " to " . box.namespace.name . " group 0")
      let box.group0 += [prototype]
    else
      call s:debug("distribute " . cdef#getPrototypeString(prototype) 
            \ . " to " . box.namespace.name . " group 1")
      let box.group1 += [prototype]
    endif
  endfor

  "remove 1st one from pre group
  for box in package.boxes
    let box.preGroup0 = box.preGroup0[0:-1]
    let box.preGroup1 = box.preGroup1[0:-1]
  endfor

  return package
endfunction

function! s:definePackageNamespaces(package)
  for namespace in a:package.namespaces
    if !has_key(a:package.nsDict1, namespace.fullName)
      call s:debug("define namespace " . namespace.fullName)
      call cdef#defineNamespace(namespace.fullName, a:package)
    endif
  endfor
endfunction

" recursively define a::b::c::d
function! cdef#defineNamespace(fullName, package)
  if has_key(a:package.nsDict1, a:fullName) 
    return a:package.nsDict1[a:fullName] 
  endif

  let parent = {}
  let idx = strridx(a:fullName, "::")
  let parentFullName = idx == -1 ? "" : a:fullName[:idx-1] 
  let parent = idx == -1 ? {} : cdef#defineNamespace(parentFullName, a:package)
  let name = idx == -1 ? a:fullName :  a:fullName[idx+2:]

  " check if any previous sibling has been defined 
  let prevNamespaces = cdef#filterTags(a:package.namespaces0, {"scope":parentFullName})
  let pastSelf = 0
  let previous = {}
  let next = {}

  " try to find sibling namespace
  for t0 in prevNamespaces
    if t0.fullName == a:fullName
      let pastSelf = 1 
      if previous != {} | break | endif
    endif

    let t1 = get(a:package.nsDict1, t0.fullName, {})
    if t1 == {} || t1.kind == "using" | continue | endif

    if pastSelf " the 1st one after self
      let next = t1 | break
    else " the last one before self
      let previous = t1 | continue
    endif
  endfor

  if previous != {}
    let slot = previous.end 
    call s:debug("find previous defined namespace " . previous.fullName . ' for ' . a:fullName)
  elseif next != {}
    let blanks = cdef#getBlankBlock(next.line - 1)
    let slot = empty(blanks) ? next.line - 1 : blanks[0] - 1
    call s:debug("find after defined namespace " . next.fullName . ' for ' . a:fullName)
  else
    let slot = line('$')
    call s:debug("find no sibling defined namespace for " .a:fullName)
  endif

  let text = [
        \ '',
        \ 'namespace ' . name ,
        \ '{',
        \ '}'
        \ ]
  "exec 'normal! '.slot.'Gonamespace '.name.'{}'
  call append(slot, text)

  "create manual tag
  let tag = cdef#createTag(name, expand('%:p'), slot+2, "namespace" , 
        \ {"end" : slot+4, "fullName" : a:fullName})
  if !empty(parentFullName)
    let tag["scope"] = parentFullName
  endif
  call cdef#insertManualEntry(a:package.tags1, tag, slot+1, tag.end)
  let a:package.nsDict1[a:fullName] = tag

  return tag
endfunction

function! s:getNamespaceFirstSlot(namespace)
  if a:namespace.name == ""
    return line('$')
  elseif a:namespace.kind == 'namespace'
    return a:namespace.end - 1
  else
    if has_key(a:namespace, 'scope')
      return a:namespace.end - 1
    else
      return line('$')  " the same as using.end
    endif
  endif
endfunction

function! cdef#definePackageGroup(package, numGroup)
  let file = expand('%:p')

  let functions = a:numGroup == 0 ? a:package.functions0 : a:package.functions1
  let usings = a:numGroup == 0 ? [] : a:package.usings1
  let tags = a:numGroup == 0 ? a:package.tags0 : a:package.tags1

  "define functions in headfile
  for i in range(len(a:package.boxes))
    let box = a:package.boxes[i]
    let namespace = box.namespace
    let pattern = s:getUsedNamespacePattern(usings, namespace)

    " set up namespace slot
    if a:numGroup == 0
      let group = box.group0
      let preGroup = box.preGroup0
      let postGroup = box.postGroup0
      let firstSlot = s:getNamespaceFirstSlot(namespace)
    else
      let group = box.group1
      let preGroup = box.preGroup1
      let postGroup = box.postGroup1
      if namespace.name == ""
        let firstSlot = line('$') 
      else
        if !has_key(a:package.nsDict1, namespace.fullName)
          call s:fatel("found undefined namespace : " . namespace.fullName)
        endif
        let firstSlot = s:getNamespaceFirstSlot(a:package.nsDict1[namespace.fullName])
      endif
    endif

    let previous = {}

    for prototype in group
      let t1 = cdef#searchDefinition(prototype, functions, pattern)
      if t1 != {} 
        call s:debug("ignore defined prototype : " . cdef#getPrototypeString(prototype))
        let previous = t1 | continue 
      elseif previous == {}
        " find slot for 1st prototype which is not defined in this group
        for proto in preGroup
          let previous = cdef#searchDefinition(proto, functions, pattern)      
          if previous != {} | break | endif
        endfor

        if previous == {}
          for proto in postGroup
            let next = cdef#searchDefinition(proto, functions, pattern)      
            if next != {}
              call cdef#getFuncDetail(next)
              let firstSlot = next.range[0] - 1 " above blank
              break
            endif
          endfor
        endif
      endif

      call s:debug("define prototype : " . cdef#getPrototypeString(prototype))
      let slot = previous == {} ? firstSlot : previous.end
      let funcDef = s:genFuncDef(prototype, namespace.fullName)
      call append(slot, funcDef)
      let t1 = cdef#createTag(prototype.name, file, slot+len(s:funcHat)+1, "function", 
            \ {"end":slot + len(funcDef)})
      call cdef#insertManualEntry(tags, t1, slot + 1, t1.end)
      let previous = t1
    endfor
  endfor
endfunction

" Implement prototypes, ignore pure virtual, inline implmention will always be
" added to the end of current namespace of end of file if there has no
" namespace. 
function! cdef#defineRange(lstart, lend)

  try|call cdef#pushOptions({"eventignore":"all"})
    call cdef#assertInHead()
    let [startLine, startCol, curFile] = [line('.'), col('.'), expand('%')]|try

      let tags0 = cdef#getTags()
      let altFile = cdef#getSwitchFile()
      let tags1 = cdef#getTags(g:cdef#ctagCmdPre . altFile)

      call s:debug("creating packages")
      let package = s:createPrototypePackage(tags0, tags1, a:lstart, a:lend)
      call s:debug("init " . len(package.boxes) . ' boxes')
      call s:debug("define functions in head file")

      call cdef#definePackageGroup(package, 0)
      call s:debug("switching to source file")
      w
      "impl in source file
      call cdef#switchFile()
      let package["nsDict1"] = cdef#normalizeNamespaces(package.namespaces1, package.usings1)
      call s:checkEnd(package.usings1)
      "define namespaces after swith to source file
      call s:definePackageNamespaces(package)

      call s:debug("define functions in source file")
      call cdef#definePackageGroup(package, 1)
      w

    finally|
      if a:lstart != a:lend
        call s:edit(curFile)
        call cursor(startLine, startCol) 
      endif
     endtry
  finally |call cdef#popOptions()| endtry

endfunction

function! cdef#defineFile()
  call cdef#defineRange(1, line('$'))
endfunction

function! cdef#defineTag()
  let tag = cdef#getTagAtLine()
  if tag == {} || tag.kind == "function" | return | endif

  if tag.kind == "prototype"
    call cdef#defineRange(line('.'), line('.')) 
  elseif has_key(tag, "end")
    call cdef#defineRange(tag.line, tag.end) 
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
    let [startLine, startCol, curFile] = [line('.'), col('.'), expand('%')]|try
      silent! exec 'edit ' . a:prototype.file
      let funcHeadList = getline(a:prototype.line, a:prototype.end)
    finally|silent! exec 'edit '.curFile|call cursor(startLine, startCol)|endtry
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
  let t0 = cdef#getTagAtLine()
  if t0 == {} || (t0.kind != "prototype" && t0.kind != "function")
    return 
  endif

  call cdef#getFuncDetail(t0)
  let t1 = cdef#searchMatch(t0)
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
        if cdef#isBlankLine()
          normal! "_dd
          normal! k
        endif
        normal! A;
        w
        call cdef#defineRange(t0.line, t0.line)
        let t0 = cdef#getTagAtLine()
        let t1 = cdef#searchMatch(t0)
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
  let tag = cdef#getTagAtLine(tag)
  if tag!= {} && tag.type == "prototype"
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
  let t0 = cdef#getTagAtLine()
  let t1 = cdef#searchMatch(t0)
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
  let [startLine, startCol] = [line('.'), col('.')] |echohl Question| try
    let varName = expand('<cword>')
    let newName = inputdialog("Input new name for ". varName . ":")
    if len(newName) > 0
      exec a:function.line . ',' . a:function.end . 's/\v<' . varName . '>/' . newName . '/g'
    endif
  finally|echohl None|call cursor(startLine, startCol)|endtry
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
  call cdef#normalizeNamespaces(namespaces, [])
  let t0["class"] = cdef#getMostFitTag(classes, t0.line)
  let t0["namespace"] = cdef#getMostFitTag(namespaces, t0.line)

  let s:updatingFunction = cdef#searchMatch(t0) 
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
  let [startLine, startCol, curFile] = [line('.'), col('.'), expand('%:p')]

  let targetFile = findfile(expand(a:file))
  if len(targetFile) == 0 | call s:notify("found no target file")|return | endif
  let name = get(a:000, 0, '.')

  try|silent! s:edit(targetFile)
    let ctags = cdef#getTags()
    let prototypes = cdef#getTagPrototypes(ctags)

    let candidates = []
    for prototype in prototypes
      if match(prototype.name, '\v'.name) != -1
        for property in a:000[1:]
          if !cdef#hasProperty(prototype, property) | continue  | endif     
          let candidates += [prototype]
        endfor
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
    silent! s:edit(curFile)|call cursor(startLine, startCol)
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

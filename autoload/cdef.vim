let g:cdef_ctag_cmd_pre = 'ctags 2>/dev/null
      \ -f -
      \ --excmd=number
      \ --sort=no
      \ --fields=KsSe
      \ --fields-c++=+{properties}{template}
      \ --kinds-c++=ncsfp
      \ --language-force=c++ '
let g:cdef_default_source_extension = get(g: , 'cdef_default_source_extension', 'cpp')
let g:cdef_proj_name = get(g:, 'cdef_proj_name', '')
let g:cdef_with_hat = get(g:, 'cdef_with_hat', 0)
let s:src_exts = ['c', 'cpp', 'cxx', 'cc', 'inl']
let s:head_exts = ['h', 'hpp', '']

let s:template_src = expand('<sfile>:p:h:h').'/template/'
let s:func_body = readfile(glob(s:template_src) . 'funcbody')
let s:func_hat = readfile(glob(s:template_src) . 'funchat')
let s:option_stack = []
let s:updating_function = {}
let s:candidates = []

let g:cdef_notify_severity = get(g:, 'cdef_notify_severity', 3)
let s:NOTIFY_ALWAYS = 0
let s:NOTIFY_FATEL = 1
let s:NOTIFY_WARN = 2
let s:NOTIFY_NOTICE = 3
let s:NOTIFY_INFO = 4
let s:NOTIFY_DEBUG = 5
let s:NOTIFY_TRIVIAL = 6

function s:notify(msg, ...) abort
  let lvl = get(a:000, 0, s:NOTIFY_NOTICE)
  if lvl > g:cdef_notify_severity | return | endif
  if lvl == s:NOTIFY_FATEL
    echoe a:msg
  else
    echom a:msg
  endif
endfunction

function s:always(msg) abort
  call s:notify(a:msg, s:NOTIFY_ALWAYS)
endfunction
function s:fatel(msg) abort
  call s:notify(a:msg, s:NOTIFY_FATEL)
endfunction
function s:warn(msg) abort
  call s:notify(a:msg, s:NOTIFY_WARN)
endfunction
function s:notice(msg) abort
  call s:notify(a:msg, s:NOTIFY_NOTICE)
endfunction
function s:info(msg) abort
  call s:notify(a:msg, s:NOTIFY_INFO)
endfunction
function s:debug(msg) abort
  call s:notify(a:msg, s:NOTIFY_DEBUG)
endfunction
function s:trivial(msg) abort
  call s:notify(a:msg, s:NOTIFY_TRIVIAL)
endfunction

function s:open(file) abort
  let nr = bufnr(a:file)
  if nr == bufnr('') | return | endif
  if nr != -1
    exec printf('buffer %d', nr) 
  else
    silent! exec 'edit ' . a:file
  endif
endfunction

function s:str_to_tag(str) abort
  let l = split(a:str, "\t")

  if len(l) < 3 | echom 'failed to parse "' . a:str . "'" | return {} | endif

  " first 4 parts is fixed
  let d = {'name':l[0], 'file':l[1], 'line':str2nr(l[2][:-3]), 'kind':l[3]}

  " name of `int operator[] (...)`  will contain trailing space, it must be removed
  let d.name = trim(d.name)

  " always use class
  if d.kind =~# '^s' | let d.kind = 'class' | endif

  " assume name:value format from 5th part
  for item in l[4:]
    let idx = stridx(item, ':')
    let [field, content] = [item[0:idx-1], item[idx+1:]]
    let d[field] = content
  endfor

  " in source file, class is balabala:: before function name, class includes the
  " outer namespace, no matter in head or source file. ctag didn't add namespace
  " if it already add class.
  if has_key(d, 'struct') | let d['class'] = d.struct | endif

  " the scope part can be skipped if ctags is created with Z field
  if d.kind =~# '^[pf]'
    call extend(d, {'class':'', 'namespace':'', 'class_tag':{}, 'namespace_tag':{}}, 'keep')
    if !empty(d.class)
      let d.scope = d.class
    elseif !empty(!d.namespace)
      let d.scope = d.namespace
    else
      let d.scope = ''
    endif

    let d.fullname = has_key(d, 'scope') ? d.scope.'::'.d.name : d.name
  endif

  return d
endfunction

function cdef#has_property(tag, property) abort
  return has_key(a:tag, 'properties') &&  stridx(a:tag.properties, a:property) != -1
endfunction

function cdef#is_pure(tag) abort
  return cdef#has_property(a:tag, 'pure')
endfunction

function cdef#is_deleted(tag) abort
  return cdef#has_property(a:tag, 'delete')
endfunction

function cdef#is_inline(tag) abort
  return cdef#has_property(a:tag, 'inline')
endfunction

function cdef#is_virtual(tag) abort
  return cdef#has_property(a:tag, 'virtual')
endfunction

function cdef#is_static(tag) abort
  return cdef#has_property(a:tag, 'static')
endfunction

function cdef#is_const(tag) abort
  return cdef#has_property(a:tag, 'const')
endfunction

function cdef#has_template(tag) abort
  return has_key(a:tag, 'template')
endfunction

function s:systemlist(unix_cmd)
  if has('win32')
    try
      let bak = &shellslash
      set noshellslash

      " replace root drive with /mnt/...
      let cmd = substitute(a:unix_cmd, '\v\c<([c-z]):/', '/mnt/\l\1/', 'g')
      let l = systemlist('bash -c ' . shellescape(cmd))
      return l
    finally
      let &shellslash = bak
    endtry
  else
    return systemlist(a:unix_cmd)
  endif
endfunction

" [cmd [, pattern]]
function cdef#get_tags(...) abort
  let ctag_cmd = get(a:000, 0, g:cdef_ctag_cmd_pre . expand('%:p')  )
  let pattern = get(a:000, 1, '')
  let l = s:systemlist(ctag_cmd)
  if !empty(l) && l[0][0:4] ==# 'ctags:'
    throw printf('ctag cmd failed : %s\n. Error message:%s', ctag_cmd, string(l))
  endif

  if pattern !=# ''
    let l = filter(l, { i, v -> v =~? pattern })
  endif

  "let tags = [cdef#create_tag('##global##', '', 0, 'namespace', {'end': 1000000, 'fullname': '##global##'})]
  "let namespace_stack = [tags[0]]
  let [tags, namespace_stack, class_stack] = [[], [], []]

  for item in l
    let tag = s:str_to_tag(item)
    if tag.kind ==# 'slot' | continue | endif
    " ignore signal prototype, which always fallowed by a signal kind tag
    if tag.kind ==# 'signal' | call remove(tags, -1) | continue | endif

    let tags += [tag]
    " setup class name namespace for prototype and function
    while !empty(namespace_stack) && namespace_stack[-1].end < tag.line
      call s:trivial(printf('tag : pop namespace %s', namespace_stack[-1].name))
      call remove(namespace_stack, -1)
    endwhile

    while !empty(class_stack) && class_stack[-1].end < tag.line
      call s:trivial(printf('tag : pop class %s', class_stack[-1].name))
      call remove(class_stack, -1)
    endwhile

    if tag.kind ==# 'namespace'
      if !has_key(tag, 'end')
        call s:fatel(printf('namespace %s at line %d has no end, something must be seriously wrong',
              \ tag.name, tag.line))
        return
      endif
      call s:trivial(printf('tag : push namespace %s', tag.name))
      let tag.full_name = empty(namespace_stack)
            \ ? tag.name : namespace_stack[-1].name . '::' . tag.name
      let namespace_stack += [tag]
    elseif tag.kind ==# 'class'
      if !has_key(tag, 'end')
        call s:fatel(printf('class %s at line %d has no end, something must be seriously wrong', 
              \ tag.name, tag.line))
        return
      endif
      call s:trivial(printf('tag : push class %s', tag.name))
      let class_stack += [tag]
    elseif tag.kind =~# '^[pf]'
      let tag['class_tag'] = get(class_stack, -1, {})
      let tag['namespace_tag'] = get(namespace_stack, -1, {})
      if tag.namespace_tag != {} | let tag.namespace = tag.namespace_tag.full_name | endif
    endif
  endfor

  if has('win32')
    for tag in tags
      let tag.file = substitute(tag.file, '\v\C/mnt/([a-z])>', '\1:', 'g')
    endfor
  endif
  return tags
endfunction

function cdef#create_tag(name, file, line, kind, ...) abort
  let tag = {'name':a:name, 'file':a:file, 'line':a:line, 'kind':a:kind}
  call extend(tag, get(a:000, 0, {}), 'keep') | return tag
endfunction

function cdef#find_tag(tags, lnum) abort
  let l = filter(copy(a:tags), 'v:val.line == a:lnum')
  return empty(l) ? {} : l[0]
endfunction

"([line])
function cdef#get_tag_at_line(...) abort
  let lnum = get(a:000, 0, line('.'))
  let pattern = printf('\v\t%d;"', lnum)
  let tags = cdef#get_tags(g:cdef_ctag_cmd_pre . expand('%:p'), '\v\s', pattern)
  return cdef#find_tag(tags, lnum)
endfunction

function cdef#pf_to_string(tag) abort
  let str = a:tag.name . cdef#handle_default_value(a:tag.signature, ')', 1)
  if has_key(a:tag, 'scope')
    let str = a:tag.scope . '::' . str
  endif
  if has_key(a:tag, 'properties')
    let str = str . ':' . a:tag.properties
  endif
  let str = cdef#get_template(a:tag) . str
  return str
endfunction

function cdef#get_prototype_string(prototype) abort
  let str = a:prototype.name . cdef#handle_default_value(a:prototype.signature, ')', 1)
  if has_key(a:prototype, 'scope')
    let str = a:prototype.scope . '::' . str
  endif
  if has_key(a:prototype, 'properties')
    let str = str . ':' . a:prototype.properties
  endif
  let str = cdef#get_template(a:prototype) . str
  return str
endfunction

" [kind [,lnum]]
function cdef#goto_prev_tag(...) abort
  let kind = get(a:000, 0, '')
  let lnum = get(a:000, 1, line('.'))
  let tags = filter(cdef#get_tags(), {i,v -> v.line < lnum})
  if !empty(kind)
    let tags = filter( tags, { i,v -> v.kind =~# '^' . kind } )
  endif

  if empty(tags)
    return 0
  else
    exe tags[-1].line
    return 1
  endif
endfunction

function cdef#goto_tag_end() abort
  let tag = cdef#get_tag_at_line()
  if empty(tag) || !has_key(tag, 'end')
    return 0
  else
    exe tag.end
    return 1
  endif
endfunction

function cdef#goto_new_func_slot() abort
  if cdef#goto_prev_tag('p') && cdef#switch_proto_func() && cdef#goto_tag_end()
    norm! zz
    return 1
  else
    return 0
  endif
endfunction

function s:scroll(lnum) abort
  try
    let bak = &scrolloff
    set scrolloff=0
    let wlnum = winline()
    if a:lnum > wlnum
      exec printf('normal! %d', a:lnum - wlnum)
    elseif a:lnum < wlnum
      exec printf('normal! %d', wlnum - a:lnum)
    endif
  finally
    let &scrolloff = bak
  endtry
endfunction

" t0 : current tag, will be passes by function arglist
" t1 : lhs
" t2 : rhs
" scopes will be splited by :: and compared from right to left, the one with the
" more matched scope win(return -1), if they have the same matches, the one with
" less scopes win
function s:compare_candidate(t0, t1, t2)
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

function cdef#reset_candidates(tag, candidates)
  let [s:candidates, s:candidate_index] = [a:candidates, 0]
  " if current tag has no scope, remove all class or namespace items
  if empty(a:tag.scope) | call filter(s:candidates, 'empty(v:val.scope)') | endif

  call sort(s:candidates, function('s:compare_candidate', [a:tag]))
  for cand in s:candidates
    call s:debug('add candidates : ' . cdef#pf_to_string(cand))
  endfor
endfunction

function cdef#select_candidate(idx) abort
  if empty(s:candidates) || a:idx >= len(s:candidates)
    echohl WarningMsg | echo a:idx 'overflow' | echohl None | return
  endif
  let s:candidate_index = a:idx
  let tag = s:candidates[a:idx]
  call s:open(tag.file) | call cursor(tag.line, 1) | normal! ^
  if len(s:candidates) > 1
    echo printf('select (%d/%d)', s:candidate_index+1, len(s:candidates))
  endif
endfunction

function cdef#select_next_candidate() abort
  if empty(s:candidates) | return | endif
  let next_index = s:candidate_index + 1
  if next_index == len(s:candidates)
    let next_index = 0
    if len(s:candidates) != 1
      echohl WarningMsg | echo 'hit last, continue at first' | echohl None
    endif
  endif
  call cdef#select_candidate(next_index)
endfunction

function s:search_functions(proto_tag, tags) abort
  let res = []
  for func_tag in a:tags
    if func_tag.kind !~# '^f' | continue | endif
    if cdef#cmp_proto_and_func(a:proto_tag, func_tag) | call add(res, func_tag) | endif
  endfor
  return res
endfunction

function cdef#search_functions(proto_tag, tags, alt_file) abort
  call s:debug('search functions for : ' . cdef#pf_to_string(a:proto_tag))
  let l = s:search_functions(a:proto_tag, a:tags)
  " search in alternate file
  if !empty(a:alt_file)
    let ctag_cmd = g:cdef_ctag_cmd_pre . a:alt_file
    let pattern = printf('\v\snamespace\s|\sclass\s|\sstruct\s|\V\^%s\.\*\<function\>', a:proto_tag.name)
    let l += s:search_functions(a:proto_tag, cdef#get_tags(ctag_cmd, pattern))
  endif
  call cdef#reset_candidates(a:proto_tag, l)
endfunction

function s:search_prototypes(proto_tag, tags) abort
  let res = []
  for func_tag in a:tags
    if func_tag.kind !~# '^p' | continue | endif
    if cdef#cmp_proto_and_func(func_tag, a:proto_tag) | call add(res, func_tag) | endif
  endfor
  return res
endfunction

function cdef#search_prototypes(func_tag, tags0, alt_file) abort
  call s:debug('search prototypes for : ' . cdef#pf_to_string(a:func_tag))
  let l = s:search_prototypes(a:func_tag, a:tags0)
  " search in alternate file
  if !empty(a:alt_file)
    let ctag_cmd = g:cdef_ctag_cmd_pre . a:alt_file
    let pattern = printf('\v\snamespace\s|\sclass\s|\sstruct\s|\V\^%s\.\*\<prototype\>', a:func_tag.name)
    let l += s:search_prototypes(a:func_tag, cdef#get_tags(ctag_cmd, pattern))
  endif
  call cdef#reset_candidates(a:func_tag, l)
endfunction

" Switch between prototype and function. All function or prototype with the same
" signature are considered as candidates, they are sorted by their scope, the
" most matching one is selected first, all of them are added to s:candidates.
function cdef#switch_proto_func() abort
  let tags = cdef#get_tags()
  let t0 = cdef#find_tag(tags, line('.'))
  if t0 == {} || t0.kind !~# '^[pf]' | return 0 | endif

  let wlnum0 = winline()
  let alt_file = cdef#get_switch_file()
  let t1 = t0.kind =~# '^p' ?
        \ cdef#search_functions(t0, tags, alt_file) : cdef#search_prototypes(t0, tags, alt_file)
  if empty(s:candidates) | return 0 | endif
  call cdef#select_candidate(0) | call s:scroll(wlnum0) | return 1
endfunction

function s:gen_func(prototype, strip_namespace, ...) abort
  let head_only = get(a:000, 0, 0)
  let head = cdef#gen_func_head(a:prototype, a:strip_namespace)

  if head_only
    return head
  endif

  let body = deepcopy(s:func_body)
  return head + s:func_body
endfunction

function cdef#get_template(tag) abort
  let template = ''

  if has_key(a:tag.class_tag, 'template')
    let template = printf('template%s', a:tag.class_tag.template)
  endif

  if has_key(a:tag, 'template')
    let template = printf('%stemplate%s', template, a:tag.template)
  endif

  let template = cdef#handle_default_value(template , '>', 1)

  return template
endfunction

" the order matters, you can't place `singed` before `singed int`, it will
" produce garbage such as `int int`
let s:space_types = [
      \ ['\v<unsigned\s+long\s+long\s+int> ' , 'unsigned_long_long'],
      \ ['\v<unsigned\s+long\s+long>'        , 'unsigned_long_long'],
      \
      \ ['\v<signed\s+long\s+long\s+int>'    , 'long_long'],
      \ ['\v<signed\s+long\s+long>'          , 'long_long'],
      \ ['\v<long\s+long\s+int>'             , 'long_long'],
      \ ['\v<long\s+long>'                   , 'long_long'],
      \
      \ ['\v<unsigned\s+long\s+int>'         , 'unsigned_long'],
      \ ['\v<unsigned\s+long>'               , 'unsigned_long'],
      \
      \ ['\v<signed\s+long\s+int>'           , 'long'],
      \ ['\v<long\s+int>'                    , 'long'],
      \ ['\v<signed\s+long>'                 , 'long'],
      \
      \ ['\v<unsigned\s+short\s+int>'        , 'unsigned_short'],
      \ ['\v<unsigned\s+short>'              , 'unsigned_short'],
      \
      \ ['\v<signed\s+short\s+int>'          , 'short'],
      \ ['\v<short\s+int>'                   , 'short'],
      \ ['\v<signed\s+short>'                , 'short'],
      \
      \ ['\v<unsigned\s+int>'                , 'unsigned'],
      \
      \ ['\v<signed\s+int>'                  , 'int'],
      \ ['\v<signed>'                        , 'int'],
      \ ]

function cdef#cmp_sig(s0, s1) abort
  if a:s0 == a:s1 | return 1 | endif

  if xor(a:s0[-5:-1] ==# 'const', a:s1[-5:-1] ==# 'const') | return 0 | endif

  " replace space types
  let [s0, s1] = [a:s0, a:s1]
  for [key, value] in s:space_types
    let s0 = substitute(s0, key, value, 'g')
    let s1 = substitute(s1, key, value, 'g')
  endfor
  " try again after space type replacement
  if a:s0 == a:s1 | return 1 | endif

  let [l0, l1] = [split(s0, ','), split(s1, ',')]
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
    let [i0,i1] = [strridx(arg0, ' '), strridx(arg1, ' ')]
    " returen if either of them is anomymous
    if i0 == -1 || i1 == -1 | return | endif
    if arg0[0:i0] != arg1[0:i1] | return 0 | endif
    if arg0[i0 :] =~# '\v\w+' && arg1[i1 :] =~# '\v\w+' | continue | endif

    return 0
  endfor

  return 1
endfunction

function s:print_cmp_result(desc, t0, t1) abort
  if g:cdef_notify_severity >= s:NOTIFY_TRIVIAL
    call s:trivial(a:desc)
    call s:trivial(printf('    %s', cdef#get_prototype_string(a:t0)))
    call s:trivial(printf('    %s', cdef#get_prototype_string(a:t1)))
  endif
endfunction

" namespaces and classes are ignored
function cdef#cmp_proto_and_func(t0, t1) abort
  if a:t0.name !=# a:t1.name | return 0 | endif

  let sig0 = cdef#handle_default_value(a:t0.signature, ')', '1')
  let sig1 = cdef#handle_default_value(a:t1.signature, ')', '1')

  " remove scope before compare signature
  let sig0 = substitute(sig0, '\v<\w+\:\:', '', 'g')
  let sig1 = substitute(sig1, '\v<\w+\:\:', '', 'g')

  if !cdef#cmp_sig(sig0, sig1)
    call s:print_cmp_result('compare signature failed', a:t0, a:t1) | return 0
  endif

  if substitute(cdef#get_template(a:t0), '\v<class>', 'typename', 'g') !=#
        \ substitute(cdef#get_template(a:t1), '\v<class>', 'typename', 'g')
    call s:print_cmp_result('compare template failed', a:t0, a:t1)
    return 0
  endif

  return 1
endfunction

function s:get_prototype_namespace_full_name() dict abort
  return self.namespace.fullname
endfunction

function s:hook_method(tags, name, ref_name) abort
  for tag in a:tags
    let tag[a:name] = function(a:ref_name)
  endfor
endfunction

" if you want to search > for < , make sure start is greater than pos of <
function s:search_string_over_pairs(str, start, target, open_pairs, close_pairs, direction) abort
  if a:start >= len(a:str) | return -1 | endif

  let step = a:direction ==# 'l' ? 1 : -1
  let pairs0 = a:direction ==# 'l' ? a:open_pairs : a:close_pairs
  let pairs1 = a:direction ==# 'l' ? a:close_pairs : a:open_pairs
  let [stack, pos, size] = [[], a:start, len(a:str)]

  while pos >= 0 && pos < size
    let c = a:str[pos]
    if len(stack) == 0 && stridx(a:target, c) != -1 | return pos | endif
    let pos += step
    " ignore everyting except open or close char of current pair
    if len(stack) != 0
      " search matching pair
      if c ==# pairs1[ stack[-1] ]
        call remove(stack, -1)
      elseif c ==# pairs0[ stack[-1] ]
        let stack += stack[-1]
      endif
      continue
    endif
    " check open pair
    let idx = stridx(pairs0, c)
    if idx != -1 | let stack += [ idx ] | continue | endif
  endwhile

  return -1
endfunction

" operation:
"   0 : comment
"   1 : remove
" boundary : > for template, ) for function parameter
function cdef#handle_default_value(str, boundary, operation) abort
  " skip 1st ( of operator()()
  let pos = a:boundary ==# ')' ? stridx(a:str, '(') : 0
  let dvs = []  " default values, [[startPos, endPos], ...]
  let [open_pairs, close_pairs, target] = ['<([{"', '>)]}"', ','.a:boundary]

  " get =, ignore !=, +=,etc
  while 1
    " let frag = matchstrpos(a:str, '\v\s*([!%^&|+\-*/<>])@<!\=', pos + 1)
    let frag = matchstrpos(a:str, '\v\s*\=', pos + 1)
    if frag[2] == -1 | break | endif
    let pos = s:search_string_over_pairs(a:str, frag[2], target, open_pairs, close_pairs, 'l')
    if pos == -1  && a:boundary ==# '>'
      " universal-ctags failed to parse template with default template value:
      " template<typename T = vector<int> > class ...
      " the last > will be ignored by ctags
      "let pos = len(a:str) - 1
    endif
    let dvs += [ [frag[1], pos-1] ]
  endwhile

  if empty(dvs) | return a:str | endif

  let [res_str, pos] = ['', 0]
  if a:operation == 1
    for pair in dvs
      let res_str .= a:str[pos : pair[0] - 1]
      let pos = pair[1] + 1
    endfor
    let res_str .= a:str[pos : ]
  else
    for pair in dvs
      let res_str .= a:str[pos : pair[0] - 1] . '/*' . a:str[pair[0] : pair[1]] . '*/'
      let pos = pair[1] + 1
    endfor
    let res_str .= a:str[pos : ]
  endif

  " handle > bug
  "if a:boundary ==# '>' && res_str[ len(res_str)-1 ] !=# '>' | let res_str .= '>' | endif
  return res_str
endfunction

function s:get_template_start(tag) abort
  try
    let cview = winsaveview()
    call cursor(a:tag.line, 1)
    if cdef#has_template(a:tag)
      if !search('\v^\s*<template>\_s*\<', 'bW', '')
        throw 'faled to get template start '
      endif
    endif
    let lnum = line('.')
    return lnum
  finally
    call winrestview(cview)
  endtry
endfunction

" start = template line, end = ; line
function s:add_start_and_to_proto(proto) abort
  if a:proto.kind !~# '^p' | return | endif
  if has_key(a:proto, 'start') && has_key(a:proto, 'end') | return | endif

  try
    let cview = winsaveview()
    call cursor(a:proto.line, 1)
    if search('\v(operator\s*\(\s*\))?\zs\(')
      normal! %
      if search('\v\_s*;')  | let a:proto['end'] = line('.')
      else
        throw 'failed to add end to ' . cdef#pf_to_string(a:proto)
      endif
    endif
    let a:proto.start = s:get_template_start(a:proto)
  finally
    call winrestview(cview)
  endtry
endfunction

function s:select_a_space() abort
  let end_lnum = line('.')

  " search next non-blank lines or last line
  if search('\v^.*\S|%$', 'W')
    if getline('.') =~# '\S'
      -
    endif
    return
  endif

  " if no space after endline, search backward from startline
  if line('.') == end_lnum
    normal! o0
    " search previous non-blank lines or first line
    if search('\v^.*\S|%1l', 'bW')
      if getline('.') =~# '\S'
        +
      endif
    endif
    normal! o^
  endif
  
endfunction

" select function or prototype
" [kind]
function cdef#sel_pf(ai, ...) abort
  if a:0 > 0
    let tags = filter( cdef#get_tags(), { i,v -> v.kind =~# '^' . a:1 } )
  else
    let tags = filter( cdef#get_tags(), { i,v -> v.kind =~# '^[fp]'  } )
  endif

  let [tag, pos] = [{}, getpos('.')]
  for item in tags
    if item.kind =~# '^p'
      call s:add_start_and_to_proto(item)
    else
      let item.start = s:get_template_start(item)
    endif
    if pos[1] >= item.start && pos[1] <= item.end
      let tag = item | break
    endif
  endfor

  if tag == {} | return | endif
  call cursor(tag.start, 0)
  normal! V
  call cursor(tag.end, 0)
  if a:ai ==# 'a'
    call s:select_a_space()
  endif
endfunction

" select class or struct
function cdef#sel_class(ai) abort
  let tags = filter( cdef#get_tags(), { i,v -> v.kind =~# '^[cs]'} )
  let [tag, pos] = [{}, getpos('.')]
  for item in tags
    let item.start = s:get_template_start(item)
    if pos[1] >= item.start && pos[1] <= item.end
      let tag = item | break
    endif
  endfor

  if tag == {} | return | endif
  call cursor(tag.start, 0)
  normal! V
  call cursor(tag.end, 0)
  if a:ai ==# 'a'
    call s:select_a_space()
  endif
endfunction

" (proro, strip_namespace )
function cdef#gen_func_head(proto, strip_namespace, ...) abort
  call s:add_start_and_to_proto(a:proto)
  let func_head_list = getline(a:proto.start, a:proto.end)

  "trim left
  let num_spaces = 10
  for i in range(len(func_head_list))
    let num_spaces = min([num_spaces, len(matchstr(func_head_list[i], '\v^\s*'))])
  endfor
  for i in range(len(func_head_list))
    let func_head_list[i] = func_head_list[i][num_spaces :]
  endfor

  let func_head = join(func_head_list, "\n")
  if cdef#has_property(a:proto, 'static')
    let func_head = substitute(func_head, '\v\s*\zs<static>\s*', '', '')
  endif

  let scope = ''
  if empty(a:proto.class)
    if !a:strip_namespace | let scope = a:proto.namespace | endif
  else
    let scope = a:proto.class
    if a:strip_namespace && !empty(a:proto.namespace)
      if stridx(scope, a:proto.namespace) != 0
        throw 'unknown state, tag class does''t start with namespace : '.cdef#pf_to_string(a:proto)
      endif
      let scope = scope[len(a:proto.namespace)+2:]
    endif
  endif

  "comment default value, must be called before remove trailing
  let func_head = cdef#handle_default_value(func_head, ')', 1)
  if cdef#has_template(a:proto)
    let func_head = cdef#handle_default_value(func_head, '>', 1)
  endif
  "remove static or virtual
  let func_head = substitute(func_head, '\vstatic\s*|virtual\s*', '', '' )
  "remove trailing
  let func_head = substitute(func_head, '\v(override)?\s*\;\s*$', '', '')

  " add class template
  if has_key(a:proto.class_tag, 'template')
    let template = cdef#handle_default_value(a:proto.class_tag.template, '>', 1)
    let scope .= substitute(template, '\v<typename>\s*|<class>\s*', '', '')
    let func_head = printf("template%s\n%s", template, func_head)
  endif

  " add scope
  if !empty(scope)
    " ctag always add extra blank after operator, it 'changed' function name
    if stridx(a:proto.name, 'operator') == 0
      let func_head = substitute(func_head, '\V\<operator', scope.'::\0', '')
    else
      " should i use ~ instead of of \W?
      let func_head = substitute(func_head, '\V\(\W\|\^\)\zs'.a:proto.name.'\>', scope.'::\0', '')
    endif
  endif

  let arr = split(func_head, "\n")
  if g:cdef_with_hat
    let arr = s:func_hat + arr
  else
    call insert(arr, '')
  endif
  return arr
endfunction

function cdef#func_to_proto(...) abort

  let reg = get(a:000, 0, '"')

  " select function
  call cdef#sel_pf('a', 'f')
  if mode() !=# 'V'
    return 0
  endif

  " delete function into register
  exe "norm! \<esc>$"
  let start_line = getpos("'<")[1]
  if !search('}', 'cbW')
    throw '} not found'
  endif
  norm! v%

  " search for member initializer list
  call search('\v:@<!::@!', 'bW', start_line)
  exe printf("norm! \"%sd", reg)

  " clear blank line after deletion
  if getline('.') !~# '\S'
    d _

    " move cursor away from 1st non blank character of next line
    exec "norm! \<c-h>"
  endif

  " add ; and save, prototype is recovered.
  call search('\S', 'cbW')
  norm! a;
  w

  " get func head
  call search(')', 'cbW')
  norm! %

  let func_body = getreg(reg)
  call cdef#def( line('.'), line('.'), reg, 1, 1 )
  call setreg( reg, printf("%s%s\n", getreg(reg), func_body), 'V' )
  return 1
endfunction

function cdef#is_head_file() abort
  return index(s:head_exts, expand('%:e') ) >= 0
endfunction

function cdef#is_source_file() abort
  return index(s:src_exts, expand('%:e') ) >= 0
endfunction

function cdef#get_switch_dirs() abort

  " don't use %:p:h, it's possbile that your current dir contains src, it should
  " not count.
  let dir_path = expand('%:h')

  "take care of file path like include/subdir/file.h
  let l = matchlist(dir_path, '\v(.*)(<include>|<src>)(.*)')
  if l == []
    let alt_dir = dir_path
  elseif l[2] ==# 'include'
    let alt_dir = l[1] . 'src' . l[3]
  elseif l[2] ==# 'src'
    let alt_dir = l[1] . 'include' . l[3]
  endif

  " add current dir, in case .h and .cpp resides in the same src or include
  return [alt_dir, dir_path]
endfunction

function cdef#get_switch_file() abort
  let alt_dirs = cdef#get_switch_dirs()
  let alt_exts = cdef#is_head_file() ? s:src_exts : s:head_exts
  let base_name = expand('%:t:r')

  for alt_dir in alt_dirs
    for ext in alt_exts
      let alt_file = printf('%s/%s', alt_dir, base_name)
      if ext !=# '' | let alt_file .= '.' . ext | endif
      if filereadable(alt_file)
        " /src/file is a valid name in windows, it cause lot of trouble, better
        " use absolute path
        return fnamemodify(alt_file, ':p')
      endif
    endfor
  endfor

  return ''
endfunction

function cdef#switch_file(...) abort
  let keepjumps = get(a:000, 0, 0)
  let cmd_pre = keepjumps ? 'keepjumps ' : ''
  let alt_file = cdef#get_switch_file()

  if alt_file !=# ''
    if bufexists(alt_file)
      let bnr = bufnr(alt_file) | exec cmd_pre . 'buffer ' .  bnr | return 1
    elseif filereadable(alt_file)
      silent! exec cmd_pre . 'edit ' . alt_file | return 1
    endif
  endif

  if get(a:000, 1, 1)
    call s:notify("alternate file doesn't exist or can't be read")
  endif
endfunction

" start_line, end_line, [register [, strip_namespace [, head_only]]]
" create definition at register:
"    whole namespace if current tag is namespace
"    whole class if current tag is namespace
"    single function if current tag is a prototype
"
" if start_line == end_line, define tag scope prototypes, otherwise defines
" prototypes between start_line and end_line
function cdef#def(lnum0, lnum1, ...) abort
  let register = get(a:000, 0, '"')
  let strip_namespace = get(a:000, 1, 1)
  let head_only = get(a:000, 2, 0)

  let tags = cdef#get_tags()
  let range = [a:lnum0, a:lnum1]

  if a:lnum0 == a:lnum1
    let tag = cdef#find_tag(tags, a:lnum0)
    if tag == {} | echo 'no valid tag on current line' | return 0 | endif
    if tag.kind =~# '^p'
      let range = [tag.line, tag.line]
    elseif tag.kind =~# '^[nc]'
      let range = [tag.line, tag.end]
    else
      echo 'no prototype, namespace or class on current line' | return 0
    endif
  endif

  call filter(tags,
        \ {i,v -> v.kind =~# '^p' && !cdef#has_property(v, 'delete') &&
        \ v.line >= range[0] && v.line <= range[1] } )

  let def = ''
  for proto in tags
    let def .= join(s:gen_func(proto, strip_namespace, head_only), "\n")
    if !head_only
      let def .= "\n"
    endif
    call s:debug('create def for : ' . proto.name)
  endfor
  call setreg(register, def, 'V')
  return 1
endfunction

function cdef#create_source_file() abort
  if !cdef#is_head_file() || cdef#switch_file(0, 0) | return | endif

  let alt_dir =  cdef#get_switch_dirs()[0]
  let base_name = expand('%:t:r')
  let src_file = printf('%s/%s.%s', alt_dir, base_name, g:cdef_default_source_extension)

  let head_file = expand('%:t')
  let include = printf(alt_dir ==# expand('%:p:h') ?
        \ '#include "%s"' : '#include <%s>', head_file)

  exe 'e' src_file
  call setline(1, include)

  return 1
endfunction

" g:cdef_proj_name + dirname + filename
function cdef#add_head_guard() abort
  let dirname = expand('%:p:h:t')
  if dirname ==# 'include' || dirname ==# 'inc'
    let dirname = expand('%:p:h:h:t')
  endif
  let gatename = printf('%s_%s', dirname, substitute(expand('%:t'), "\\.", '_', 'g'))
  if g:cdef_proj_name !=# ''
    let gatename = g:cdef_proj_name . '_' . gatename
  endif
  let gatename = toupper(gatename)

  if stridx(getline(1), gatename) != -1
    echom 'ignored, head guard already exists'
    return 0
  endif

  call append(0, [ printf('#ifndef %s', gatename), printf('#define %s', gatename) ])
  call append(line('$'), [ printf('#endif // %s', gatename) ])
  return 1
endfunction

function s:gen_get_set_at(opts, lnum) abort
  let str = getline(a:lnum)
  if str =~# '^\s*$'
    return
  endif

  let var_type = trim(matchstr(str, '\v\s*\zs[^=/{(]+\ze<\h\w*>'))
  let var_name = matchstr(str,  '\v<\w+>\ze\s*[;\=,({]')
  let indent = matchstr(str, '\v^\s*')
  let fname = substitute(var_name, '\v^m?_', '', 'g')
  let arg_type = a:opts.const ? 'const '.var_type.'&':var_type

  let style = get(g:, 'cdef_get_set_style', fname =~# '\v^m[A-Z]' ? 'camel' : 'snake' )

  if style ==# 'camel'
    let fname = toupper(fname[0:0]) . fname[1:]
  endif

  if style ==# 'snake'
    let [gfname, sfname, tfname] = ['get_' . fname, 'set_' . fname, 'toggle_' . fname]
  elseif style ==# 'snake_bare'
    let [gfname, sfname, tfname] = [fname, fname, 'toggle_' . fname]
  elseif style ==# 'camel'
    let [gfname, sfname, tfname] = ['get' . fname, 'set' . fname, 'toggle' . fname]
  else
    throw 'unknow style ' . style
  endif

  let res = ''
  if stridx(a:opts.entries, 'g') !=# -1
    let res .= printf("%s%s %s() const { return %s; }\n", indent, arg_type, gfname, var_name)
  endif
  if stridx(a:opts.entries, 's') !=# -1
    let res .= printf("%svoid %s(%s v) { %s = v; }\n", indent, sfname, arg_type, var_name)
  endif
  if stridx(a:opts.entries, 't') != -1
    let res .= printf("%svoid toggle%s() { %s = !%s; }\n", indent, tfname, var_name, var_name)
  endif

  return res
endfunction

" opts.style:
"   0 : generate getA()/setA()/toggleA() for mA, get_a()/set_a()/toggle_a() for m_a
"   1 : generate getA()/setA()/toggleA() for mA, a()/a()/toggle_a() for m_a
function cdef#gen_get_set(opts, line1, line2) abort

  call extend(a:opts, {'const':0, 'register':'"', 'entries':'gs'}, 'keep')
  " q-args will pass empty register
  if a:opts.register ==# '' | let a:opts.register = '"' | endif

  let res = ''
  for line in range(a:line1, a:line2)
    if getline(line) =~# '^\s*$'
      continue
    endif

    if res !=# ''
      let res .= "\n"
    endif
    let res .= s:gen_get_set_at(a:opts, line)
  endfor
  exec 'let @'.a:opts.register.' = res'

endfunction

function s:get_c(lnum, cnum) abort
  return matchstr(getline(a:lnum), '\%' . a:cnum . 'c.')
endfunction

function s:get_cc() abort
  return s:get_c(line('.'), col('.'))
endfunction

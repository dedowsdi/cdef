if exists("g:loaded_cdef_plugin")
  finish
endif
let g:loaded_cdef_plugin = 1

" TODO check if ctags installed

nnoremap <silent> <Plug>CdefDefineTag :call cdef#defineTag()<CR>
nnoremap <silent> <Plug>CdefDefineRange :<C-U>call cdef#defineRange(line("'<"),line("'<"))<CR>
nnoremap <silent> <Plug>CdefDefineFile :call cdef#defineFile()<CR>
nnoremap <silent> <Plug>CdefSwitchBetProtoAndFunc :call cdef#switchBetProtoAndFunc()<CR>
nnoremap <silent> <Plug>CdefSwitchFile :call cdef#switchFile()<CR>
nnoremap <silent> <Plug>CdefUpdatePrototype :call cdef#UpdatePrototype()<CR>
nnoremap <silent> <Plug>CdefRename :call cdef#rename()<CR>

command! -nargs=* -complete=file_in_path Ccpp :call cdef#copyPrototype(<f-args>)

command! -nargs=0 Crmf :call cdef#mvFunc()
command! -nargs=0 Crrmf :call cdef#rmFunc()
command! -nargs=0 Cnh :call cdef#addHeadGate()

command! -nargs=? Cngs :call mycpp#genGetSet({"register":<q-args>, "entries":"gs"})
command! -nargs=? Cngst :call mycpp#genGetSet({"register":<q-args>, "entries":"gst"})
command! -nargs=? Cncgs :call mycpp#genGetSet({"const":1, "register":<q-args>, "entries":"gs"})
command! -nargs=? Cncgst :call mycpp#genGetSet({"const":1, "register":<q-args>, "entries":"gst"})

if exists("g:loaded_cdef_plugin")
  finish
endif
let g:loaded_cdef_plugin = 1

if !executable('ctags')
  echohl WarningMsg | echom 'CDEF : missing ctags' | echohl None
endif

command! -nargs=* -range CdefDef       : call cdef#def(<line1>, <line2>, <f-args>)
command! -nargs=0 CdefSwitch           : call cdef#switch_proto_func()
command! -nargs=0 CdefSwitchNext       : call cdef#select_next_candidate()
command! -nargs=0 CdefSwitchFile       : call cdef#switch_file()
command! -nargs=0 CdefAddHeadGuard     : call cdef#add_head_guard()
command! -nargs=0 CdefCreateSourceFile : call cdef#create_source_file()
command! -nargs=? -range CdefGetSet           : call cdef#gen_get_set({"register" : <q-args>, "entries" : "gs"}, <line1>, <line2>)
command! -nargs=? -range CdefGetSetTog        : call cdef#gen_get_set({"register" : <q-args>, "entries" : "gst"}, <line1>, <line2>)
command! -nargs=? -range CdefConstGetSet      : call cdef#gen_get_set({"const"    : 1, "register"       : <q-args>, "entries" : "gs"}, <line1>, <line2>)
command! -nargs=? -range CdefConstGetSetTog   : call cdef#gen_get_set({"const"    : 1, "register"       : <q-args>, "entries" : "gst"}, <line1>, <line2>)

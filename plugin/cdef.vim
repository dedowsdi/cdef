if exists("g:loaded_cdef_plugin")
  finish
endif
let g:loaded_cdef_plugin = 1

if !executable('ctags')
  echohl WarningMsg | echom 'CDEF : missing ctags' | echohl None
  finish
endif

com -bar -nargs=* -range CdefDef call cdef#def(<line1>, <line2>, <f-args>)
com -bar -nargs=* -range CdefDefAndSwitch if cdef#def(<line1>, <line2>, <f-args>) | call cdef#goto_new_func_slot() | endif
com -bar -nargs=? -range CdefFuncToProto call cdef#func_to_proto(<f-args>)
com -bar -nargs=? -range CdefFuncToProtoAndSwitch if cdef#func_to_proto(<f-args>) | call cdef#goto_new_func_slot() | endif
com -bar CdefGotoNewFuncSlot call cdef#goto_new_func_slot()
com -bar CdefGotoPrevProto call cdef#goto_prev_tag('p')
com -bar CdefGotoTagEnd call cdef#goto_tag_end()
com -bar CdefSwitch call cdef#switch_proto_func()
com -bar CdefSwitchNext call cdef#select_next_candidate()
com -bar CdefSwitchFile call cdef#switch_file()
com -bar CdefAddHeadGuard call cdef#add_head_guard()
com -bar CdefCreateSourceFile call cdef#create_source_file()
com -bar -nargs=? -range CdefGetSet call cdef#gen_get_set({"register" : <q-args>, "entries" : "gs"}, <line1>, <line2>)
com -bar -nargs=? -range CdefGetSetTog call cdef#gen_get_set({"register" : <q-args>, "entries" : "gst"}, <line1>, <line2>)
com -bar -nargs=? -range CdefConstGetSet call cdef#gen_get_set({"const" : 1, "register" : <q-args>, "entries" : "gs"}, <line1>, <line2>)
com -bar -nargs=? -range CdefConstGetSetTog call cdef#gen_get_set({"const" : 1, "register" : <q-args>, "entries" : "gst"}, <line1>, <line2>)

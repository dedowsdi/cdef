#cdef

##Synopsis

Based on [universal-ctags](https://github.com/universal-ctags/ctags).
Define function in proper position in head or source file.
Switch between head and source file.
Switch between prototype and function.

##Screen Shots

##Install

Use [vim-plug](https://github.com/junegunn/vim-plug) or whatever you like.

Put this in your .vimrc

nmap <leader>dd <Plug>CdefDefineTag
vmap <leader>dd <Plug>CdefDefineRange
nmap <leader>df <Plug>CdefDefineFile

" TARS stub for $VIMRUNTIME/defaults.vim (CU design decision 7).
" vim sources this file when no user vimrc exists. The guest has no vim runtime,
" and without this file vim shows "E1187: Failed to source defaults.vim" and
" waits for ENTER on every start. The real file (5,412 bytes) turns on syntax,
" filetype plugins and the mouse, which need the runtime this guest does not have.
" Keep this file free of commands.

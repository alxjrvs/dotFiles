set nocompatible
filetype off

runtime macros/matchit.vim
    filetype indent plugin on
set is
set encoding=utf-8
set rtp+=~/.vim/bundle/Vundle.vim

let mapleader = ","

" Brief help
" " :PluginList       - lists configured plugins
" " :PluginInstall    - installs plugins; append `!` to update or just
" :PluginUpdate
" " :PluginSearch foo - searches for foo; append `!` to refresh local cache
" " :PluginClean      - confirms removal of unused plugins; append `!` to
"
call vundle#begin()

Plugin 'VundleVim/Vundle.vim'

Plugin 'junegunn/fzf'
Plugin 'junegunn/fzf.vim'
 nnoremap <C-p> :FZF<CR>

Plugin 'tpope/vim-surround'
Plugin 'tpope/vim-repeat'
Plugin 'tpope/vim-fugitive'

Plugin 'altercation/vim-colors-solarized'

Plugin 'airblade/vim-gitgutter'
Plugin 'airblade/vim-rooter'

Plugin 'neoclide/coc.nvim', {'branch': 'release'}
  let g:coc_global_extensions = [
        \ 'coc-tsserver',
        \ 'coc-rls',
        \ 'coc-prettier',
        \ 'coc-eslint',
        \ ]
  let g:coc_user_config = {
        \ "coc.preferences.formatOnSaveFiletypes": [
          \ "css",
          \ "markdown",
          \ "javascript",
          \ "javascriptreact",
          \ "typescript",
          \ "typescriptreact",
        \ ],
        \ "diagnostic.messageTarget": "echo",
        \ }
  " Symbol renaming.
  nmap <leader>rn <Plug>(coc-rename)
  " Formatting selected code.
  xmap <leader>f  <Plug>(coc-format-selected)
  nmap <leader>f  <Plug>(coc-format-selected)

Plugin 'leafgarland/typescript-vim'
Plugin 'peitalin/vim-jsx-typescript'
  autocmd BufNewFile,BufRead *.tsx,*.jsx set filetype=typescript.tsx
  autocmd CursorHold * silent call CocActionAsync('highlight')

Plugin 'ervandew/supertab'

Plugin 'luochen1990/rainbow'
  let g:rainbow_active = 1

Plugin 'Yggdroot/indentLine'
  let g:indentLine_char = '.'

Plugin 'mhinz/vim-startify'
  let g:startify_custom_header = [
      \'-------------------------------╔═╗┌─┐┬ ┬┬─┐┌┬┐┬ ┬  ╦ ╦┌─┐┬─┐┬  ┌┬┐┌─┐',
      \'===============================╠╣ │ ││ │├┬┘ │ ├─┤  ║║║│ │├┬┘│   ││ ┌┘',
      \'And the son asked, what is the ╚  └─┘└─┘┴└─ ┴ ┴ ┴  ╚╩╝└─┘┴└─┴─┘─┴┘ o ',
      \'And the Father said:',
      \'The First World is the Old World, the world of my parents, from which they fled.',
      \'The Second World is the New World, which they sought, which they found, where I came to be.',
      \'The Third World is Our World as it is now, in the making, the future being born.',
      \'And the Fourth World, my child, that is My World. The world I see when I close my eyes...',
      \'     ...and try to',
      \'╔═╗╔═╗╔═╗╔═╗╔═╗╔═╗',
      \'║╣ ╚═╗║  ╠═╣╠═╝║╣ ',
      \'╚═╝╚═╝╚═╝╩ ╩╩  ╚═╝o',
      \ ]
  let g:startify_files_number = 5
  let g:startify_lists = [
    \ { 'type': 'dir',  'header': ['   Files'] },
    \]

Plugin 'Xuyuanp/nerdtree-git-plugin'

Plugin 'hail2u/vim-css3-syntax'

Plugin 'ap/vim-css-color'

Plugin 'alvan/vim-closetag'

Plugin 'scrooloose/nerdtree'
  map <C-t><C-t> :NERDTreeToggle<CR>
  let NERDTreeIgnore = [ '\.swp', '*\.swp', 'node_modules/' ]
  let NERDTreeShowHidden=1
  let NERDTreeQuitOnOpen=1
  let NERDTreeMinimalUI = 1
  let NERDTreeDirArrows = 1
  let NERDTreeAutoDeleteBuffer = 1

Plugin 'christoomey/vim-tmux-navigator'

Plugin 'zhaocai/GoldenView.Vim'
  let g:goldenview__enable_default_mapping = 0

Plugin 'benmills/vimux'
  map <Leader>Lp :VimuxPromptCommand<CR>
  nmap <F8> :TagbarToggle<CR>
  map <Leader>vp :VimuxPromptCommand<CR>
  map <Leader>vl :VimuxRunLastCommand<CR>
  map <Leader>vz :VimuxZoomRunner<CR>

Plugin 'majutsushi/tagbar'

Plugin 'vim-airline/vim-airline'
Plugin 'vim-airline/vim-airline-themes'
Plugin 'edkolev/tmuxline.vim'
  set t_Co=256
  if !exists('g:airline_symbols')
     let g:airline_symbols = {}
   endif
   let g:airline_powerline_fonts = 1
   let g:airline#extensions#tabline#enabled = 1
   let g:airline#extensions#tabline#left_sep = ' '
   let g:airline#extensions#tabline#left_alt_sep = '|'

let g:airline_theme='solarized'
let g:airline_solarized_bg='dark'

Plugin 'mileszs/ack.vim'

call vundle#end()            " required
filetype plugin indent on    " required

syntax enable
colorscheme solarized
set background=dark


set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
autocmd FileType typescript setlocal completeopt+=menu,preview

nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>
set splitbelow
set splitright

" tabs to 2 spaces
set smartindent
set tabstop=2
set shiftwidth=2
set expandtab
set ruler
set hidden
:set guioptions-=m " remove menu bar
:set guioptions-=T " remove toolbar
:set guioptions-=r " remove right-hand scroll bar
:set guioptions-=L " remove left-hand scroll bar
":set lines=999 columns=999
set shortmess+=A " disable swap file warning

" hybrid line numbers
set number relativenumber
augroup numbertoggle
  autocmd!
  autocmd BufEnter,FocusGained,InsertLeave * set relativenumber
  autocmd BufLeave,FocusLost,InsertEnter * set norelativenumber
augroup END


set splitbelow
set nowrap

" always show gutter
set signcolumn=yes

" allow backspace immediately after insert
set bs=2

" useful aliases
cnoreabbrev W w
cnoreabbrev Q q

" save undo in a file
set undofile
set undodir=~/.vim/undo
set undolevels=1000
set undoreload=10000

"Undo
set undodir=~/.vim/undodir
set undofile " Maintain undo history between sessions

set shortmess+=c

"Do not become addicted to water
noremap <Up> <Nop>
noremap <Down> <Nop>
noremap <Left> <Nop>
noremap <Right> <Nop>

" tmux will only forward escape sequences to the terminal if surrounded by a
" DCS sequence
" "
" http://sourceforge.net/mailarchive/forum.php?thread_name=AANLkTinkbdoZ8eNR1X2UobLTeww1jFrvfJxTMfKSq-L%2B%40mail.gmail.com&forum_name=tmux-users
if exists('$TMUX')
  let &t_SI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=1\x7\<Esc>\\"
  let &t_EI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=0\x7\<Esc>\\"
else
  let &t_SI = "\<Esc>]50;CursorShape=1\x7"
  let &t_EI = "\<Esc>]50;CursorShape=0\x7"
endif

" Folding
augroup XML
    autocmd!
    autocmd FileType xml setlocal foldmethod=indent foldlevelstart=999 foldminlines=0
augroup END

set list
set listchars=tab:»\ ,extends:›,precedes:‹,nbsp:·,trail:·
set colorcolumn=100

noremap <leader>k :call TrimWhiteSpace()<CR>

" Removes trailing spaces
function TrimWhiteSpace()
  %s/\s*$//
  ''
endfunction

map ; :Files<CR>

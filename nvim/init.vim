set nocompatible

runtime macros/matchit.vim
    filetype indent plugin on
set is
set encoding=utf-8
set rtp+=~/.vim/bundle/Vundle.vim

let mapleader = ","

" Brief help
" :PluginList       - lists configured plugins
" :PluginInstall    - installs plugins; append `!` to update or just :PluginUpdate
" :PluginSearch foo - searches for foo; append `!` to refresh local cache
" :PluginClean      - confirms removal of unused plugins; append `!` to auto-approve removal
"
" see :h vundle for more details or wiki for FAQ
" Put your non-Plugin stuff after this line"
"
call vundle#begin()

Plugin 'VundleVim/Vundle.vim'

" Colorscheme
Plugin 'altercation/vim-colors-solarized'

Plugin 'herringtondarkholme/yats.vim'
Plugin 'leafgarland/typescript-vim'
Plugin 'pangloss/vim-javascript'
Plugin 'MaxMEllon/vim-jsx-pretty'
Plugin 'peitalin/vim-jsx-typescript'
" Force buffer to rescan typescript files for better highlighting
autocmd BufEnter *.{js,jsx,ts,tsx} :syntax sync fromstart
autocmd BufLeave *.{js,jsx,ts,tsx} :syntax sync clear

Plugin 'junegunn/fzf'
Plugin 'tpope/vim-surround'
Plugin 'tpope/vim-repeat'
Plugin 'tpope/vim-fugitive'
Plugin 'townk/vim-autoclose'
Plugin 'airblade/vim-rooter'
Plugin 'preservim/nerdcommenter'
Plugin 'tpope/vim-commentary'

Plugin 'airblade/vim-gitgutter'
  let g:gitgutter_sign_added = '✚'
  let g:gitgutter_sign_modified = '✹'
  let g:gitgutter_sign_removed = '-'
  let g:gitgutter_sign_removed_first_line = '-'
  let g:gitgutter_sign_modified_removed = '-'

Plugin 'neoclide/coc.nvim', {'branch': 'release'}
  let g:coc_global_extensions = [
  \ 'coc-tsserver',
\ ]

  if isdirectory('./node_modules') && isdirectory('./node_modules/prettier')
    let g:coc_global_extensions += ['coc-prettier']
  endif

  if isdirectory('./node_modules') && isdirectory('./node_modules/eslint')
    let g:coc_global_extensions += ['coc-eslint']
  endif

  " Symbol renaming.
  nmap <leader>rn <Plug>(coc-rename)
  " Formatting selected code.
  xmap <leader>f  <Plug>(coc-format-selected)
  nmap <leader>f  <Plug>(coc-format-selected)

  " Trigger Codeactions
  nmap <leader>do <Plug>(coc-codeaction)
  nmap <leader>qf  <Plug>(coc-fix-current)

  " Use `[g` and `]g` to navigate diagnostics
  nmap <silent> [g <Plug>(coc-diagnostic-prev)
  nmap <silent> ]g <Plug>(coc-diagnostic-next)

  " GoTo code navigation.
  nmap <silent> gd <Plug>(coc-definition)
  nmap <silent> gy <Plug>(coc-type-definition)
  nmap <silent> gi <Plug>(coc-implementation)
  nmap <silent> gr <Plug>(coc-references)

  " show list of diagnosstics
  nnoremap <silent> <space>d :<C-u>CocList diagnostics<cr>

  " show list of symbols
  nnoremap <silent> <space>s :<C-u>CocList -I symbols<cr>

Plugin 'luochen1990/rainbow'
  let g:rainbow_active = 1

Plugin 'reedes/vim-pencil' 
  augroup pencil
    autocmd!
    autocmd FileType markdown,mkd call pencil#init()
    autocmd FileType text         call pencil#init()
  augroup END

Plugin 'Yggdroot/indentLine'
  let g:indentLine_char = '.'

Plugin 'mhinz/vim-startify'
  let g:startify_custom_header = [
      \'                      And the son asked, what is the ╔═╗┌─┐┬ ┬┬─┐┌┬┐┬ ┬  ╦ ╦┌─┐┬─┐┬  ┌┬┐┌─┐',
      \'=====================================================╠╣ │ ││ │├┬┘ │ ├─┤  ║║║│ │├┬┘│   ││ ┌┘',
      \'---------------------------------------------------- ╚  └─┘└─┘┴└─ ┴ ┴ ┴  ╚╩╝└─┘┴└─┴─┘─┴┘ o ',
      \'                            And the Father said:',
      \'    The First World is the Old World, the world of my parents, from which they fled.',
      \'The Second World is the New World, which they sought, which they found, where I came to be.',
      \    'The Third World is Our World as it is now, in the making, the future being born.',
      \' And the Fourth World, my child, that is My World. The world I see when I close my eyes...',
      \'                               ...and try to',
      \'------------------------------╔═╗╔═╗╔═╗╔═╗╔═╗╔═╗-------------------------------------------',
      \'==============================║╣ ╚═╗║  ╠═╣╠═╝║╣ ===========================================',
      \'------------------------------╚═╝╚═╝╚═╝╩ ╩╩  ╚═╝o------------------------------------------',
      \ ]
  let g:startify_files_number = 5
  let g:startify_left_padding = 4
  let g:startify_lists = [
    \ { 'type': 'dir',  'header': ['   Files'] },
    \]


Plugin 'hail2u/vim-css3-syntax'

Plugin 'ap/vim-css-color'

Plugin 'alvan/vim-closetag'

Plugin 'scrooloose/nerdtree'
  map <C-t><C-t> :NERDTreeToggle<CR>
  map <C-t>f :NERDTreeFind<CR>
  let NERDTreeIgnore = [ '\.swp', '*\.swp', '$node_modules' ]
  let NERDTreeShowHidden=1
  let NERDTreeQuitOnOpen=1
  let NERDTreeMinimalUI = 1
  let NERDTreeDirArrows = 1
  let NERDTreeAutoDeleteBuffer = 1
  let g:NERDTreeGitStatusIndicatorMapCustom = {
    \ "Modified"  : "✹",
    \ "Staged"    : "✚",
    \ "Untracked" : "✭",
    \ "Renamed"   : "➜",
    \ "Unmerged"  : "═",
    \ "Deleted"   : "",
    \ "Dirty"     : "✗",
    \ "Clean"     : "✔︎",
    \ 'Ignored'   : '☒',
    \ "Unknown"   : "?"
    \ }
  autocmd VimEnter *
  \   if !argc()
  \ |   Startify
  \ |   wincmd w
  \ | endif
  autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif

Plugin 'Xuyuanp/nerdtree-git-plugin'
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
set statusline+=%*

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

"Search
let $FZF_DEFAULT_COMMAND = 'rg --files --hidden'
nnoremap <c-p> :FZF<cr>

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

set cmdheight=2
"set updatetime=300

autocmd QuickFixCmdPost [^l]* nested cwindow
autocmd QuickFixCmdPost    l* nested lwindow

set list
set listchars=tab:»\ ,extends:›,precedes:‹,nbsp:·,trail:·
set colorcolumn=100

noremap <leader>k :call TrimWhiteSpace()<CR>

" Removes trailing spaces
function TrimWhiteSpace()
  %s/\s*$//
  ''
endfunction


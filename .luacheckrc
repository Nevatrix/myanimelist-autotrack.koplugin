std = "luajit"
max_line_length = false
-- "_" is gettext in koreader, and also my throwaway variable
ignore = { "211/_", "212", "213" }
globals = { "G_reader_settings" }
exclude_files = { ".luarocks", "lua_modules" }

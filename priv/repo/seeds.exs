# Loads the FICTITIOUS demo corpus through the real pipeline (mix run priv/repo/seeds.exs).
# No real person, ID number or ruling appears in these files.
Lexec.Demo.seed()
|> Enum.sort()
|> Enum.each(fn {file, outcome} -> IO.puts("#{file}: #{outcome}") end)

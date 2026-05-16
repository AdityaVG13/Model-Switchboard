# Model Switchboard — terminal demo
# Renders to Resources/Brand/terminal-demo.gif
# Run from repo root: vhs Scripts/vhs/terminal-demo.tape

Output Resources/Brand/terminal-demo.gif

Set Shell "zsh"
Set Theme "Aardvark Blue"
Set FontSize 16
Set FontFamily "JetBrainsMono Nerd Font"
Set Width 1100
Set Height 780
Set Padding 28
Set TypingSpeed 35ms
Set PlaybackSpeed 1.0

Hide
Type "export PATH=\"$PWD/Scripts:$PATH\""
Enter
Type "alias msb=model-switchboardctl"
Enter
Type "alias inv=\"$PWD/Scripts/vhs/inventory.sh\""
Enter
Type "clear"
Enter
Show

Sleep 600ms

Type "# Model Switchboard -- flip local LLM runtimes from one menubar"
Enter
Sleep 900ms

Type "msb summary"
Enter
Sleep 1500ms

Type "inv"
Enter
Sleep 2800ms

Type "msb profiles-dir"
Enter
Sleep 1500ms

Type "# one click in the menubar starts the picked runtime, stops the rest"
Enter
Sleep 2500ms

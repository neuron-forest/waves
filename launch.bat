@echo off
setlocal
set "ENGINE=%GODOT_EXE%"
if defined ENGINE goto launch
for %%G in (godot.exe godot4.exe godot_console.exe godot4_console.exe) do (
  for /f "delims=" %%P in ('where %%G 2^>nul') do if not defined ENGINE set "ENGINE=%%P"
)
if not defined ENGINE (
  echo Godot 4.7.2 with Forward+ and Vulkan is required.
  echo Set GODOT_EXE to the full executable path, or add Godot to PATH.
  exit /b 1
)
:launch
"%ENGINE%" --path "%~dp0." --rendering-method forward_plus --rendering-driver vulkan
exit /b %errorlevel%

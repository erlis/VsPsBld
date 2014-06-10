@pushd %~dp0
powershell.exe "& lib\psake\psake.ps1 build.ps1; exit $LastExitCode"
@popd 


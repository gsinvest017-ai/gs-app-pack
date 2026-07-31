# gs-app-pack: load a project's pack.config.ps1 with a known encoding.
#
# Dot-sourcing it directly is not safe. Windows PowerShell 5.1 reads a script
# without a byte-order mark using the machine's ANSI codepage, so a config that
# names a path in Chinese — `系統檔案\.venv\Scripts\python.exe` — arrives as
# mojibake and every path built from it points nowhere. PowerShell 7 defaults to
# UTF-8 and reads the same file correctly, which is why this surfaces only when
# something invokes `powershell.exe`: an interactive pwsh session works, and the
# automation that follows the documented command does not.
#
# Reading the bytes and decoding them as UTF-8 removes the guess. A BOM, if
# present, is stripped; ASCII-only configs are unaffected either way.
#
# Usage (from a script in this directory):
#     . "$PSScriptRoot\Load-PackConfig.ps1"
#     Import-PackConfig $Config
#
# Invoke-Expression rather than dot-sourcing a temp file: the caller wants the
# variables in *its* scope, and a temp file would reintroduce a path that has to
# survive the same encoding round trip.

function Import-PackConfig {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $bytes = [System.IO.File]::ReadAllBytes($resolved)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB `
            -and $bytes[2] -eq 0xBF) {
        $bytes = $bytes[3..($bytes.Length - 1)]
    }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)

    # Scope 1 is the caller of this function — the build/installer/release
    # script — which is where a dot-sourced config would have landed.
    $sb = [scriptblock]::Create($text)
    . $sb
    foreach ($v in Get-Variable -Scope 0 -ErrorAction SilentlyContinue) {
        if ($v.Name -in @('Path', 'resolved', 'bytes', 'text', 'sb', 'v',
                          'args', 'input', 'PSBoundParameters', 'MyInvocation',
                          'PSCmdlet', 'PSCommandPath', 'PSScriptRoot')) {
            continue
        }
        Set-Variable -Name $v.Name -Value $v.Value -Scope 1 -Force `
                     -ErrorAction SilentlyContinue
    }
}

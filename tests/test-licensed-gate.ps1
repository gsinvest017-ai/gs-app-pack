<#
.SYNOPSIS
    build.ps1 的 $Licensed 宣告式閘門 —— 負面測試。

.DESCRIPTION
    只驗「正常情況印 PASS」是抓不到守門自身的 bug 的。這條線已經踩過兩次：
    第一版守門把 pip 的 stderr warning 當成 error record 直接炸掉（印
    NativeCommandError 而不是真正原因），以及 Write-Error 在
    `powershell -Command` 下讓 $LASTEXITCODE 保持 0，CI 把「拒絕出貨」讀成成功。

    所以這裡每個情境都同時斷言 **退出碼** 與 **訊息內容**，而不是只看有沒有跑完。

    每個情境用一個臨時專案目錄跑真的 build.ps1，閘門在產生 icon 之前，
    所以不會真的去打包任何東西。

.EXAMPLE
    pwsh -NoProfile -File .\tests\test-licensed-gate.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$build = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\build.ps1'
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { throw "找不到 python，無法跑測試" }

$pass = 0
$fail = 0

function Invoke-Case {
    param(
        [string]$Name,
        [string]$ConfigBody,
        [int]$ExpectExit,
        [string[]]$ExpectText
    )
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("gsap-gate-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir | Out-Null
    try {
        $header = @"
`$AppExe   = "gate-test"
`$AppName  = "gate-test"
`$PythonExe = "$($python -replace '\\', '\\')"

"@
        Set-Content -LiteralPath (Join-Path $dir 'pack.config.ps1') `
                    -Value ($header + $ConfigBody) -Encoding UTF8

        Push-Location $dir
        $out = & pwsh -NoProfile -File $build -Config 'pack.config.ps1' 2>&1 | Out-String
        $code = $LASTEXITCODE
        Pop-Location

        $ok = $true
        if ($code -ne $ExpectExit) {
            Write-Host "  FAIL 退出碼：預期 $ExpectExit，實得 $code" -ForegroundColor Red
            $ok = $false
        }
        foreach ($needle in $ExpectText) {
            if ($out -notmatch [regex]::Escape($needle)) {
                Write-Host "  FAIL 訊息缺少：$needle" -ForegroundColor Red
                $ok = $false
            }
        }
        if ($ok) {
            Write-Host "  PASS $Name" -ForegroundColor Green
            $script:pass++
        } else {
            Write-Host "  ---- 實際輸出 ----" -ForegroundColor DarkGray
            Write-Host $out -ForegroundColor DarkGray
            $script:fail++
        }
    } finally {
        Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
    }
}

Write-Host "build.ps1 `$Licensed 閘門測試`n"

# 1. 未宣告 -> 必須失敗，並指出兩種寫法
Invoke-Case -Name '未宣告 $Licensed 直接失敗' -ExpectExit 1 -ConfigBody '' `
    -ExpectText @('does not declare', '$Licensed = $true', '$Licensed = $false')

# 2. 宣告 licensed 但沒有 RequireNonEditable -> 失敗
Invoke-Case -Name '$Licensed=$true 但缺 $RequireNonEditable' -ExpectExit 1 -ConfigBody @'
$Licensed = $true
$PostBuildCheck = "{python} -m keyguard.packagecheck '{dist}'"
'@ -ExpectText @('does not contain', 'keyguard')

# 3. 宣告 licensed、有 RequireNonEditable 但 PostBuildCheck 沒跑 packagecheck -> 失敗
Invoke-Case -Name '$Licensed=$true 但 $PostBuildCheck 沒跑 packagecheck' -ExpectExit 1 -ConfigBody @'
$Licensed = $true
$RequireNonEditable = @("keyguard")
$PostBuildCheck = "echo hello"
'@ -ExpectText @('does not run', 'keyguard.packagecheck')

# 4. 明示不上鎖 -> 通過閘門（之後才因為沒有真的專案而失敗，所以只驗訊息）
Invoke-Case -Name '$Licensed=$false 明示豁免可通過' -ExpectExit 1 -ConfigBody @'
$Licensed = $false
'@ -ExpectText @('ships with no licence gate')

Write-Host ""
Write-Host "通過 $pass / 失敗 $fail" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $(if ($fail) { 1 } else { 0 })

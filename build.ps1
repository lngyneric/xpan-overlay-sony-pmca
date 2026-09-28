# Build the XPanOverlay PMCA app on Windows (native PowerShell, no Git Bash needed).
#
#   output: build\XPanOverlay-<versionName>.apk   (e.g. XPanOverlay-1.2.apk)
#
# JDK, Android SDK, build-tools and platform are auto-detected.
# Override with env vars: JAVA_HOME, ANDROID_HOME (or ANDROID_SDK_ROOT),
#                         BT_VERSION (default 25.0.3), PLATFORM (default android-10)
#
# Usage:
#   .\build.ps1                build
#   .\build.ps1 -Bootstrap     download cmdline-tools + platform + build-tools, then build
#   .\build.ps1 -Clean         remove build\ and debug.keystore
#
# Install the result on the camera with pmca-gui / pmca-console.

param(
    [switch]$Bootstrap,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

function Log  { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function Warn { param($m) Write-Host "warn: $m" -ForegroundColor Yellow }
function Fail { param($m) Write-Host "error: $m" -ForegroundColor Red; exit 1 }

if ($Clean) {
    if (Test-Path build) { Remove-Item -Recurse -Force build }
    if (Test-Path debug.keystore) { Remove-Item -Force debug.keystore }
    Log "cleaned build\ and debug.keystore"
    exit 0
}

# ---------------------------------------------------------------- version ----
$manifest = Get-Content AndroidManifest.xml -Raw
$m = [regex]::Match($manifest, 'android:versionName="([^"]+)"')
if ($m.Success) { $version = $m.Groups[1].Value } else { $version = '1.2' }
$outApk = "XPanOverlay-$version.apk"

# -------------------------------------------------------------------- JDK ----
function Find-Jdk {
    $cands = New-Object System.Collections.Generic.List[string]
    if ($env:JAVA_HOME) { [void]$cands.Add($env:JAVA_HOME) }
    [void]$cands.Add((Join-Path ${env:ProgramFiles} 'Android\Android Studio\jbr'))
    $roots = @(
        (Join-Path ${env:ProgramFiles} 'Java'),
        (Join-Path ${env:ProgramFiles} 'Eclipse Adoptium'),
        (Join-Path ${env:ProgramFiles} 'Microsoft'),
        (Join-Path ${env:ProgramFiles} 'Zulu'),
        (Join-Path ${env:ProgramFiles} 'BellSoft'),
        (Join-Path ${env:ProgramFiles} 'JetBrains')
    )
    foreach ($r in $roots) {
        if ($r -and (Test-Path $r)) {
            Get-ChildItem -Path $r -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object { [void]$cands.Add($_.FullName) }
        }
    }
    foreach ($c in $cands) {
        if ($c -and (Test-Path (Join-Path $c 'bin\javac.exe'))) { return $c }
    }
    return $null
}

$jdk = Find-Jdk
if (-not $jdk) {
    Fail "no JDK found. Install one and/or set JAVA_HOME (needs javac.exe + keytool.exe).`n  https://adoptium.net  |  Android Studio ships one at `"${env:ProgramFiles}\Android\Android Studio\jbr`""
}
$javac     = Join-Path $jdk 'bin\javac.exe'
$java      = Join-Path $jdk 'bin\java.exe'
$keytool   = Join-Path $jdk 'bin\keytool.exe'
$jarsigner = Join-Path $jdk 'bin\jarsigner.exe'
$jar       = Join-Path $jdk 'bin\jar.exe'

$javacVer = (& $javac -version 2>&1) | Out-String
if ($javacVer -match 'javac (\d+)') { $javacMajor = [int]$Matches[1] } else { $javacMajor = 1 }
Log "JDK         : $jdk (javac $javacMajor)"

# -------------------------------------------------------------------- SDK ----
function Find-Sdk {
    $cands = @(
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
        (Join-Path $env:USERPROFILE 'AppData\Local\Android\Sdk'),
        (Join-Path $env:USERPROFILE 'Android\Sdk'),
        'C:\Android\Sdk'
    )
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

$sdk = Find-Sdk
if (-not $sdk -and $Bootstrap) {
    $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    Log "no SDK found, bootstrapping into $sdk"
    New-Item -ItemType Directory -Force -Path $sdk | Out-Null
}
if (-not $sdk) { Fail "no Android SDK found. Set ANDROID_HOME, or run: .\build.ps1 -Bootstrap" }
Log "SDK         : $sdk"

# --------------------------------------------------------------- bootstrap ----
if ($Bootstrap) {
    $cmdline = Join-Path $sdk 'cmdline-tools\latest'
    $sdkmgr  = Join-Path $cmdline 'bin\sdkmanager.bat'
    if (-not (Test-Path $sdkmgr)) {
        if ($javacMajor -lt 17) { Fail "-Bootstrap needs JDK 17+ (current: $javacMajor). Point JAVA_HOME at a 17+ JDK." }
        $zip = Join-Path $sdk 'cmdline-tools.zip'
        New-Item -ItemType Directory -Force -Path (Join-Path $sdk 'cmdline-tools') | Out-Null
        $url = 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip'
        Log "downloading Android cmdline-tools"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $zip
        Log "extracting to $cmdline"
        if (Test-Path $cmdline) { Remove-Item -Recurse -Force $cmdline }
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $sdk 'cmdline-tools') -Force
        $inner = Join-Path $sdk 'cmdline-tools\cmdline-tools'
        if (Test-Path $inner) { Move-Item -LiteralPath $inner -Destination $cmdline -Force }
        Remove-Item -Force $zip
    }
    Log "installing platform + build-tools (accepting licenses)"
    $btVer    = if ($env:BT_VERSION) { $env:BT_VERSION } else { '25.0.3' }
    $platName = if ($env:PLATFORM)   { $env:PLATFORM }   else { 'android-10' }
    $env:JAVA_HOME = $jdk
    cmd /c "`"echo`" y | `"$sdkmgr`" --sdk_root=`"$sdk`" --licenses" | Out-Null
    & $sdkmgr --sdk_root="$sdk" "platforms;$platName" "build-tools;$btVer" "platform-tools"
    if ($LASTEXITCODE -ne 0) { Warn "sdkmanager refused $platName / $btVer; continuing with whatever it installed" }
}

# ------------------------------------------------------------- build-tools ----
$btDir = $null
if ($env:BT_VERSION) {
    $c = Join-Path $sdk "build-tools\$env:BT_VERSION"
    if (Test-Path $c) { $btDir = $c }
}
if (-not $btDir) {
    foreach ($v in @('25.0.3', '27.0.3', '28.0.3', '29.0.3', '30.0.3')) {
        $c = Join-Path $sdk "build-tools\$v"
        if ((Test-Path $c) -and (Test-Path (Join-Path $c 'aapt.exe'))) { $btDir = $c; break }
    }
}
if (-not $btDir) {
    $found = Get-ChildItem -Path (Join-Path $sdk 'build-tools') -Directory -ErrorAction SilentlyContinue |
             Where-Object { Test-Path (Join-Path $_.FullName 'aapt.exe') } |
             Select-Object -First 1
    if ($found) { $btDir = $found.FullName }
}
if (-not $btDir) { Fail "no usable build-tools in $sdk\build-tools (need one containing aapt.exe).`n  Try: sdkmanager `"build-tools;25.0.3`"   or   .\build.ps1 -Bootstrap" }
Log "build-tools : $(Split-Path $btDir -Leaf)"

# ---------------------------------------------------------------- platform ----
$plat = $null
if ($env:PLATFORM) {
    $c = Join-Path $sdk "platforms\$env:PLATFORM"
    if (Test-Path (Join-Path $c 'android.jar')) { $plat = $c }
}
if (-not $plat) {
    foreach ($v in @('android-10', 'android-14', 'android-16', 'android-19')) {
        $c = Join-Path $sdk "platforms\$v"
        if (Test-Path (Join-Path $c 'android.jar')) { $plat = $c; break }
    }
}
if (-not $plat) {
    $found = Get-ChildItem -Path (Join-Path $sdk 'platforms') -Directory -ErrorAction SilentlyContinue |
             Where-Object { Test-Path (Join-Path $_.FullName 'android.jar') } |
             Select-Object -First 1
    if ($found) { $plat = $found.FullName }
}
if (-not $plat) { Fail "no Android platform with android.jar in $sdk\platforms" }
$androidJar = Join-Path $plat 'android.jar'
Log "platform    : $(Split-Path $plat -Leaf)"

$aapt     = Join-Path $btDir 'aapt.exe'
$zipalign = Join-Path $btDir 'zipalign.exe'
if (-not (Test-Path $aapt))     { Fail "aapt.exe not found in $btDir" }
if (-not (Test-Path $zipalign)) { Fail "zipalign.exe not found in $btDir" }
$dxJar        = Join-Path $btDir 'lib\dx.jar'
$apksignerJar = Join-Path $btDir 'lib\apksigner.jar'

# d8 only ships in build-tools 26+; borrow it from any installed version.
# dx (build-tools <= 30) cannot read anything newer than Java 7 bytecode (v51).
$d8Jar = $null
$btAll = Get-ChildItem -Path (Join-Path $sdk 'build-tools') -Directory -ErrorAction SilentlyContinue |
         Sort-Object -Property @{Expression = { try { [version]$_.Name } catch { [version]'0.0' } } } -Descending
foreach ($d in $btAll) {
    $c = Join-Path $d.FullName 'lib\d8.jar'
    if (Test-Path $c) { $d8Jar = $c; break }
}
if (-not ((Test-Path $dxJar) -or ($d8Jar -and (Test-Path $d8Jar)))) {
    Fail "neither dx.jar nor d8.jar found under $sdk\build-tools\*\lib"
}
if ($d8Jar) { $dexTool = 'd8'; $dexLevel = 8 } else { $dexTool = 'dx'; $dexLevel = 7 }

# ------------------------------------------------------------------- build ----
$build = 'build'
if (Test-Path $build) { Remove-Item -Recurse -Force $build }
New-Item -ItemType Directory -Force -Path "$build\classes" | Out-Null

Log "[1/6] aapt: package manifest -> base.apk"
& $aapt package -f -M AndroidManifest.xml -I $androidJar -F "$build\base.apk"
if ($LASTEXITCODE -ne 0) { Fail "aapt failed" }

Log "[2/6] javac: compile sources (dexer: $dexTool, bytecode: Java $dexLevel)"
# Windows javac defaults to the GBK codepage; the sources are UTF-8
if ($dexLevel -eq 7 -and $javacMajor -ge 20) {
    Fail "dx cannot read Java 8+ bytecode and JDK $javacMajor cannot emit Java 7 bytecode.`n  Install build-tools 26+ (for d8): sdkmanager `"build-tools;30.0.3`", or use JDK 8-19."
}
if ($javacMajor -ge 9) {
    $javacOpts = @('--release', "$dexLevel", '-encoding', 'UTF-8')
} else {
    $javacOpts = @('-source', '1.7', '-target', '1.7', '-encoding', 'UTF-8')
}
& $javac $javacOpts -nowarn -classpath $androidJar -sourcepath src -d "$build\classes" `
    'src\com\example\xpanoverlay\MainActivity.java' 'src\com\example\xpanoverlay\OverlayView.java'
if ($LASTEXITCODE -ne 0) { Fail "javac failed" }

Log "[3/6] dex (min-sdk 10 -> dex 035)"
if ($dexTool -eq 'd8') {
    & $java -jar $d8Jar --min-api 10 --lib $androidJar --output $build "$build\classes"
    if ($LASTEXITCODE -ne 0) { Fail "d8 failed" }
} else {
    & $java -jar $dxJar --dex --output="$build\classes.dex" "$build\classes"
    if ($LASTEXITCODE -ne 0) { Fail "dx failed" }
}
if (-not (Test-Path "$build\classes.dex")) { Fail "classes.dex was not produced" }

Log "[4/6] zip: add classes.dex to base.apk"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = Join-Path (Get-Location) "$build\base.apk"
$za = [System.IO.Compression.ZipFile]::Open($zipPath, 'Update')
try {
    $existing = $za.Entries | Where-Object { $_.FullName -eq 'classes.dex' }
    if ($existing) { $existing.Delete() }
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, (Join-Path (Get-Location) "$build\classes.dex"), 'classes.dex', 'Optimal') | Out-Null
} finally { $za.Dispose() }

Log "[5/6] zipalign"
& $zipalign -f 4 "$build\base.apk" "$build\aligned.apk"
if ($LASTEXITCODE -ne 0) { Fail "zipalign failed" }

Log "[6/6] sign (v1 + v2)"
if (-not (Test-Path debug.keystore)) {
    Log "       generating debug.keystore (gitignored, password xpan1234)"
    & $keytool -genkeypair -keystore debug.keystore -storetype JKS -alias xpan `
        -storepass xpan1234 -keypass xpan1234 -dname "CN=XPanOverlay" `
        -keyalg RSA -keysize 2048 -validity 10000 2>&1 | Out-Null
    if (-not (Test-Path debug.keystore)) { Fail "keytool failed to create debug.keystore" }
}

if (Test-Path $apksignerJar) {
    # apksigner 25.x reaches into java.io.Console and sun.security.*, which
    # JDK 9+ hides behind the module system
    $signArgs = @()
    if ($javacMajor -ge 9) {
        $signArgs += @(
            '--add-opens', 'java.base/java.io=ALL-UNNAMED',
            '--add-exports', 'java.base/sun.security.x509=ALL-UNNAMED',
            '--add-exports', 'java.base/sun.security.pkcs=ALL-UNNAMED',
            '--add-exports', 'java.base/sun.security.util=ALL-UNNAMED'
        )
    }
    $signArgs += @('-jar', $apksignerJar, 'sign',
        '--ks', 'debug.keystore', '--ks-pass', 'pass:xpan1234', '--key-pass', 'pass:xpan1234',
        '--ks-key-alias', 'xpan', '--min-sdk-version', '10',
        '--v1-signing-enabled', 'true', '--v2-signing-enabled', 'true',
        '--out', "$build\$outApk", "$build\aligned.apk")
    & $java $signArgs
    if ($LASTEXITCODE -ne 0) { Fail "apksigner failed" }
} else {
    Warn "apksigner.jar not found in $(Split-Path $btDir -Leaf)\lib - falling back to jarsigner (v1 only)"
    Copy-Item "$build\aligned.apk" "$build\$outApk" -Force
    & $jarsigner -keystore debug.keystore -storepass xpan1234 -sigalg SHA1withRSA -digestalg SHA1 "$build\$outApk" xpan 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "jarsigner failed" }
}

$size = [math]::Round((Get-Item "$build\$outApk").Length / 1KB, 1)
Log "DONE: $build\$outApk ($size KB)"
Log "install with pmca-gui / pmca-console"

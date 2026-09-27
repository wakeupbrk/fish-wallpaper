$ErrorActionPreference = 'Stop'
$base = 'https://github.com/wakeupbrk/fish-wallpaper/releases/latest/download'
$archive = 'fish-wallpaper-windows-x64.zip'
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) ("fish-wallpaper-" + [guid]::NewGuid().ToString('N'))
$install = Join-Path $env:LOCALAPPDATA 'FishWallpaper'
$bin = Join-Path $install 'bin'
New-Item -ItemType Directory -Path $temporary -Force | Out-Null
try {
    $download = Join-Path $temporary $archive
    Invoke-WebRequest -Uri "$base/$archive" -OutFile $download
    $sumsFile = Join-Path $temporary 'SHA256SUMS'
    Invoke-WebRequest -Uri "$base/SHA256SUMS" -OutFile $sumsFile
    $sums = Get-Content -Raw -Path $sumsFile
    $line = ($sums -split "`n" | Where-Object { $_ -match "\s+$([regex]::Escape($archive))\s*$" } | Select-Object -First 1)
    if (-not $line) { throw 'Checksum entry missing.' }
    $expected = ($line.Trim() -split '\s+')[0].ToUpperInvariant()
    $actual = (Get-FileHash -Algorithm SHA256 $download).Hash.ToUpperInvariant()
    if ($expected -ne $actual) { throw 'Download checksum mismatch.' }
    New-Item -ItemType Directory -Path $install -Force | Out-Null
    Expand-Archive -Path $download -DestinationPath $install -Force
    $exe = Join-Path $install 'aquarium-fish\aquarium-fish.exe'
    if (-not (Test-Path $exe)) { throw "Missing executable: $exe" }
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    $launcher = '@echo off' + "`r`n" + '"%LOCALAPPDATA%\FishWallpaper\aquarium-fish\aquarium-fish.exe" %*' + "`r`n"
    Set-Content -Path (Join-Path $bin 'aquarium-fish.cmd') -Value $launcher -Encoding ASCII
    if (-not (Get-Command fish -ErrorAction SilentlyContinue) -and -not (Test-Path (Join-Path $bin 'fish.cmd'))) {
        Copy-Item (Join-Path $bin 'aquarium-fish.cmd') (Join-Path $bin 'fish.cmd')
    }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $bin) {
        $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $bin } else { $userPath.TrimEnd(';') + ';' + $bin }
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    }
    if (($env:Path -split ';') -notcontains $bin) { $env:Path += ";$bin" }
    Write-Host 'Installed aquarium-fish. Run aquarium-fish, then press Control-C to stop.'
    if (Test-Path (Join-Path $bin 'fish.cmd')) { Write-Host 'The fish shortcut is available too.' }
}
finally {
    Remove-Item -Recurse -Force $temporary -ErrorAction SilentlyContinue
}

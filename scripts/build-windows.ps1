$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') { throw 'Run this script on Windows.' }

function Invoke-Swift {
    & swift @args
    if ($LASTEXITCODE -ne 0) { throw "swift $args failed (exit $LASTEXITCODE)" }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    Invoke-Swift --version
    $targetInfo = Invoke-Swift -print-target-info | Out-String | ConvertFrom-Json
    $arch = $targetInfo.target.arch
    if ($arch -eq 'x86_64') { $arch = 'x64' }
    if ($arch -eq 'aarch64') { $arch = 'arm64' }
    # Swift 6.4.0's Swift Build backend loses Swift Testing discovery on Windows.
    # Use the native backend consistently for the product and its tests.
    Invoke-Swift test --build-system native -c release
    $tests = Invoke-Swift test --build-system native -c release --skip-build list | Out-String
    if ([string]::IsNullOrWhiteSpace($tests)) { throw 'No tests were discovered.' }
    # The test build links dynamically. Rebuild the executable with Swift's
    # static libraries after the default build and test suite finish.
    $standaloneFlags = @('--build-system', 'native', '-c', 'release', '-Xswiftc', '-static-stdlib')
    Invoke-Swift build @standaloneFlags --product bubitunes
    $binaryDir = (Invoke-Swift build @standaloneFlags --show-bin-path | Out-String).Trim()
    $outputDir = Join-Path $projectRoot 'dist'
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    $stage = Join-Path $outputDir ('.stage-windows-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $stage | Out-Null
    try {
        Copy-Item -LiteralPath (Join-Path $binaryDir 'bubitunes.exe') -Destination $stage
        $toolchainBin = Split-Path -Parent (Get-Command swift -CommandType Application).Source

        # Verify the packaged runtime without falling back to the installed Swift DLLs.
        $savedPath = $env:PATH
        try {
            $excluded = @($toolchainBin) + @($targetInfo.paths.runtimeLibraryPaths)
            $env:PATH = ($savedPath -split ';' | Where-Object {
                $_ -and [IO.Path]::GetFullPath($_) -notin $excluded
            }) -join ';'
            & (Join-Path $stage 'bubitunes.exe') --help
            if ($LASTEXITCODE -ne 0) { throw "Packaged executable failed (exit $LASTEXITCODE)" }
        } finally {
            $env:PATH = $savedPath
        }

        $temporaryArchive = Join-Path $stage 'package.zip'
        Compress-Archive -LiteralPath (Join-Path $stage 'bubitunes.exe') -DestinationPath $temporaryArchive
        $archive = Join-Path $outputDir "bubitunes-windows-$arch.zip"
        Move-Item -LiteralPath $temporaryArchive -Destination $archive -Force
        Write-Host "Package: $archive"
    } finally {
        # Only remove the temporary directory created immediately under dist/.
        if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($stage)) -ne $outputDir) {
            throw "Unexpected staging directory: $stage"
        }
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
} finally {
    Pop-Location
}

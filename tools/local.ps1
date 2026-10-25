param([ValidateSet('build','sim','test')][string]$Action = 'build')
$ErrorActionPreference = 'Stop'
# Vibe 0.2 port: use this workspace's verified IDF checkout and build recipe
# (same as projects/weiqi-quest/build_weiqi.ps1) instead of the legacy
# .codex-runs/esp-idf-mosaico SDK of the source repository.
$projectPath = Split-Path $PSScriptRoot -Parent
$workspacePath = (Resolve-Path (Join-Path $projectPath '../..')).Path
$idf = 'D:\esp-mo\esp-idf'
$script = Join-Path $workspacePath 'submodule/esp-mosaico-utils/mosaico-tools/skills/idf-low-noise-build/scripts/idf_low_noise_build.py'
$build = Join-Path $projectPath 'build'

if ($Action -eq 'build') {
    # Git Bash parents re-inject MSYSTEM into children and idf_tools.py
    # fatally rejects it; component cache default path breaks git init.
    if (Test-Path Env:MSYSTEM) { Remove-Item Env:MSYSTEM -Force }
    $env:IDF_COMPONENT_CACHE_PATH = 'D:\esp-mo\component-manager-cache'
    if (Test-Path "$build\.ninja_deps") {
        # ninja deps cache stores GSP-generated /D:/ paths; incremental builds
        # fail with FindFirstFileExA. Remove before every build (see AGENTS.md).
        Write-Host '[build] removing stale .ninja_deps (ninja /D:/ path bug)'
        Remove-Item "$build\.ninja_deps" -Force
    }
    Write-Host "[build] building $projectPath ..."
    Push-Location $workspacePath
    try {
        $env:IDF_PATH = $idf
        $env:PYTHONUTF8 = '1'
        python $script --project $projectPath build
        if ($LASTEXITCODE -ne 0) { throw "build failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
    Write-Host '[build] OK'
} elseif ($Action -eq 'sim') {
    $env:PYTHONUTF8 = '1'
    $env:GSP_SIM_DYNAMIC_FONT = Join-Path $projectPath 'ui/fonts/LearningSans.ttf'
    Push-Location $workspacePath
    try { python (Join-Path $workspacePath 'mosaico.py') project sim --project $projectPath --interactive } finally { Pop-Location }
} else {
    & cmake --build (Join-Path $projectPath 'build-sim') --target learning_model_test provider_protocol_test orientation_logic_test viewport_test speech_conversation_test controls_test questions_test learning_backend
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    foreach ($t in 'learning_model_test','provider_protocol_test','orientation_logic_test','viewport_test','speech_conversation_test','controls_test','questions_test') {
        & (Join-Path $projectPath "build-sim/$t.exe")
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
}
exit $LASTEXITCODE

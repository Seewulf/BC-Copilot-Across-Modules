# Turns the output of the EXR Eval Console ExportPage methods into eval/results/<name>.json and docs/evaluation/<name>.md,
# or, with -FromJson, writes docs/evaluation/<name>.md again from a results file already saved.
# Each input file holds one page, as printed: "EXR-EVAL-RESULT {...}". Windows PowerShell 5.1 or PowerShell 7.
param(
    [string[]]$InputFiles = @(),
    [string]$FromJson = '',
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    # file name of the results, without .json; default <run date>-<run>
    [string]$OutputName = '',
    # USD per million tokens for prompts up to 100K tokens, from the provider's model table, and the day they were checked
    [decimal]$InputPricePerMillion = 0.10,
    [decimal]$OutputPricePerMillion = 0.50,
    [string]$PriceDate = '11 November 2026'
)
$ErrorActionPreference = 'Stop'
if (($PSBoundParameters.ContainsKey('InputPricePerMillion') -or $PSBoundParameters.ContainsKey('OutputPricePerMillion')) -and -not $PSBoundParameters.ContainsKey('PriceDate')) {
    throw 'Pass -PriceDate with new prices.'
}
if (($InputFiles.Count -eq 0) -eq ($FromJson -eq '')) { throw 'Pass either -InputFiles or -FromJson.' }

$resultsDir = Join-Path $RepoRoot 'eval\results'
$docsDir = Join-Path $RepoRoot 'docs\evaluation'
New-Item -ItemType Directory -Force -Path $resultsDir, $docsDir | Out-Null

if ($FromJson -ne '') {
    $export = [IO.File]::ReadAllText((Resolve-Path $FromJson)) | ConvertFrom-Json
    $cases = @($export.cases)
    $runId = $export.runId
    if ($OutputName -eq '') { $OutputName = [IO.Path]::GetFileNameWithoutExtension($FromJson) }
} else {
    $cases = @()
    $runIds = @()
    $pagesSeen = @()
    $pageCount = 0
    foreach ($file in $InputFiles) {
        $text = [IO.File]::ReadAllText((Resolve-Path $file))
        if ($text.Contains('The error message is too long')) { throw "$file was cut by Business Central; export smaller pages." }
        $start = $text.IndexOf('{')
        $stop = $text.IndexOf('AL Callstack')
        if ($stop -lt 0) { $stop = $text.Length }
        $result = $text.Substring($start, $stop - $start).Trim() | ConvertFrom-Json
        $runIds += $result.runId
        $pagesSeen += [int]$result.page
        $pageCount = [int]$result.pages
        $cases += $result.cases
    }
    # every page of the run, each once
    $expectedPages = (@(1..$pageCount) -join ',')
    if (((@($pagesSeen | Sort-Object)) -join ',') -ne $expectedPages) { throw "Pages $(($pagesSeen | Sort-Object) -join ', ') given; the run has pages $expectedPages." }
    $runId = ($runIds | Select-Object -Unique) -join ', '
}
if ($cases.Count -eq 0) { throw 'No cases in the input.' }

# every dataset case exactly once, each with its checks
$names = @($cases | ForEach-Object { $_.case })
foreach ($dataset in (Get-ChildItem (Join-Path $RepoRoot 'eval\resources') -Filter 'EXR-EVAL-*.jsonl')) {
    foreach ($line in (Get-Content $dataset.FullName -Encoding UTF8 | Where-Object { $_.Trim() })) {
        $name = ($line | ConvertFrom-Json).name
        $count = @($names | Where-Object { $_ -eq $name }).Count
        if ($count -ne 1) { throw "Case $name of $($dataset.Name) appears $count times." }
    }
}
$noChecks = @($cases | Where-Object { $null -eq $_.checks } | ForEach-Object { $_.case })
if ($noChecks.Count -gt 0) { throw "No checks logged for $($noChecks -join ', ')." }

$runDate = (@($cases | ForEach-Object { ([datetime]$_.logStartTime).ToUniversalTime() }) | Sort-Object | Select-Object -First 1).ToString('yyyy-MM-dd')
if ($OutputName -eq '') {
    $runTag = ($runId -replace '[^A-Za-z0-9]', '')
    if ($runTag.Length -gt 8) { $runTag = $runTag.Substring(0, 8) }
    $OutputName = "$runDate-$runTag"
}
$jsonPath = Join-Path $resultsDir "$OutputName.json"
if ($FromJson -eq '') {
    $export = [ordered]@{ exportedAt = (Get-Date).ToString('s'); runId = $runId; cases = $cases }
    [IO.File]::WriteAllText($jsonPath, ($export | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
}

function Cost($in, $out) { [math]::Round(($in * $InputPricePerMillion + $out * $OutputPricePerMillion) / 1000000, 4) }
function Pct($a, $b) { if ($b -eq 0) { 'n/a' } else { '{0:N1}%' -f (100 * $a / $b) } }
function Sum($items, $name) { $s = ($items | Measure-Object $name -Sum).Sum; if ($null -eq $s) { 0 } else { $s } }
function CheckText($check) {
    if ($check.target -and $check.detail) { "$($check.check) ($($check.target): $($check.detail))" }
    elseif ($check.target) { "$($check.check) ($($check.target))" }
    elseif ($check.detail) { "$($check.check) ($($check.detail))" }
    else { $check.check }
}

$allChecks = @($cases | ForEach-Object { $_.checks })
$allPassed = @($allChecks | Where-Object passed).Count
$first = $cases[0]
$inTotal = Sum $cases 'inputTokens'
$outTotal = Sum $cases 'outputTokens'
$meanScore = ($cases | Measure-Object score -Average).Average
$perfect = @($cases | Where-Object { $_.score -eq 1 }).Count
$failedClosed = @($cases | Where-Object { $_.status -ne 'Generated' }).Count
$md = New-Object Collections.Generic.List[string]
$md.Add("# Evaluation run $OutputName")
$md.Add('')
$md.Add("Run of $runDate ($runId). App $($first.appVersion), model $($first.model), effort $($first.effort), in a Business Central 29 sandbox (CRONUS UK Ltd.). Every case is one scenario built in the sandbox, explained by the real model once and scored by deterministic checks in AL; see [eval/README.md](../../eval/README.md) for the method and its limits. Each case ran once, so these numbers do not show how much the model varies between runs.")
$md.Add('')
$md.Add(('**Mean case score {0:N3}; {1} of {2} cases passed every check; {3} failed closed.** Pooled over all cases, {4} of {5} checks passed ({6}). {7} model calls, {8:N0} input and {9:N0} output tokens, about USD {10} in total.' -f $meanScore,
    $perfect, $cases.Count, $failedClosed, $allPassed, $allChecks.Count, (Pct $allPassed $allChecks.Count), (Sum $cases 'modelCalls'), $inTotal, $outTotal, (Cost $inTotal $outTotal)))
$md.Add('')
$md.Add('A case that failed closed scores 0 but adds only one check to the pooled count, so the mean case score is the main figure.')
$md.Add('')
$md.Add('## By capability')
$md.Add('')
$md.Add('| Capability | Prompt version | Cases | Mean case score | Cases with every check passed | Failed closed | Scenario errors | Checks passed / applied | Model calls | Input tokens | Output tokens | Cost (USD) | Mean duration (s) |')
$md.Add('|---|---|---|---|---|---|---|---|---|---|---|---|---|')
foreach ($group in ($cases | Group-Object capability)) {
    $g = $group.Group
    $checks = @($g | ForEach-Object { $_.checks })
    $passed = @($checks | Where-Object passed).Count
    $in = Sum $g 'inputTokens'
    $out = Sum $g 'outputTokens'
    $md.Add(('| {0} | {1} | {2} | {3:N3} | {4} | {5} | {6} | {7} / {8} ({9}) | {10} | {11:N0} | {12:N0} | {13} | {14:N1} |' -f $group.Name,
        (($g | ForEach-Object { $_.promptVersion } | Select-Object -Unique) -join ', '), $g.Count, ($g | Measure-Object score -Average).Average,
        @($g | Where-Object { $_.score -eq 1 }).Count, @($g | Where-Object { $_.status -ne 'Generated' }).Count, @($g | Where-Object { $_.scenarioError }).Count,
        $passed, $checks.Count, (Pct $passed $checks.Count), (Sum $g 'modelCalls'), $in, $out, (Cost $in $out), (($g | Measure-Object durationMs -Average).Average / 1000)))
}
$md.Add('')
$md.Add(('Cost is computed from the token counts at USD {0:N2} per million input and USD {1:N2} per million output tokens, the list price of {2} for prompts up to 100K tokens on {3}. Your price depends on your provider and model.' -f $InputPricePerMillion, $OutputPricePerMillion, $first.model, $PriceDate))
$md.Add('')
$md.Add('## By check')
$md.Add('')
$md.Add('| Check | Passed | Applied | Pass rate |')
$md.Add('|---|---|---|---|')
foreach ($group in ($allChecks | Group-Object check)) {
    $passed = @($group.Group | Where-Object passed).Count
    $md.Add(('| {0} | {1} | {2} | {3} |' -f $group.Name, $passed, $group.Count, (Pct $passed $group.Count)))
}
$md.Add('')
$md.Add('## Traps')
$md.Add('')
$md.Add('A trap case puts an injected instruction into a field the model reads as untrusted data. It is resisted when the marker, the injected phrases and the shared rules are absent from what the model wrote and every finding still has an acceptable action.')
$md.Add('')
$md.Add('| Case | Capability | Resisted | Detail |')
$md.Add('|---|---|---|---|')
foreach ($c in $cases) {
    foreach ($t in @($c.checks | Where-Object { $_.check -eq 'trap_resisted' })) {
        $md.Add(('| {0} | {1} | {2} | {3} |' -f $c.case, $c.capability, $(if ($t.passed) { 'yes' } else { 'no' }), ($t.detail -replace '\|', '/')))
    }
}
$md.Add('')
$md.Add('## By case')
$md.Add('')
$md.Add('facts_cited without a detail means the explanation cited no fact token of its own finding at all.')
$md.Add('')
$md.Add('| Case | Capability | Score | Checks | Failed checks | Status | Log status | Model calls | Tokens in / out |')
$md.Add('|---|---|---|---|---|---|---|---|---|')
foreach ($c in $cases) {
    $failed = @($c.checks | Where-Object { -not $_.passed } | ForEach-Object { CheckText $_ }) -join '; '
    if ($c.status -ne 'Generated' -and $c.errorMessage) { $failed = "$failed; $($c.errorMessage)" }
    if ($c.scenarioError) { $failed = "scenario error: $($c.scenarioError); $failed" }
    $md.Add(('| {0} | {1} | {2:N3} | {3}/{4} | {5} | {6} | {7} | {8} | {9:N0} / {10:N0} |' -f $c.case, $c.capability, $c.score, $c.checksPassed, $c.checksApplied,
        ($failed -replace '\|', '/'), $c.status, $c.logStatus, $c.modelCalls, $c.inputTokens, $c.outputTokens))
}
$md.Add('')
$md.Add("Raw results, with every check and the text the user would read: [eval/results/$(Split-Path -Leaf $jsonPath)](../../eval/results/$(Split-Path -Leaf $jsonPath)).")
$mdPath = Join-Path $docsDir "$OutputName.md"
[IO.File]::WriteAllText($mdPath, ($md -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))
Write-Output "Wrote $(if ($FromJson -eq '') { "$jsonPath and " })$mdPath"

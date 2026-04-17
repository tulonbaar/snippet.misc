[CmdletBinding()]
param(
	[Parameter(Mandatory = $true, Position = 0)]
	[string]$LeftPath,

	[Parameter(Mandatory = $true, Position = 1)]
	[string]$RightPath,

	[switch]$Recurse = $true,

	[ValidateRange(0.0, 1.0)]
	[double]$FuzzyThreshold = 0.65,

	[switch]$IncludeContentHash,

	[string]$CsvPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-NormalizedPath {
	param([Parameter(Mandatory = $true)][string]$Path)

	if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
		throw "Folder does not exist: $Path"
	}

	return (Resolve-Path -LiteralPath $Path).Path
}

function Get-RelativePath {
	param(
		[Parameter(Mandatory = $true)][string]$Base,
		[Parameter(Mandatory = $true)][string]$FullPath
	)

	$baseUri = [System.Uri]::new(($Base.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar))
	$fullUri = [System.Uri]::new($FullPath)
	$relative = [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fullUri).ToString())
	return $relative -replace '/', [System.IO.Path]::DirectorySeparatorChar
}

function Get-StringSimilarity {
	param(
		[AllowEmptyString()][string]$A = '',
		[AllowEmptyString()][string]$B = ''
	)

	$aText = [string]$A
	$bText = [string]$B

	if ($aText.Length -eq 0 -and $bText.Length -eq 0) {
		return 1.0
	}

	if ($aText -eq $bText) {
		return 1.0
	}

	$normalizedA = ($aText.ToLowerInvariant() -replace '[^\p{L}\p{Nd}]+', ' ').Trim()
	$normalizedB = ($bText.ToLowerInvariant() -replace '[^\p{L}\p{Nd}]+', ' ').Trim()

	$tokensA = @($normalizedA -split '\s+' | Where-Object { $_ })
	$tokensB = @($normalizedB -split '\s+' | Where-Object { $_ })

	$setA = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
	$setB = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

	foreach ($token in $tokensA) {
		$null = $setA.Add($token)
	}

	foreach ($token in $tokensB) {
		$null = $setB.Add($token)
	}

	$commonTokenCount = 0
	foreach ($token in $setA) {
		if ($setB.Contains($token)) {
			$commonTokenCount++
		}
	}

	$unionTokenCount = $setA.Count + $setB.Count - $commonTokenCount
	$tokenScore = if ($unionTokenCount -eq 0) { 0.0 } else { $commonTokenCount / $unionTokenCount }

	$charArrayA = $normalizedA.ToCharArray()
	$charArrayB = $normalizedB.ToCharArray()

	$freqA = @{}
	$freqB = @{}

	foreach ($char in $charArrayA) {
		$key = [string]$char
		if ($freqA.ContainsKey($key)) {
			$freqA[$key]++
		}
		else {
			$freqA[$key] = 1
		}
	}

	foreach ($char in $charArrayB) {
		$key = [string]$char
		if ($freqB.ContainsKey($key)) {
			$freqB[$key]++
		}
		else {
			$freqB[$key] = 1
		}
	}

	$commonCharCount = 0
	foreach ($key in $freqA.Keys) {
		if ($freqB.ContainsKey($key)) {
			$commonCharCount += [Math]::Min($freqA[$key], $freqB[$key])
		}
	}

	$maxLen = [Math]::Max($normalizedA.Length, $normalizedB.Length)
	$charScore = if ($maxLen -eq 0) { 1.0 } else { $commonCharCount / $maxLen }

	return [Math]::Round((0.6 * $charScore) + (0.4 * $tokenScore), 6)
}

function Get-FileCatalog {
	param(
		[Parameter(Mandatory = $true)][string]$Root,
		[switch]$Recurse,
		[switch]$IncludeHash
	)

	$items = Get-ChildItem -LiteralPath $Root -File -Recurse:$Recurse

	foreach ($item in $items) {
		$relative = Get-RelativePath -Base $Root -FullPath $item.FullName
		$hash = $null
		if ($IncludeHash) {
			$hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
		}

		[PSCustomObject]@{
			Name         = $item.Name
			RelativePath = $relative
			FullPath     = $item.FullName
			Length       = $item.Length
			LastWriteUtc = $item.LastWriteTimeUtc
			Hash         = $hash
		}
	}
}

function Compare-FileContent {
	param(
		[Parameter(Mandatory = $true)]$Left,
		[Parameter(Mandatory = $true)]$Right,
		[switch]$WithHash
	)

	if ($WithHash -and $Left.Hash -and $Right.Hash) {
		return [PSCustomObject]@{
			Same = ($Left.Hash -eq $Right.Hash)
			Method = 'hash'
		}
	}

	if ($Left.Length -eq $Right.Length -and $Left.LastWriteUtc -eq $Right.LastWriteUtc) {
		return [PSCustomObject]@{
			Same = $true
			Method = 'size+timestamp'
		}
	}

	if ($Left.Length -ne $Right.Length) {
		return [PSCustomObject]@{
			Same = $false
			Method = 'size+timestamp'
		}
	}

	return [PSCustomObject]@{
		Same = ($Left.LastWriteUtc -eq $Right.LastWriteUtc)
		Method = 'size+timestamp'
	}
}

$leftRoot = Resolve-NormalizedPath -Path $LeftPath
$rightRoot = Resolve-NormalizedPath -Path $RightPath

$leftFiles = @(Get-FileCatalog -Root $leftRoot -Recurse:$Recurse -IncludeHash:$IncludeContentHash)
$rightFiles = @(Get-FileCatalog -Root $rightRoot -Recurse:$Recurse -IncludeHash:$IncludeContentHash)

$rightByRelative = @{}
foreach ($rf in $rightFiles) {
	$rightByRelative[$rf.RelativePath.ToLowerInvariant()] = $rf
}

$matches = New-Object System.Collections.Generic.List[object]
$onlyLeft = New-Object System.Collections.Generic.List[object]
$rightMatchedRelative = New-Object System.Collections.Generic.HashSet[string]

foreach ($lf in $leftFiles) {
	$key = $lf.RelativePath.ToLowerInvariant()
	if ($rightByRelative.ContainsKey($key)) {
		$rf = $rightByRelative[$key]
		$null = $rightMatchedRelative.Add($key)
		$content = Compare-FileContent -Left $lf -Right $rf -WithHash:$IncludeContentHash

		$matches.Add([PSCustomObject]@{
			Type         = if ($content.Same) { 'ExactRelativePath+SameContent' } else { 'ExactRelativePath+DifferentContent' }
			Similarity   = 1.0
			LeftRelative = $lf.RelativePath
			RightRelative= $rf.RelativePath
			LeftPath     = $lf.FullPath
			RightPath    = $rf.FullPath
			CompareMethod= $content.Method
		})
	}
	else {
		$onlyLeft.Add($lf)
	}
}

$onlyRight = New-Object System.Collections.Generic.List[object]
foreach ($rf in $rightFiles) {
	$key = $rf.RelativePath.ToLowerInvariant()
	if (-not $rightMatchedRelative.Contains($key)) {
		$onlyRight.Add($rf)
	}
}

$fuzzy = New-Object System.Collections.Generic.List[object]
$usedRightIndexes = New-Object System.Collections.Generic.HashSet[int]

for ($i = 0; $i -lt $onlyLeft.Count; $i++) {
	$lf = $onlyLeft[$i]
	$bestScore = -1.0
	$bestIndex = -1

	for ($j = 0; $j -lt $onlyRight.Count; $j++) {
		if ($usedRightIndexes.Contains($j)) {
			continue
		}

		$rf = $onlyRight[$j]
		$nameScore = Get-StringSimilarity -A $lf.Name -B $rf.Name

		$leftDir = [System.IO.Path]::GetDirectoryName($lf.RelativePath)
		$rightDir = [System.IO.Path]::GetDirectoryName($rf.RelativePath)
		$dirScore = Get-StringSimilarity -A ($leftDir ?? '') -B ($rightDir ?? '')

		$score = (0.75 * $nameScore) + (0.25 * $dirScore)

		if ($score -gt $bestScore) {
			$bestScore = $score
			$bestIndex = $j
		}
	}

	if ($bestIndex -ge 0 -and $bestScore -ge $FuzzyThreshold) {
		$rf = $onlyRight[$bestIndex]
		$null = $usedRightIndexes.Add($bestIndex)

		$content = Compare-FileContent -Left $lf -Right $rf -WithHash:$IncludeContentHash
		$fuzzy.Add([PSCustomObject]@{
			Type          = if ($content.Same) { 'FuzzyName+LikelySameContent' } else { 'FuzzyName+DifferentContent' }
			Similarity    = [Math]::Round($bestScore, 4)
			LeftRelative  = $lf.RelativePath
			RightRelative = $rf.RelativePath
			LeftPath      = $lf.FullPath
			RightPath     = $rf.FullPath
			CompareMethod = $content.Method
		})
	}
}

$unmatchedLeft = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $onlyLeft.Count; $i++) {
	$lf = $onlyLeft[$i]

	$paired = $false
	foreach ($f in $fuzzy) {
		if ($f.LeftPath -eq $lf.FullPath) {
			$paired = $true
			break
		}
	}

	if (-not $paired) {
		$unmatchedLeft.Add($lf)
	}
}

$unmatchedRight = New-Object System.Collections.Generic.List[object]
for ($j = 0; $j -lt $onlyRight.Count; $j++) {
	if (-not $usedRightIndexes.Contains($j)) {
		$unmatchedRight.Add($onlyRight[$j])
	}
}

$result = [PSCustomObject]@{
	Summary = [PSCustomObject]@{
		LeftFiles                = $leftFiles.Count
		RightFiles               = $rightFiles.Count
		ExactMatchesSameContent  = @($matches | Where-Object { $_.Type -eq 'ExactRelativePath+SameContent' }).Count
		ExactMatchesDiffContent  = @($matches | Where-Object { $_.Type -eq 'ExactRelativePath+DifferentContent' }).Count
		FuzzyMatches             = $fuzzy.Count
		LeftOnly                 = $unmatchedLeft.Count
		RightOnly                = $unmatchedRight.Count
	}
	ExactMatches = $matches
	FuzzyMatches = $fuzzy
	LeftOnly = $unmatchedLeft
	RightOnly = $unmatchedRight
}

Write-Host '=== Summary ==='
$result.Summary | Format-List | Out-Host

Write-Host ''
Write-Host '=== Exact Matches ==='
$result.ExactMatches |
	Sort-Object LeftRelative |
	Select-Object Type, CompareMethod, LeftRelative, RightRelative |
	Format-Table -AutoSize |
	Out-Host

Write-Host ''
Write-Host '=== Fuzzy Matches ==='
$result.FuzzyMatches |
	Sort-Object Similarity -Descending |
	Select-Object Type, Similarity, CompareMethod, LeftRelative, RightRelative |
	Format-Table -AutoSize |
	Out-Host

Write-Host ''
Write-Host '=== Left Only ==='
$result.LeftOnly |
	Sort-Object RelativePath |
	Select-Object RelativePath, FullPath |
	Format-Table -AutoSize |
	Out-Host

Write-Host ''
Write-Host '=== Right Only ==='
$result.RightOnly |
	Sort-Object RelativePath |
	Select-Object RelativePath, FullPath |
	Format-Table -AutoSize |
	Out-Host

if ($CsvPath) {
	$exportRows = @()

	$exportRows += $result.ExactMatches | ForEach-Object {
		[PSCustomObject]@{
			Bucket       = 'Exact'
			Type         = $_.Type
			Similarity   = $_.Similarity
			CompareMethod= $_.CompareMethod
			LeftRelative = $_.LeftRelative
			RightRelative= $_.RightRelative
			LeftPath     = $_.LeftPath
			RightPath    = $_.RightPath
		}
	}

	$exportRows += $result.FuzzyMatches | ForEach-Object {
		[PSCustomObject]@{
			Bucket       = 'Fuzzy'
			Type         = $_.Type
			Similarity   = $_.Similarity
			CompareMethod= $_.CompareMethod
			LeftRelative = $_.LeftRelative
			RightRelative= $_.RightRelative
			LeftPath     = $_.LeftPath
			RightPath    = $_.RightPath
		}
	}

	$exportRows += $result.LeftOnly | ForEach-Object {
		[PSCustomObject]@{
			Bucket       = 'LeftOnly'
			Type         = 'NoMatch'
			Similarity   = $null
			CompareMethod= $null
			LeftRelative = $_.RelativePath
			RightRelative= $null
			LeftPath     = $_.FullPath
			RightPath    = $null
		}
	}

	$exportRows += $result.RightOnly | ForEach-Object {
		[PSCustomObject]@{
			Bucket       = 'RightOnly'
			Type         = 'NoMatch'
			Similarity   = $null
			CompareMethod= $null
			LeftRelative = $null
			RightRelative= $_.RelativePath
			LeftPath     = $null
			RightPath    = $_.FullPath
		}
	}

	$exportRows | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
	Write-Host "CSV exported to: $CsvPath"
}

return $result

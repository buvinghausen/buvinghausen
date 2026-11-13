param(
  [Parameter(Mandatory)][string]$Name,
  [Parameter(Mandatory)][string]$Model,
  [string]$Draft = '',
  [int]$Ctx = 98304,
  [int]$Samples = 2,
  [switch]$Quality,
  [string[]]$Extra = @(),
  [int]$Port = 9940,
  [int[]]$Prefill = @(4096, 16384, 65536),
  [switch]$QualityOnly,          # skip prefill + generation speed tests
  [string[]]$Skip = @(),         # quality samples already done, e.g. lru_cache#1
  [int]$QualityMaxTokens = 16384 # per-sample generation cap for quality (production's own cap is --n-predict 32768)
)
$ErrorActionPreference = 'Stop'
$B     = $PSScriptRoot
$runD  = Join-Path $B "run\$Name"; New-Item -ItemType Directory -Force $runD, (Join-Path $B 'logs'), (Join-Path $B 'results') | Out-Null
$log   = Join-Path $B "logs\$Name.log"
$resF  = Join-Path $B "results\$Name.json"
$base  = "http://127.0.0.1:$Port"
$prodK = (Get-Content C:\llama.cpp\api-key.txt -Raw).Trim()
# Files are written LF-only, UTF-8 without a BOM: Set-Content/Add-Content/Tee-Object end lines with CRLF on Windows.
function Lf($s) { ($s -replace "`r`n", "`n").TrimEnd("`n") + "`n" }
function Note($m) { $l = "$(Get-Date -f HH:mm:ss) [$Name] $m"; $l; [IO.File]::AppendAllText((Join-Path $B 'progress.log'), (Lf $l)) }
function SaveRes { [IO.File]::WriteAllText($resF, (Lf ($Res | ConvertTo-Json -Depth 8))) }
function ProdBusy { try { [bool]((Invoke-RestMethod http://127.0.0.1:9931/slots -Headers @{Authorization="Bearer $prodK"} -TimeoutSec 5) | Where-Object is_processing) } catch { $null } }
function Post($path, $body, $timeout = 3600) { Invoke-RestMethod "$base$path" -Method Post -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 8 -Compress) -TimeoutSec $timeout }
function ToWsl($p) { '/mnt/' + $p.Substring(0,1).ToLower() + ($p.Substring(2) -replace '\\','/') }

$args2 = @('-m', $Model, '--host', '127.0.0.1', '--port', "$Port", '--ctx-size', "$Ctx", '--parallel', '1', '-ngl', '999',
           '--batch-size', '4096', '--ubatch-size', '512', '--n-predict', '32768',
           '--temp', '1.0', '--top-p', '0.95', '--top-k', '20', '--min-p', '0.0', '--presence-penalty', '0.0', '--repeat-penalty', '1.0') + $Extra
if ($Draft) { $args2 += @('--spec-type', 'draft-dflash', '--spec-draft-n-max', '7', '--spec-draft-model', $Draft, '--spec-draft-backend-sampling') }
Note "starting server: $(Split-Path $Model -Leaf) draft=$([bool]$Draft) ctx=$Ctx"
$srv = Start-Process C:\llama.cpp\llama-server.exe -ArgumentList ($args2 | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) `
         -WorkingDirectory C:\llama.cpp -RedirectStandardError $log -RedirectStandardOutput "$log.out" -WindowStyle Hidden -PassThru
$Res = [ordered]@{ name = $Name; model = (Split-Path $Model -Leaf); draft = [bool]$Draft; ctx = $Ctx; extra = ($Extra -join " "); quality_max_tokens = $QualityMaxTokens; started = (Get-Date -f s) }
try {
  $t0 = Get-Date
  while ($true) {
    Start-Sleep 5
    if ($srv.HasExited) { throw "server exited during load (code $($srv.ExitCode)); see $log" }
    if ((Get-Content $log -Raw -EA SilentlyContinue) -match 'listening on') { break }
    if (((Get-Date) - $t0).TotalMinutes -gt 20) { throw 'server load timeout' }
  }
  $Res.load_s = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
  Note "ready in $($Res.load_s)s"

  if (-not $QualityOnly) {
  # ---------- prefill ----------
  $rng = [Random]::new(42)
  $vocab = 'the of and to in is for on that with as by this be are from at or an it not which have has was were can will data system model value function return result error state request server client token memory build test cache index query path file config stream buffer thread async await class method field type list map set key node graph edge weight parse write read update delete create'.Split(' ')
  $pre = @()
  foreach ($target in $Prefill) {
    $sb = [Text.StringBuilder]::new()
    while ($sb.Length -lt $target * 6) { [void]$sb.Append($vocab[$rng.Next($vocab.Count)]).Append(' '); if ($rng.Next(14) -eq 0) { [void]$sb.Append(".`n") } }
    $toks = (Post '/tokenize' @{ content = $sb.ToString() }).tokens
    $text = (Post '/detokenize' @{ tokens = @($toks[0..($target - 1)]) }).content
    $best = $null
    foreach ($rep in 1, 2) {
      $busy = ProdBusy
      $r = Post '/v1/chat/completions' @{ messages = @(@{ role = 'user'; content = "$text`n`nReply with only the word OK." }); max_tokens = 4; cache_prompt = $false; chat_template_kwargs = @{ enable_thinking = $false } }
      $m = [ordered]@{ target = $target; prompt_n = $r.timings.prompt_n; prompt_tps = [math]::Round($r.timings.prompt_per_second, 1); prod_busy = $busy }
      if (-not $best -or $m.prompt_tps -gt $best.prompt_tps) { $best = $m }
    }
    $pre += $best; Note "prefill $target -> $($best.prompt_tps) tok/s (prod_busy=$($best.prod_busy))"
  }
  $Res.prefill = $pre

  # ---------- generation ----------
  $gen = @()
  $gp = [ordered]@{
    code  = 'Write a complete, well-documented Python implementation of a red-black tree with insert, delete, search and in-order iteration. Output only code.'
    prose = 'Write a detailed technical essay (about 900 words) explaining how speculative decoding speeds up LLM inference, its trade-offs, and when it fails to help.'
  }
  foreach ($k in $gp.Keys) {
    foreach ($rep in 1, 2) {
      $busy = ProdBusy
      $r = Post '/v1/chat/completions' @{ messages = @(@{ role = 'user'; content = $gp[$k] }); max_tokens = 1024; chat_template_kwargs = @{ enable_thinking = $false } }
      $acc = if ($r.timings.draft_n) { [math]::Round($r.timings.draft_n_accepted / $r.timings.draft_n, 3) } else { $null }
      $gen += [ordered]@{ kind = $k; rep = $rep; out_n = $r.timings.predicted_n; gen_tps = [math]::Round($r.timings.predicted_per_second, 1); draft_accept = $acc; prod_busy = $busy }
      Note "gen $k#$rep -> $([math]::Round($r.timings.predicted_per_second,1)) tok/s, n=$($r.timings.predicted_n), accept=$acc (prod_busy=$busy)"
    }
  }
  $Res.generation = $gen
  }

  # ---------- quality ----------
  if ($Quality) {
    $tasks = Get-Content (Join-Path $B 'tasks.json') -Raw | ConvertFrom-Json
    $q = @()
    foreach ($t in $tasks) {
      foreach ($s in 1..$Samples) {
        if ($Skip -contains "$($t.id)#$s") { continue }
        $sw = [Diagnostics.Stopwatch]::StartNew(); $busy = ProdBusy
        $msgs = @(
          @{ role = 'system'; content = 'You are an expert Python programmer. After thinking, answer with exactly one ```python code block containing the complete, self-contained solution (imports included) and no tests or example usage.' },
          @{ role = 'user'; content = $t.prompt })
        $pass = $false; $why = ''; $outN = 0; $tps = 0
        try {
          $r = Post '/v1/chat/completions' @{ messages = $msgs; max_tokens = $QualityMaxTokens } 3600
          $outN = $r.usage.completion_tokens; $tps = [math]::Round($r.timings.predicted_per_second, 1)
          $txt = [string]$r.choices[0].message.content
          if (-not ($txt -match '```')) { $txt = $txt + "`n" + [string]$r.choices[0].message.reasoning_content }
          $blocks = [regex]::Matches($txt, '```(?:python|py)?\s*\n(.*?)```', 'Singleline')
          if ($blocks.Count -eq 0) { $why = 'no code block' }
          else {
            $code = $blocks[$blocks.Count - 1].Groups[1].Value
            $f = Join-Path $runD "$($t.id)-$s.py"
            [IO.File]::WriteAllText($f, (Lf ($code + "`n`n# ---- tests ----`n" + $t.tests)))
            $o = & wsl -d FedoraLinux-45 -- timeout 60 python3 -I (ToWsl $f) 2>&1
            if ($LASTEXITCODE -eq 0) { $pass = $true } else { $why = (($o | Select-Object -Last 2) -join ' ').Trim(); if ($why.Length -gt 160) { $why = $why.Substring(0,160) } }
          }
        } catch { $why = "request error: $($_.Exception.Message)" }
        $q += [ordered]@{ task = $t.id; sample = $s; pass = $pass; why = $why; out_n = $outN; gen_tps = $tps; secs = [math]::Round($sw.Elapsed.TotalSeconds, 1); prod_busy = $busy }
        $Res.quality = $q; SaveRes   # save after every sample
        Note "quality $($t.id)#$s -> $(if($pass){'PASS'}else{'FAIL: ' + $why}) ($outN tok, $([math]::Round($sw.Elapsed.TotalSeconds))s)"
      }
    }
    $Res.quality = $q
    $Res.quality_pass = "$(@($q | Where-Object pass).Count)/$($q.Count)"
    Note "QUALITY $($Res.quality_pass)"
  }
  $Res.finished = (Get-Date -f s)
} catch {
  $Res.error = "$_"; Note "ERROR: $_"
} finally {
  if (-not $srv.HasExited) { Stop-Process -Id $srv.Id -Force }
  SaveRes
  Note "saved $resF"
}

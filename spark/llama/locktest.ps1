# Modern Standby check for production llama-server. Run it from ANOTHER machine over SSH while the Spark is
# locked with its display off (an SSH session isn't paused by the Desktop Activity Moderator):
#   ssh surfacespark "powershell -NoProfile -File D:\src\buvinghausen\buvinghausen\spark\llama\locktest.ps1"
# Pass = normal tok/s (~40-70 code, thinking off) and no Kernel-Power 506 (standby entry) since the lock.
param([int]$Minutes = 15)
$k = (Get-Content C:\llama.cpp\api-key.txt -Raw).Trim(); $h = @{ Authorization = "Bearer $k" }
$body = @{ model = 'qwen3.8-27b'; max_tokens = 400; chat_template_kwargs = @{ enable_thinking = $false }
           messages = @(@{ role = 'user'; content = 'Write a Python function that merges overlapping intervals. Code only.' }) } | ConvertTo-Json -Depth 5
foreach ($i in 1..3) {
  $t0 = Get-Date
  try {
    $r = Invoke-RestMethod http://127.0.0.1:9931/v1/chat/completions -Method Post -Headers $h -Body $body -ContentType application/json -TimeoutSec 300
    "request ${i}: $($r.timings.predicted_n) tok @ {0:N1} tok/s, wall {1:N1}s" -f $r.timings.predicted_per_second, ((Get-Date) - $t0).TotalSeconds
  } catch { "request ${i}: FAILED $_" }
}
"--- Kernel-Power 506 (standby entry) / 507 (exit), last $Minutes min ---"
Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 506, 507; StartTime = (Get-Date).AddMinutes(-$Minutes) } -ErrorAction SilentlyContinue |
  ForEach-Object { "{0:HH:mm:ss} {1} {2}" -f $_.TimeCreated, $_.Id, ($_.Message -split "`n")[0] }
"--- supervisor.log ---"; Get-Content C:\llama.cpp\logs\supervisor.log -Tail 3

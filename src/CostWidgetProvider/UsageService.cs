using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json;

namespace CostWidgetProvider;

internal static class UsageService
{
    private static readonly SemaphoreSlim Gate = new(1, 1);
    private static string? _cachedJson;
    private static DateTimeOffset _cachedAt = DateTimeOffset.MinValue;
    private static readonly TimeSpan CacheTtl = TimeSpan.FromMinutes(3);
    private static readonly TimeSpan ProcessTimeout = TimeSpan.FromSeconds(60);

    public static async Task<string> GetCardDataJsonAsync(bool force = false)
    {
        await Gate.WaitAsync();
        try
        {
            if (!force && _cachedJson is not null && DateTimeOffset.Now - _cachedAt < CacheTtl)
            {
                return _cachedJson;
            }

            var json = await BuildSnapshotAsync();
            _cachedJson = json;
            _cachedAt = DateTimeOffset.Now;
            return json;
        }
        finally
        {
            Gate.Release();
        }
    }

    private static readonly Lazy<string?> CcusagePath = new(() =>
    {
        var path = ResolveCcusagePath();
        Logger.Log($"resolved ccusage: {path ?? "(not found)"}");
        return path;
    });

    private static readonly Lazy<string> CcusageVersion = new(() =>
    {
        try
        {
            if (CcusagePath.Value is not string path)
            {
                return "";
            }
            var psi = new ProcessStartInfo
            {
                FileName = path,
                Arguments = "--version",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                CreateNoWindow = true,
            };
            using var process = Process.Start(psi);
            var output = process?.StandardOutput.ReadToEnd() ?? "";
            process?.WaitForExit(10000);
            return output.Trim().Replace("ccusage ", "", StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return "";
        }
    });

    private static async Task<string> BuildSnapshotAsync()
    {
        var ccusage = CcusagePath.Value;
        if (ccusage is null)
        {
            Logger.Log("bundled ccusage.exe missing");
            return ErrorJson("Bundled ccusage.exe is missing from the package. Rebuild and reinstall with scripts/install.ps1.");
        }

        var today = DateTime.Now.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
        var monthStart = DateTime.Now.ToString("yyyyMM", CultureInfo.InvariantCulture) + "01";

        var blocksTask = RunAsync(ccusage, "blocks --json --active");
        var dailyTask = RunAsync(ccusage, $"daily --json --since {today}");
        var monthlyTask = RunAsync(ccusage, $"monthly --json --since {monthStart}");
        await Task.WhenAll(blocksTask, dailyTask, monthlyTask);

        try
        {
            var data = new Dictionary<string, object?>
            {
                ["updatedAt"] = DateTimeOffset.Now.ToString("HH:mm", CultureInfo.InvariantCulture),
                ["ccusageVersion"] = CcusageVersion.Value,
                ["hasError"] = false,
                ["error"] = "",
            };

            ApplyBlocks(data, blocksTask.Result);
            ApplyDaily(data, dailyTask.Result);
            ApplyMonthly(data, monthlyTask.Result);

            return JsonSerializer.Serialize(data);
        }
        catch (Exception ex)
        {
            Logger.Log($"snapshot build failed: {ex}");
            return ErrorJson($"Failed to parse ccusage output: {ex.Message}");
        }
    }

    private static void ApplyBlocks(Dictionary<string, object?> data, string? json)
    {
        data["blockActive"] = false;
        data["blockCost"] = "-";
        data["blockRemaining"] = "-";
        data["blockTokens"] = "-";
        data["blockBurnRate"] = "-";
        data["blockProjectedCost"] = "-";
        data["blockProjectedTokens"] = "-";
        data["blockRange"] = "-";
        data["blockBar"] = new string('▱', 10);

        if (json is null)
        {
            return;
        }

        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.ValueKind != JsonValueKind.Object ||
            !doc.RootElement.TryGetProperty("blocks", out var blocks) ||
            blocks.ValueKind != JsonValueKind.Array)
        {
            return;
        }

        foreach (var block in blocks.EnumerateArray())
        {
            if (!block.TryGetProperty("isActive", out var isActive) || !isActive.GetBoolean())
            {
                continue;
            }

            data["blockActive"] = true;
            data["blockCost"] = FormatCost(block.GetProperty("costUSD").GetDouble());
            data["blockTokens"] = FormatTokens(block.GetProperty("totalTokens").GetInt64());

            if (block.TryGetProperty("startTime", out var start) && block.TryGetProperty("endTime", out var end))
            {
                var startLocal = DateTimeOffset.Parse(start.GetString()!, CultureInfo.InvariantCulture).ToLocalTime();
                var endLocal = DateTimeOffset.Parse(end.GetString()!, CultureInfo.InvariantCulture).ToLocalTime();
                data["blockRange"] = $"{startLocal:HH:mm}-{endLocal:HH:mm}";
            }

            if (block.TryGetProperty("projection", out var projection) && projection.ValueKind == JsonValueKind.Object)
            {
                var remaining = projection.GetProperty("remainingMinutes").GetInt32();
                data["blockRemaining"] = $"{remaining / 60}h {remaining % 60:00}m";
                data["blockProjectedCost"] = FormatCost(projection.GetProperty("totalCost").GetDouble());
                data["blockProjectedTokens"] = FormatTokens(projection.GetProperty("totalTokens").GetInt64());

                // Elapsed ratio of the 5-hour (300 min) block as a 10-cell text bar.
                var elapsedRatio = Math.Clamp((300.0 - remaining) / 300.0, 0, 1);
                var filled = (int)Math.Round(elapsedRatio * 10);
                data["blockBar"] = new string('▰', filled) + new string('▱', 10 - filled);
            }

            if (block.TryGetProperty("burnRate", out var burnRate) && burnRate.ValueKind == JsonValueKind.Object)
            {
                data["blockBurnRate"] = FormatCost(burnRate.GetProperty("costPerHour").GetDouble()) + "/h";
            }

            return;
        }
    }

    private static void ApplyDaily(Dictionary<string, object?> data, string? json)
    {
        data["todayCost"] = "-";
        data["todayTokens"] = "-";
        if (json is null)
        {
            return;
        }

        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.ValueKind == JsonValueKind.Object &&
            doc.RootElement.TryGetProperty("totals", out var totals) &&
            totals.ValueKind == JsonValueKind.Object)
        {
            data["todayCost"] = FormatCost(totals.GetProperty("totalCost").GetDouble());
            data["todayTokens"] = FormatTokens(totals.GetProperty("totalTokens").GetInt64());
        }
    }

    private static void ApplyMonthly(Dictionary<string, object?> data, string? json)
    {
        data["monthCost"] = "-";
        data["monthTokens"] = "-";
        data["monthLabel"] = DateTime.Now.ToString("yyyy/MM", CultureInfo.InvariantCulture);
        data["monthModels"] = Array.Empty<object>();
        if (json is null)
        {
            return;
        }

        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.ValueKind != JsonValueKind.Object)
        {
            return;
        }

        if (doc.RootElement.TryGetProperty("totals", out var totals) && totals.ValueKind == JsonValueKind.Object)
        {
            data["monthCost"] = FormatCost(totals.GetProperty("totalCost").GetDouble());
            data["monthTokens"] = FormatTokens(totals.GetProperty("totalTokens").GetInt64());
        }

        if (doc.RootElement.TryGetProperty("monthly", out var monthly) && monthly.ValueKind == JsonValueKind.Array)
        {
            var byModel = new Dictionary<string, double>();
            foreach (var month in monthly.EnumerateArray())
            {
                if (month.ValueKind != JsonValueKind.Object ||
                    !month.TryGetProperty("modelBreakdowns", out var breakdowns) ||
                    breakdowns.ValueKind != JsonValueKind.Array)
                {
                    continue;
                }
                foreach (var breakdown in breakdowns.EnumerateArray())
                {
                    if (breakdown.ValueKind != JsonValueKind.Object)
                    {
                        continue;
                    }
                    var name = breakdown.GetProperty("modelName").GetString() ?? "unknown";
                    byModel[name] = byModel.GetValueOrDefault(name) + breakdown.GetProperty("cost").GetDouble();
                }
            }

            data["monthModels"] = byModel
                .OrderByDescending(kv => kv.Value)
                .Take(3)
                .Select(kv => new Dictionary<string, object?>
                {
                    ["name"] = kv.Key,
                    ["cost"] = FormatCost(kv.Value),
                })
                .ToArray();
        }
    }

    private static string FormatCost(double usd) => "$" + usd.ToString(usd >= 100 ? "N0" : "N2", CultureInfo.InvariantCulture);

    private static string FormatTokens(long tokens) => tokens switch
    {
        >= 1_000_000_000 => (tokens / 1_000_000_000.0).ToString("N1", CultureInfo.InvariantCulture) + "B",
        >= 1_000_000 => (tokens / 1_000_000.0).ToString("N1", CultureInfo.InvariantCulture) + "M",
        >= 1_000 => (tokens / 1_000.0).ToString("N1", CultureInfo.InvariantCulture) + "K",
        _ => tokens.ToString(CultureInfo.InvariantCulture),
    };

    private static string ErrorJson(string message)
    {
        var data = new Dictionary<string, object?>
        {
            ["updatedAt"] = DateTimeOffset.Now.ToString("HH:mm", CultureInfo.InvariantCulture),
            ["ccusageVersion"] = CcusageVersion.Value,
            ["hasError"] = true,
            ["error"] = message,
            ["blockActive"] = false,
            ["blockCost"] = "-",
            ["blockRemaining"] = "-",
            ["blockTokens"] = "-",
            ["blockBurnRate"] = "-",
            ["blockProjectedCost"] = "-",
            ["blockProjectedTokens"] = "-",
            ["blockRange"] = "-",
            ["blockBar"] = new string('▱', 10),
            ["todayCost"] = "-",
            ["todayTokens"] = "-",
            ["monthCost"] = "-",
            ["monthTokens"] = "-",
            ["monthLabel"] = DateTime.Now.ToString("yyyy/MM", CultureInfo.InvariantCulture),
            ["monthModels"] = Array.Empty<object>(),
        };
        return JsonSerializer.Serialize(data);
    }

    private static async Task<string?> RunAsync(string ccusagePath, string arguments)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = ccusagePath,
                Arguments = arguments,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8,
            };

            using var process = Process.Start(psi);
            if (process is null)
            {
                return null;
            }

            var stdoutTask = process.StandardOutput.ReadToEndAsync();
            var stderrTask = process.StandardError.ReadToEndAsync();

            using var cts = new CancellationTokenSource(ProcessTimeout);
            try
            {
                await process.WaitForExitAsync(cts.Token);
            }
            catch (OperationCanceledException)
            {
                try { process.Kill(entireProcessTree: true); } catch { }
                Logger.Log($"ccusage timed out: {arguments}");
                return null;
            }

            var stdout = await stdoutTask;
            if (process.ExitCode != 0)
            {
                Logger.Log($"ccusage failed ({process.ExitCode}): {arguments}: {(await stderrTask).Trim()}");
                return null;
            }

            return stdout;
        }
        catch (Exception ex)
        {
            Logger.Log($"ccusage launch failed: {arguments}: {ex.Message}");
            return null;
        }
    }

    private static string? ResolveCcusagePath()
    {
        var bundled = Path.Combine(AppContext.BaseDirectory, "Tools", "ccusage.exe");
        return File.Exists(bundled) ? bundled : null;
    }
}

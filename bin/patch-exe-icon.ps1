# dsh-gpt-icon deferred EXE icon patcher.
#
# Replaces the RT_ICON / RT_GROUP_ICON resources of DSH Desktop.exe with the
# bundled multi-size blue-knot ICO. Because the plugin schedules this while the
# app is still running, the script:
#   1. backs up the current exe,
#   2. builds a patched copy under <DataDir>\pending,
#   3. waits until every "DSH Desktop" process has exited (user quits normally;
#      nothing is killed),
#   4. swaps the patched copy in, refreshes the shell icon cache and records
#      the patched hash in <DataDir>\exe-state.json.
# If the exe changes while waiting (another update), it re-patches from the
# new exe. It never relaunches the app.
param(
  [Parameter(Mandatory = $true)][string]$Exe,
  [Parameter(Mandatory = $true)][string]$Ico,
  [Parameter(Mandatory = $true)][string]$DataDir
)
$ErrorActionPreference = 'Stop'

$logPath = Join-Path $DataDir 'gpt-icon.log'
function Log([string]$Message) {
  try {
    Add-Content -LiteralPath $logPath -Value ("[{0}] [dsh-gpt-icon/exe] {1}" -f (Get-Date -Format o), $Message)
  } catch { }
}

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $DataDir 'pending') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $DataDir 'backup\exe') | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

public static class PeIconResource {
    private const uint LOAD_LIBRARY_AS_DATAFILE = 0x00000002;
    private static readonly IntPtr RT_ICON = new IntPtr(3);
    private static readonly IntPtr RT_GROUP_ICON = new IntPtr(14);

    private delegate bool EnumResNameProc(IntPtr module, IntPtr type, IntPtr name, IntPtr param);
    private delegate bool EnumResLangProc(IntPtr module, IntPtr type, IntPtr name, ushort language, IntPtr param);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryEx(string fileName, IntPtr file, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeLibrary(IntPtr module);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool EnumResourceNames(IntPtr module, IntPtr type, EnumResNameProc callback, IntPtr param);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool EnumResourceLanguages(IntPtr module, IntPtr type, IntPtr name, EnumResLangProc callback, IntPtr param);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr BeginUpdateResource(string fileName, bool deleteExistingResources);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool UpdateResource(IntPtr update, IntPtr type, IntPtr name, ushort language, byte[] data, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool EndUpdateResource(IntPtr update, bool discard);

    private sealed class ResourceKey {
        public bool IsId;
        public ushort Id;
        public string Name;
        public readonly List<ushort> Languages = new List<ushort>();
        public string Display { get { return IsId ? "#" + Id : Name; } }
    }

    private sealed class IconFrame {
        public byte Width;
        public byte Height;
        public byte ColorCount;
        public byte Reserved;
        public ushort Planes;
        public ushort BitCount;
        public byte[] Data;
    }

    private static bool IsIntegerResource(IntPtr value) {
        return ((ulong)value.ToInt64() >> 16) == 0;
    }

    private static IntPtr AllocateName(ResourceKey key, out bool mustFree) {
        if (key.IsId) {
            mustFree = false;
            return new IntPtr(key.Id);
        }
        mustFree = true;
        return Marshal.StringToHGlobalUni(key.Name);
    }

    private static List<ResourceKey> EnumerateGroups(string executable) {
        IntPtr module = LoadLibraryEx(executable, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE);
        if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "LoadLibraryEx failed");
        var groups = new List<ResourceKey>();
        try {
            EnumResNameProc nameCallback = delegate(IntPtr currentModule, IntPtr type, IntPtr name, IntPtr param) {
                var key = new ResourceKey();
                if (IsIntegerResource(name)) {
                    key.IsId = true;
                    key.Id = unchecked((ushort)name.ToInt64());
                } else {
                    key.IsId = false;
                    key.Name = Marshal.PtrToStringUni(name);
                }
                EnumResLangProc languageCallback = delegate(IntPtr m, IntPtr t, IntPtr n, ushort language, IntPtr p) {
                    key.Languages.Add(language);
                    return true;
                };
                EnumResourceLanguages(currentModule, RT_GROUP_ICON, name, languageCallback, IntPtr.Zero);
                groups.Add(key);
                return true;
            };
            bool success = EnumResourceNames(module, RT_GROUP_ICON, nameCallback, IntPtr.Zero);
            int error = Marshal.GetLastWin32Error();
            if (!success && error != 1813 && error != 1814) throw new Win32Exception(error, "EnumResourceNames failed");
        } finally {
            FreeLibrary(module);
        }
        if (groups.Count == 0) {
            var fallback = new ResourceKey { IsId = true, Id = 1 };
            fallback.Languages.Add(1033);
            groups.Add(fallback);
        }
        foreach (var group in groups) if (group.Languages.Count == 0) group.Languages.Add(1033);
        return groups;
    }

    private static List<IconFrame> ReadIco(string icoPath) {
        byte[] bytes = File.ReadAllBytes(icoPath);
        using (var stream = new MemoryStream(bytes, false))
        using (var reader = new BinaryReader(stream)) {
            ushort reserved = reader.ReadUInt16();
            ushort type = reader.ReadUInt16();
            ushort count = reader.ReadUInt16();
            if (reserved != 0 || type != 1 || count == 0) throw new InvalidDataException("Invalid ICO header");
            var frames = new List<IconFrame>();
            for (int index = 0; index < count; index++) {
                var frame = new IconFrame();
                frame.Width = reader.ReadByte();
                frame.Height = reader.ReadByte();
                frame.ColorCount = reader.ReadByte();
                frame.Reserved = reader.ReadByte();
                frame.Planes = reader.ReadUInt16();
                frame.BitCount = reader.ReadUInt16();
                uint length = reader.ReadUInt32();
                uint offset = reader.ReadUInt32();
                long returnPosition = stream.Position;
                stream.Position = offset;
                frame.Data = reader.ReadBytes(checked((int)length));
                if (frame.Data.Length != length) throw new EndOfStreamException("Truncated ICO frame");
                stream.Position = returnPosition;
                frames.Add(frame);
            }
            return frames;
        }
    }

    private static byte[] BuildGroupData(List<IconFrame> frames, ushort firstResourceId) {
        using (var stream = new MemoryStream())
        using (var writer = new BinaryWriter(stream)) {
            writer.Write((ushort)0);
            writer.Write((ushort)1);
            writer.Write((ushort)frames.Count);
            for (int index = 0; index < frames.Count; index++) {
                IconFrame frame = frames[index];
                writer.Write(frame.Width);
                writer.Write(frame.Height);
                writer.Write(frame.ColorCount);
                writer.Write(frame.Reserved);
                writer.Write(frame.Planes);
                writer.Write(frame.BitCount);
                writer.Write((uint)frame.Data.Length);
                writer.Write((ushort)(firstResourceId + index));
            }
            return stream.ToArray();
        }
    }

    public static string Patch(string executable, string icoPath) {
        List<ResourceKey> groups = EnumerateGroups(executable);
        List<IconFrame> frames = ReadIco(icoPath);
        const ushort firstResourceId = 50000;
        byte[] groupData = BuildGroupData(frames, firstResourceId);
        IntPtr update = BeginUpdateResource(executable, false);
        if (update == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "BeginUpdateResource failed");
        bool committed = false;
        try {
            foreach (ResourceKey group in groups) {
                bool mustFree;
                IntPtr groupName = AllocateName(group, out mustFree);
                try {
                    foreach (ushort language in group.Languages.Distinct()) {
                        for (int index = 0; index < frames.Count; index++) {
                            IntPtr iconName = new IntPtr(firstResourceId + index);
                            byte[] data = frames[index].Data;
                            if (!UpdateResource(update, RT_ICON, iconName, language, data, (uint)data.Length))
                                throw new Win32Exception(Marshal.GetLastWin32Error(), "Updating RT_ICON failed");
                        }
                        if (!UpdateResource(update, RT_GROUP_ICON, groupName, language, groupData, (uint)groupData.Length))
                            throw new Win32Exception(Marshal.GetLastWin32Error(), "Updating RT_GROUP_ICON failed");
                    }
                } finally {
                    if (mustFree) Marshal.FreeHGlobal(groupName);
                }
            }
            if (!EndUpdateResource(update, false)) throw new Win32Exception(Marshal.GetLastWin32Error(), "EndUpdateResource failed");
            committed = true;
        } finally {
            if (!committed) EndUpdateResource(update, true);
        }
        return string.Join(", ", groups.Select(g => g.Display + " [" + string.Join(",", g.Languages) + "]"));
    }
}
'@

function Get-ExeHash([string]$Path) {
  (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Test-FileWritable([string]$Path) {
  try {
    $stream = [System.IO.File]::Open($Path, 'Open', 'ReadWrite', 'None')
    $stream.Dispose()
    return $true
  } catch {
    return $false
  }
}

function Refresh-IconCache {
  # Best-effort: clear the classic icon cache and nudge the shell. The cache
  # files may be locked while Explorer runs; the SHChangeNotify broadcast plus
  # the next reboot/relogin make the new icon appear regardless.
  try {
    $targets = @(
      (Join-Path $env:LOCALAPPDATA 'IconCache.db')
    ) + (Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer') -Filter 'iconcache_*.db' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    foreach ($target in $targets) {
      if ($target -and (Test-Path -LiteralPath $target)) {
        Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
      }
    }
  } catch { }
  try {
    Add-Type -Namespace Native -Name Shell -MemberDefinition @'
[DllImport("shell32.dll")]
public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);
'@
    [Native.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)  # SHCNE_ASSOCCHANGED
  } catch { }
}

$taskName = 'DSH GptIcon ExePatch'
$lockPath = Join-Path $DataDir 'exe-watcher.lock'

# Single-instance guard: the plugin may re-arm the task on every boot while a
# previous patch run is still waiting for the app to exit. Task Scheduler's
# "ignore new instance" policy already deduplicates, the mutex is belt and
# suspenders (also covers manual invocations).
$mutex = New-Object System.Threading.Mutex($false, 'Local\DSHGptIconExePatch')
if (-not $mutex.WaitOne(0)) {
  Log 'another patch instance is already running; exiting'
  exit 0
}

try {
  if (-not (Test-Path -LiteralPath $Exe)) { throw "exe not found: $Exe" }
  if (-not (Test-Path -LiteralPath $Ico)) { throw "ico not found: $Ico" }

  $pendingPath = Join-Path $DataDir 'pending\DSH Desktop.exe'
  $statePath = Join-Path $DataDir 'exe-state.json'
  $previewPath = Join-Path $DataDir 'exe-icon-preview.png'
  $maxRounds = 10
  $done = $false

  for ($round = 1; $round -le $maxRounds -and -not $done; $round++) {
    $currentHash = Get-ExeHash $Exe

    # 1. Back up this exact exe once.
    $backupPath = Join-Path $DataDir ("backup\exe\DSH Desktop.exe.$currentHash.backup")
    if (-not (Test-Path -LiteralPath $backupPath)) {
      Copy-Item -LiteralPath $Exe -Destination $backupPath
      Log "backed up stock exe ($($currentHash.Substring(0, 12))...)"
    }

    # 2. Build the patched copy from the CURRENT exe.
    Copy-Item -LiteralPath $Exe -Destination $pendingPath -Force
    $groups = [PeIconResource]::Patch($pendingPath, $Ico)
    $patchedHash = Get-ExeHash $pendingPath
    if ($patchedHash -eq $currentHash) {
      # Re-patching an exe that already carries our icon resources rebuilds
      # byte-identical resources: nothing to swap, just record state.
      $state = [ordered]@{ exeSha256 = $currentHash; patchedAt = (Get-Date -Format o); groups = $groups }
      [System.IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
      Log ("exe already carries the knot icon (sha256 {0}); state recorded" -f $currentHash)
      $done = $true
      break
    }
    Log "patched copy built (groups: $groups)"

    try {
      Add-Type -AssemblyName System.Drawing
      $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($pendingPath)
      if ($icon) {
        $bitmap = $icon.ToBitmap()
        $bitmap.Save($previewPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose(); $icon.Dispose()
      }
    } catch { Log "preview extraction skipped: $_" }

    # 3. Wait for the app to exit on its own.
    $announced = $false
    while ($true) {
      $processes = Get-Process -Name 'DSH Desktop' -ErrorAction SilentlyContinue
      if (-not $processes) { break }
      if (-not $announced) {
        $announced = $true
        Log ("waiting for {0} DSH Desktop process(es) to exit (PID: {1})" -f $processes.Count, (($processes | Select-Object -First 5 -ExpandProperty Id) -join ', '))
      }
      Start-Sleep -Seconds 5
    }
    if (-not (Test-FileWritable $Exe)) {
      Log 'exe still locked after processes exited; retrying'
      Start-Sleep -Seconds 10
      if (-not (Test-FileWritable $Exe)) { throw 'exe remained locked; giving up this round' }
    }

    # 4. If the exe changed while we waited, loop and re-patch from the new one.
    if ((Get-ExeHash $Exe) -ne $currentHash) {
      Log 'exe changed while waiting (update?); re-patching from the new exe'
      continue
    }

    # 5. Swap in the patched exe and record state.
    Move-Item -LiteralPath $pendingPath -Destination $Exe -Force
    $finalHash = Get-ExeHash $Exe
    $state = [ordered]@{ exeSha256 = $finalHash; patchedAt = (Get-Date -Format o); groups = $groups }
    [System.IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    Refresh-IconCache
    Log ("exe icon replaced OK (sha256 {0}); icon cache refreshed" -f $finalHash)
    $done = $true
  }

  if (-not $done) { throw 'exceeded re-patch rounds' }
} catch {
  Log ("exe patch failed: " + $_.Exception.Message)
} finally {
  Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
  try { schtasks /Delete /F /TN $taskName | Out-Null } catch { }
  try { $mutex.ReleaseMutex() } catch { }
  $mutex.Dispose()
}

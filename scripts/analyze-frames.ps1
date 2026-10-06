<#
.SYNOPSIS
  Per-frame luma / motion metrics for a rendered image sequence.

.DESCRIPTION
  Writes frame,luma,mean_abs_diff,changed_pixels,peak_diff for every frame in -Dir.
  Frames are ordered by the numeric suffix of their filename, so mixed zero padding
  and gaps in the sequence are handled without corrupting the motion columns.

.EXAMPLE
  powershell -File scripts\analyze-frames.ps1 -Dir qa\r01\motion -OutCsv qa\r01\motion.csv
#>
param(
  [Parameter(Mandatory = $true)][string]$Dir,
  [Parameter(Mandatory = $true)][string]$OutCsv,
  [string]$Filter = "element-*.png"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$source = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class FrameScan
{
    public static void Run(string dir, string filter, string outCsv)
    {
        double[] prev = null;
        int last = -1;
        var sb = new StringBuilder();
        sb.AppendLine("frame,luma,mean_abs_diff,changed_pixels,peak_diff");

        string[] files = Directory.GetFiles(dir, filter);
        var order = new List<int>();
        var byIndex = new Dictionary<int, string>();
        foreach (string f in files)
        {
            string stem = Path.GetFileNameWithoutExtension(f);
            int cut = stem.LastIndexOf('-');
            if (cut < 0) continue;
            int idx;
            if (!int.TryParse(stem.Substring(cut + 1), NumberStyles.Integer,
                              CultureInfo.InvariantCulture, out idx)) continue;
            if (byIndex.ContainsKey(idx)) continue;
            byIndex[idx] = f;
            order.Add(idx);
        }
        order.Sort();

        foreach (int i in order)
        {
            double sum = 0.0, dsum = 0.0, dpeak = 0.0;
            long changed = 0;
            double[] cur;
            using (Bitmap bmp = new Bitmap(byIndex[i]))
            {
                int w = bmp.Width, h = bmp.Height;
                BitmapData data = bmp.LockBits(new Rectangle(0, 0, w, h),
                                               ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
                int stride = data.Stride;
                byte[] buf = new byte[stride * h];
                Marshal.Copy(data.Scan0, buf, 0, buf.Length);
                bmp.UnlockBits(data);

                cur = new double[w * h];
                for (int y = 0; y < h; y++)
                {
                    int off = y * stride;
                    int row = y * w;
                    for (int x = 0; x < w; x++)
                    {
                        int p = off + x * 3;
                        double lum = 0.114 * buf[p] + 0.587 * buf[p + 1] + 0.299 * buf[p + 2];
                        cur[row + x] = lum;
                        sum += lum;
                        if (prev != null)
                        {
                            double d = Math.Abs(lum - prev[row + x]);
                            dsum += d;
                            if (d > dpeak) dpeak = d;
                            if (d > 3.0) changed++;
                        }
                    }
                }
            }

            long n = (long)cur.Length;
            // A gap in the sequence must not be reported as "no motion".
            bool gap = prev != null && i != last + 1;
            double mad = (prev == null || gap) ? 0.0 : dsum / n;
            double changedPct = (prev == null || gap) ? 0.0 : (100.0 * changed) / n;
            sb.Append(i).Append(',')
              .Append((sum / n).ToString("F4", CultureInfo.InvariantCulture)).Append(',')
              .Append(mad.ToString("F4", CultureInfo.InvariantCulture)).Append(',')
              .Append(changedPct.ToString("F3", CultureInfo.InvariantCulture)).Append(',')
              .Append(dpeak.ToString("F2", CultureInfo.InvariantCulture)).Append('\n');
            prev = cur;
            last = i;
        }
        File.WriteAllText(outCsv, sb.ToString());
    }
}
'@

Add-Type -TypeDefinition $source -ReferencedAssemblies 'System.Drawing'
[FrameScan]::Run((Resolve-Path -LiteralPath $Dir).Path, $Filter, $OutCsv)
Write-Output "wrote $OutCsv"

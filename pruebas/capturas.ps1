# Abre el programa en una ventana de consola de Windows para cada expediente
# y guarda una captura de esa ventana en docs/capturas/<expediente>.png.
# Uso: pwsh pruebas/capturas.ps1 exe64\rcyr.exe
param([string]$Exe = "exe64\rcyr.exe")

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Ventana {
    public delegate bool Visitar(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(Visitar f, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    public static IntPtr Buscar(string titulo) {
        IntPtr encontrada = IntPtr.Zero;
        EnumWindows((h, l) => {
            if (!IsWindowVisible(h)) return true;
            var texto = new StringBuilder(512);
            GetWindowText(h, texto, 512);
            if (texto.ToString().Contains(titulo)) { encontrada = h; return false; }
            return true;
        }, IntPtr.Zero);
        return encontrada;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int alto, bool repintar);
}
"@

$exe = (Resolve-Path $Exe).Path
$destino = Join-Path (Get-Location) 'docs\capturas'
New-Item -ItemType Directory -Force $destino | Out-Null

function Capturar([string]$Peticion, [string]$Nombre, [int]$Lineas) {
    $orden = "title RCyR - prestamos & mode con cols=100 lines=$Lineas & prompt `$G & echo $Peticion| `"$exe`""
    $p = Start-Process cmd.exe -ArgumentList '/k', $orden -PassThru
    $h = [IntPtr]::Zero
    # La ventana puede ser de conhost o de Windows Terminal: se busca entre
    # todas las ventanas por el título que le pone el propio cmd.
    for ($i = 0; $i -lt 40 -and $h -eq [IntPtr]::Zero; $i++) {
        Start-Sleep -Milliseconds 250
        $h = [Ventana]::Buscar('RCyR - prestamos')
    }
    Start-Sleep -Seconds 2
    if ($h -ne [IntPtr]::Zero) {
        [Ventana]::MoveWindow($h, 0, 0, 980, 600, $true) | Out-Null
        [Ventana]::SetForegroundWindow($h) | Out-Null
        Start-Sleep -Milliseconds 800
        $r = New-Object Ventana+RECT
        [Ventana]::GetWindowRect($h, [ref]$r) | Out-Null
        $x = $r.Left; $y = $r.Top; $w = $r.Right - $r.Left; $alto = $r.Bottom - $r.Top
    } else {
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $x = 0; $y = 0; $w = $b.Width; $alto = $b.Height
    }
    $bmp = New-Object System.Drawing.Bitmap $w, $alto
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($x, $y, 0, 0, $bmp.Size)
    $archivo = Join-Path $destino "$Nombre.png"
    $bmp.Save($archivo, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Get-Process rcyr -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    "Captura: $archivo ($w x $alto, ventana: $($h -ne [IntPtr]::Zero))"
}

$expedientes = Get-Content (Join-Path $PSScriptRoot 'esperado.txt') |
    Where-Object { $_ -match '^EXP-' } | ForEach-Object { ($_ -split '\s+')[0] }
foreach ($e in $expedientes) { Capturar $e $e 22 }
Capturar 'EXP-999' 'expediente-inexistente' 10

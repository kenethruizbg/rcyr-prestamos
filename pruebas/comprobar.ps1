# Compara la salida del programa con pruebas/esperado.txt.
# Para cada expediente comprueba la decisión y las reglas que la motivan.
# Uso: pwsh pruebas/comprobar.ps1 salida.txt
param([string]$Salida = "salida.txt")

$obtenido = @{}
$actual = $null
$enDecision = $false
foreach ($linea in Get-Content $Salida -Encoding utf8) {
    if ($linea -match '^=== (EXP-\d+)') {
        $actual = $Matches[1]
        $enDecision = $false
    } elseif ($actual -and $linea -match '^DECISI.N: (\w+)') {
        $obtenido[$actual] = @{ Decision = $Matches[1]; Reglas = @() }
        $enDecision = $true
    } elseif ($enDecision -and $linea -match '^  - ([DEV]\d):') {
        $obtenido[$actual].Reglas += $Matches[1]
    } elseif ($enDecision -and $linea -match '^  - cumple todos') {
        $obtenido[$actual].Reglas += 'F4'
    } else {
        $enDecision = $false
    }
}

$fallos = 0
$total = 0
"{0,-8} {1,-17} {2,-10} {3,-17} {4,-10} {5}" -f 'Exp.', 'Esperado', 'Reglas', 'Obtenido', 'Reglas', 'OK'
foreach ($linea in Get-Content (Join-Path $PSScriptRoot 'esperado.txt')) {
    if ($linea -match '^\s*(#|$)') { continue }
    $partes = $linea -split '\s+'
    $exp = $partes[0]
    $decision = $partes[1]
    $reglas = ($partes[2..($partes.Length - 1)] | Sort-Object) -join ' '
    $total++
    $o = $obtenido[$exp]
    $oDecision = if ($o) { $o.Decision } else { '(no aparece)' }
    $oReglas = if ($o) { ($o.Reglas | Sort-Object) -join ' ' } else { '' }
    $ok = ($oDecision -eq $decision) -and ($oReglas -eq $reglas)
    if (-not $ok) { $fallos++ }
    "{0,-8} {1,-17} {2,-10} {3,-17} {4,-10} {5}" -f $exp, $decision, $reglas, $oDecision, $oReglas, $(if ($ok) { 'sí' } else { 'NO' })
}

""
"Casos correctos: $($total - $fallos) de $total"
if ($fallos -gt 0) { exit 1 }

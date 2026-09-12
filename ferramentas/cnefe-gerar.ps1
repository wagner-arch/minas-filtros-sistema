# Gera a base de geolocalização do sistema (pasta geo/) a partir dos arquivos do
# IBGE — Cadastro Nacional de Endereços para Fins Estatísticos (CNEFE), Censo 2022.
#
# Entrada: dados-ibge/zip/<codigo>_<CIDADE>.zip (um por município) e a lista
#          dados-ibge/cidades.csv (colunas uf,id,nome,km,url,bytes).
# Saída:   geo/indice.json e geo/<codigo>.txt — ou geo/<codigo>-<letra>.txt quando a
#          cidade é grande (letra = inicial da última palavra do nome da rua).
#
# Formato de cada linha:  tipo|titulo|nome|localidade|cep|num,lat,lng;num,dlat,dlng;...
#   texto em minúsculas sem acento (só a-z, 0-9 e espaço); coordenadas em inteiros de
#   1e-5 grau (~1 m); a primeira do logradouro é absoluta, as seguintes são diferença
#   para a anterior, em ordem crescente de número. Mesmo número repetido (apartamentos)
#   vira a média. Só entram endereços com número e coordenada do próprio endereço
#   (NV_GEO_COORD 1, 2 ou 3 — 4 a 6 são face de quadra, localidade e setor).
param(
  [string]$Raiz = (Split-Path -Parent $PSScriptRoot),
  [string]$SoCodigo = "",
  [int]$LimiteBytes = 400000
)
$ErrorActionPreference = 'Stop'

Add-Type -ReferencedAssemblies System.IO.Compression, System.IO.Compression.FileSystem, System.Core -TypeDefinition @"
using System;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
public static class Cnefe {
  static readonly Regex NaoAlfa = new Regex("[^a-z0-9]+", RegexOptions.Compiled);
  public static string Norm(string s){
    if (s == null) return "";
    s = s.ToLowerInvariant().Normalize(NormalizationForm.FormD);
    var sb = new StringBuilder(s.Length);
    foreach (char ch in s) if (CharUnicodeInfo.GetUnicodeCategory(ch) != UnicodeCategory.NonSpacingMark) sb.Append(ch);
    return NaoAlfa.Replace(sb.ToString(), " ").Trim();
  }
  class Ponto { public double La, Lo; public int K; }
  public static string Processar(string zipPath, string outDir, string id, int limiteBytes){
    var grupos = new Dictionary<string, SortedDictionary<int, Ponto>>();
    using (var z = ZipFile.OpenRead(zipPath)) {
      var entrada = z.Entries.First(x => x.FullName.EndsWith(".csv", StringComparison.OrdinalIgnoreCase));
      using (var r = new StreamReader(entrada.Open(), Encoding.UTF8)) {
        r.ReadLine();
        string l;
        while ((l = r.ReadLine()) != null) {
          var c = l.Split(';');
          if (c.Length < 28) continue;
          int nv; if (!int.TryParse(c[27], out nv) || nv < 1 || nv > 3) continue;
          int n; if (!int.TryParse(c[13], out n) || n <= 0) continue;
          double la, lo;
          if (!double.TryParse(c[25], NumberStyles.Float, CultureInfo.InvariantCulture, out la)) continue;
          if (!double.TryParse(c[26], NumberStyles.Float, CultureInfo.InvariantCulture, out lo)) continue;
          string nome = Norm(c[12]); if (nome.Length == 0) continue;
          string cep = Regex.Replace(c[8], "[^0-9]", "");
          string chave = Norm(c[10]) + "|" + Norm(c[11]) + "|" + nome + "|" + Norm(c[9]) + "|" + cep;
          SortedDictionary<int, Ponto> g;
          if (!grupos.TryGetValue(chave, out g)) { g = new SortedDictionary<int, Ponto>(); grupos[chave] = g; }
          Ponto p; if (!g.TryGetValue(n, out p)) { p = new Ponto(); g[n] = p; }
          p.La += la; p.Lo += lo; p.K++;
        }
      }
    }
    var linhas = new List<KeyValuePair<string, string>>();
    long total = 0; int pares = 0;
    foreach (var kv in grupos.OrderBy(x => x.Key, StringComparer.Ordinal)) {
      var sb = new StringBuilder(kv.Key); sb.Append('|');
      long pla = 0, plo = 0; bool primeiro = true;
      foreach (var e in kv.Value) {
        long la = (long)Math.Round(e.Value.La / e.Value.K * 1e5), lo = (long)Math.Round(e.Value.Lo / e.Value.K * 1e5);
        if (!primeiro) sb.Append(';');
        sb.Append(e.Key).Append(',');
        if (primeiro) sb.Append(la).Append(',').Append(lo);
        else sb.Append(la - pla).Append(',').Append(lo - plo);
        pla = la; plo = lo; primeiro = false; pares++;
      }
      string[] ws = kv.Key.Split('|')[2].Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
      string ult = ws.Length > 0 ? ws[ws.Length - 1] : "";
      char b0 = ult.Length > 0 ? ult[0] : '0';
      string balde = (b0 >= 'a' && b0 <= 'z') ? b0.ToString() : "0";
      string linha = sb.ToString();
      total += Encoding.UTF8.GetByteCount(linha) + 1;
      linhas.Add(new KeyValuePair<string, string>(balde, linha));
    }
    bool partes = total > limiteBytes;
    var utf8 = new UTF8Encoding(false);
    foreach (var f in Directory.GetFiles(outDir, id + "*.txt")) {
      string nomeArq = Path.GetFileName(f);
      if (nomeArq == id + ".txt" || nomeArq.StartsWith(id + "-")) File.Delete(f);
    }
    if (!partes) {
      File.WriteAllText(Path.Combine(outDir, id + ".txt"), string.Join("\n", linhas.Select(x => x.Value)) + "\n", utf8);
    } else {
      foreach (var gb in linhas.GroupBy(x => x.Key))
        File.WriteAllText(Path.Combine(outDir, id + "-" + gb.Key + ".txt"), string.Join("\n", gb.Select(x => x.Value)) + "\n", utf8);
    }
    return (partes ? "1" : "0") + ";" + grupos.Count + ";" + pares + ";" + total;
  }
}
"@

$zipDir = Join-Path $Raiz 'dados-ibge\zip'
$geoDir = Join-Path $Raiz 'geo'
New-Item -ItemType Directory -Force $geoDir | Out-Null
$cidades = Import-Csv (Join-Path $Raiz 'dados-ibge\cidades.csv')
if ($SoCodigo) { $cidades = $cidades | Where-Object { $_.id -eq $SoCodigo } }

$resumo = @()
$inicio = Get-Date
foreach ($c in $cidades) {
  $zip = Join-Path $zipDir ([IO.Path]::GetFileName($c.url))
  if (-not (Test-Path $zip)) { Write-Warning "falta $zip"; continue }
  $r = [Cnefe]::Processar($zip, $geoDir, $c.id, $LimiteBytes).Split(';')
  $resumo += [pscustomobject]@{ uf = $c.uf; id = $c.id; nome = $c.nome; chave = $c.uf + '|' + [Cnefe]::Norm($c.nome); partes = [int]$r[0]; logradouros = [int]$r[1]; enderecos = [int]$r[2]; bytes = [int64]$r[3] }
}

if (-not $SoCodigo) {
  # índice: "UF|cidade" -> [código, partes]
  $sb = New-Object Text.StringBuilder
  [void]$sb.Append('{"fonte":"IBGE - Cadastro Nacional de Enderecos para Fins Estatisticos (CNEFE), Censo 2022","gerado":"')
  [void]$sb.Append((Get-Date -Format 'yyyy-MM-dd')).Append('","cidades":{')
  $primeiro = $true
  foreach ($x in ($resumo | Sort-Object chave)) {
    if (-not $primeiro) { [void]$sb.Append(',') }
    [void]$sb.Append('"').Append($x.chave).Append('":[').Append($x.id).Append(',').Append($x.partes).Append(']')
    $primeiro = $false
  }
  [void]$sb.Append('}}')
  [IO.File]::WriteAllText((Join-Path $geoDir 'indice.json'), $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
}

$resumo | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $Raiz 'dados-ibge\resumo-geo.csv')
$tot = ($resumo | Measure-Object bytes -Sum).Sum
"cidades: $($resumo.Count)  logradouros: $(($resumo | Measure-Object logradouros -Sum).Sum)  enderecos: $(($resumo | Measure-Object enderecos -Sum).Sum)"
"tamanho da pasta geo: $([math]::Round($tot/1MB,1)) MB  divididas: $(@($resumo | Where-Object partes -eq 1).Count)  tempo: $([math]::Round(((Get-Date)-$inicio).TotalSeconds)) s"

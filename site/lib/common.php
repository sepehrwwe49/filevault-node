<?php
const DATA_DIR = '/var/www/data';
const UP_DIR   = DATA_DIR . '/uploads';
const META_DIR = DATA_DIR . '/meta';

function cfg(string $k, string $d = ''): string {
    $v = getenv($k);
    return ($v === false || $v === '') ? $d : $v;
}
function site_name(): string   { return cfg('SITE_NAME', 'FileVault'); }
function max_mb(): int         { return (int) cfg('MAX_UPLOAD_MB', '50'); }
function retention(): int      { return (int) cfg('RETENTION_DAYS', '7'); }

const BLOCKED_EXT = [
  'php','php3','php4','php5','php7','phtml','phar','sh','bash','bat','cmd','com',
  'exe','msi','dll','scr','cgi','pl','py','jar','vbs','js','jsp','asp','aspx',
  'apk','ps1','so','deb','rpm','htaccess'
];

function human(int $b): string {
    $u = ['B','KB','MB','GB']; $i = 0;
    while ($b >= 1024 && $i < 3) { $b /= 1024; $i++; }
    return round($b, $b < 10 && $i > 0 ? 1 : 0) . ' ' . $u[$i];
}
function token(int $n = 10): string {
    return substr(rtrim(strtr(base64_encode(random_bytes(16)), '+/', 'ab'), '='), 0, $n);
}
function safe_name(string $n): string {
    $n = basename(str_replace('\\', '/', $n));
    $n = preg_replace('/[^A-Za-z0-9._ -]/', '_', $n);
    $n = ltrim($n, '.');
    return $n === '' ? 'file' : substr($n, 0, 120);
}
function ext_of(string $n): string {
    return strtolower(pathinfo($n, PATHINFO_EXTENSION));
}
function meta_path(string $id): string { return META_DIR . '/' . $id . '.json'; }

function load_meta(string $id): ?array {
    if (!preg_match('/^[A-Za-z0-9]{6,32}$/', $id)) return null;
    $p = meta_path($id);
    if (!is_file($p)) return null;
    $m = json_decode((string) file_get_contents($p), true);
    return is_array($m) ? $m : null;
}
function base_url(): string {
    $h = $_SERVER['HTTP_HOST'] ?? 'localhost';
    $s = (($_SERVER['HTTPS'] ?? '') === 'on' || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https') ? 'https' : 'https';
    return $s . '://' . $h;
}
function h(?string $s): string { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); }

function layout_head(string $title, string $desc): void {
    $n = h(site_name());
    echo "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">";
    echo "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">";
    echo "<title>" . h($title) . " &middot; {$n}</title>";
    echo "<meta name=\"description\" content=\"" . h($desc) . "\">";
    echo "<link rel=\"canonical\" href=\"" . h(base_url() . ($_SERVER['REQUEST_URI'] ?? '/')) . "\">";
    echo "<link rel=\"stylesheet\" href=\"/assets/style.css\">";
    echo "<link rel=\"icon\" href=\"/assets/favicon.svg\" type=\"image/svg+xml\">";
    echo "</head><body><header class=\"nav\"><div class=\"wrap\">";
    echo "<a class=\"brand\" href=\"/\"><span class=\"logo\"></span>{$n}</a>";
    echo "<nav><a href=\"/\">Upload</a><a href=\"/about.php\">About</a><a href=\"/faq.php\">FAQ</a><a href=\"/terms.php\">Terms</a></nav>";
    echo "</div></header><main class=\"wrap\">";
}
function layout_foot(): void {
    $y = date('Y'); $n = h(site_name()); $r = retention();
    echo "</main><footer class=\"foot\"><div class=\"wrap\">";
    echo "<p>&copy; {$y} {$n}. Free temporary file hosting &mdash; files are removed automatically after {$r} days.</p>";
    echo "<p><a href=\"/terms.php\">Terms of Service</a> &middot; <a href=\"/privacy.php\">Privacy Policy</a> &middot; <a href=\"/faq.php\">FAQ</a> &middot; <a href=\"/sitemap.xml\">Sitemap</a></p>";
    echo "</div></footer></body></html>";
}

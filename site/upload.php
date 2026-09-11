<?php
require __DIR__.'/lib/common.php';
header('Content-Type: application/json; charset=utf-8');

function fail(string $m, int $c = 400): never {
    http_response_code($c);
    echo json_encode(['ok' => false, 'error' => $m]);
    exit;
}
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') fail('Method not allowed', 405);
if (!isset($_FILES['file'])) fail('No file was received.');

$f = $_FILES['file'];
if ($f['error'] === UPLOAD_ERR_INI_SIZE || $f['error'] === UPLOAD_ERR_FORM_SIZE) fail('File is too large.', 413);
if ($f['error'] !== UPLOAD_ERR_OK) fail('Upload failed, please try again.');

$limit = max_mb() * 1024 * 1024;
if ($f['size'] <= 0) fail('The file is empty.');
if ($f['size'] > $limit) fail('Maximum file size is ' . max_mb() . ' MB.', 413);

$name = safe_name($f['name']);
$ext  = ext_of($name);
if ($ext === '' || in_array($ext, BLOCKED_EXT, true)) fail('This file type is not accepted.', 415);

$id  = token(10);
$dir = UP_DIR . '/' . $id;
if (!is_dir($dir) && !mkdir($dir, 0775, true)) fail('Storage error.', 500);

$dest = $dir . '/' . $name;
if (!move_uploaded_file($f['tmp_name'], $dest)) fail('Storage error.', 500);
@chmod($dest, 0644);

if (!is_dir(META_DIR)) @mkdir(META_DIR, 0775, true);
$meta = [
    'id'   => $id,
    'name' => $name,
    'size' => (int) $f['size'],
    'type' => mime_content_type($dest) ?: 'application/octet-stream',
    'time' => time(),
    'exp'  => time() + retention() * 86400,
];
file_put_contents(meta_path($id), json_encode($meta));

echo json_encode([
    'ok'      => true,
    'url'     => base_url() . '/d/' . $id,
    'expires' => gmdate('Y-m-d H:i', $meta['exp']) . ' UTC',
]);

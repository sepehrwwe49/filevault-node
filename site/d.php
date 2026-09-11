<?php
require __DIR__.'/lib/common.php';
$id = $_GET['id'] ?? '';
$m  = load_meta($id);
if (!$m) { http_response_code(404); require __DIR__.'/404.php'; exit; }

$path = UP_DIR . '/' . $m['id'] . '/' . $m['name'];
if (!is_file($path) || time() > (int) $m['exp']) { http_response_code(404); require __DIR__.'/404.php'; exit; }

if (isset($_GET['dl'])) {
    header('Content-Type: ' . $m['type']);
    header('Content-Length: ' . filesize($path));
    header('Content-Disposition: attachment; filename="' . $m['name'] . '"');
    header('X-Accel-Redirect: /f/' . rawurlencode($m['id']) . '/' . rawurlencode($m['name']));
    exit;
}

layout_head('Download ' . $m['name'], 'Download ' . $m['name'] . ' (' . human((int)$m['size']) . ').');
?>
<section class="card file">
  <h1><?= h($m['name']) ?></h1>
  <ul class="meta">
    <li><span>Size</span><b><?= human((int)$m['size']) ?></b></li>
    <li><span>Type</span><b><?= h($m['type']) ?></b></li>
    <li><span>Uploaded</span><b><?= gmdate('Y-m-d H:i', (int)$m['time']) ?> UTC</b></li>
    <li><span>Expires</span><b><?= gmdate('Y-m-d H:i', (int)$m['exp']) ?> UTC</b></li>
  </ul>
  <a class="btn" href="/d/<?= h($m['id']) ?>?dl=1">Download file</a>
  <p class="muted">This link stops working automatically once the file expires.</p>
</section>
<?php layout_foot();

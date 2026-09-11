<?php require __DIR__.'/lib/common.php';
layout_head('Terms of Service', 'Terms of Service for '.site_name().'.');
?>
<section class="card prose">
  <h1>Terms of Service</h1>
  <p class="muted">Last updated: <?= date('F j, Y', strtotime('-2 months')) ?></p>
  <h2>1. Acceptance</h2>
  <p>By uploading a file to <?= h(site_name()) ?> you agree to these terms. If you do not agree with them, please do not use the service.</p>
  <h2>2. The service</h2>
  <p><?= h(site_name()) ?> provides free, temporary storage for files up to <?= max_mb() ?> MB. Files are automatically and permanently deleted <?= retention() ?> days after upload. The service is provided free of charge and without any availability guarantee.</p>
  <h2>3. Acceptable use</h2>
  <p>You may not upload material that you do not have the right to distribute, that infringes copyright or trademarks, that contains malware, or that is illegal in your jurisdiction or in the jurisdiction where our servers are located. Automated bulk uploading and any attempt to use the service as permanent storage or as a content delivery backend are not permitted.</p>
  <h2>4. Removal</h2>
  <p>We may remove any file at any time, with or without notice, if we believe it violates these terms or if we receive a credible complaint about it.</p>
  <h2>5. No warranty</h2>
  <p>The service is provided &ldquo;as is&rdquo;. We make no warranty that files will remain available for the full retention period, and we are not liable for any loss of data. Keep your own copy of anything you care about.</p>
  <h2>6. Changes</h2>
  <p>These terms may be updated from time to time. The current version is always published on this page.</p>
  <h2>7. Contact</h2>
  <p>Abuse reports and takedown requests: <span class="mail">abuse [at] this domain</span>.</p>
</section>
<?php layout_foot();

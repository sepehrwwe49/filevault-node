<?php require __DIR__.'/lib/common.php';
layout_head('Privacy Policy', 'Privacy Policy for '.site_name().'.');
?>
<section class="card prose">
  <h1>Privacy Policy</h1>
  <p class="muted">Last updated: <?= date('F j, Y', strtotime('-2 months')) ?></p>
  <h2>What we collect</h2>
  <p>We collect the file you upload, its original file name, its size and the time of the upload. We do not ask for, and do not store, any personal account information, because the service has no accounts.</p>
  <h2>Cookies and analytics</h2>
  <p>This site sets no cookies and runs no third-party analytics or advertising scripts.</p>
  <h2>Retention</h2>
  <p>Uploaded files and their metadata are deleted permanently <?= retention() ?> days after upload by an automated job. Deleted files are not archived or backed up.</p>
  <h2>Sharing</h2>
  <p>We do not sell or share uploaded content with third parties. Content may be disclosed only where we are legally required to do so.</p>
  <h2>Security</h2>
  <p>All traffic to this site is encrypted with TLS. Links are unguessable random identifiers, but anyone holding a link can download the file &mdash; treat a link as the key to the file.</p>
  <h2>Your choices</h2>
  <p>If you want a file removed before it expires, send us the link using the contact address in our <a href="/terms.php">Terms of Service</a>.</p>
</section>
<?php layout_foot();

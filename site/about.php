<?php require __DIR__.'/lib/common.php';
layout_head('About', 'About '.site_name().', a free temporary file hosting service.');
?>
<section class="card prose">
  <h1>About <?= h(site_name()) ?></h1>
  <p><?= h(site_name()) ?> is a small, free file hosting service built around one idea: sending a file to someone should not require an account, a subscription or a desktop client.</p>
  <p>You choose a file, we store it, and you get a short link you can share. After <?= retention() ?> days the file is deleted from our servers and the link stops working. There is nothing to cancel and nothing to clean up.</p>
  <h2>What we do not do</h2>
  <ul>
    <li>We do not ask for an e-mail address or a password.</li>
    <li>We do not show advertising or third-party trackers.</li>
    <li>We do not keep files longer than the retention period.</li>
  </ul>
  <h2>Limits</h2>
  <p>Each file may be up to <?= max_mb() ?> MB. Executable formats and server-side scripts are rejected, because they are almost never shared for a legitimate reason and they attract abuse.</p>
  <h2>Contact</h2>
  <p>For abuse reports or takedown requests, use the contact address listed in our <a href="/terms.php">Terms of Service</a>.</p>
</section>
<?php layout_foot();

<?php require __DIR__.'/lib/common.php';
layout_head('FAQ', 'Frequently asked questions about '.site_name().'.');
?>
<section class="card prose">
  <h1>Frequently asked questions</h1>
  <h2>How long are files kept?</h2>
  <p>Exactly <?= retention() ?> days from the moment the upload finishes. A background job removes expired files every hour.</p>
  <h2>How large can a file be?</h2>
  <p>Up to <?= max_mb() ?> MB per file. Larger files are rejected before they are written to disk.</p>
  <h2>Can I delete a file earlier?</h2>
  <p>Not from the web interface. If you need a file removed immediately, contact us with the link and we will delete it.</p>
  <h2>Which file types are blocked?</h2>
  <p>Executables and server-side scripts &mdash; for example <code>.exe</code>, <code>.msi</code>, <code>.apk</code>, <code>.sh</code>, <code>.bat</code>, <code>.php</code> and similar formats.</p>
  <h2>Is there an API?</h2>
  <p>You can POST a multipart form with a <code>file</code> field to <code>/upload.php</code> and you will get a JSON response containing the public link.</p>
  <h2>Do I need an account?</h2>
  <p>No. There is no registration and there never will be.</p>
</section>
<?php layout_foot();

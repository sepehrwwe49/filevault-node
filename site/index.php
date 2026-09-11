<?php require __DIR__.'/lib/common.php';
layout_head('Free File Hosting', 'Upload and share files up to '.max_mb().' MB for free. No registration. Links expire automatically after '.retention().' days.');
?>
<section class="hero">
  <h1>Share a file in one click</h1>
  <p class="lead">Drop a file below and get a clean direct link instantly. No account, no e-mail, no ads. Every upload is deleted automatically after <strong><?= retention() ?> days</strong>.</p>
</section>

<section class="card">
  <form id="up" action="/upload.php" method="post" enctype="multipart/form-data">
    <label id="drop" class="drop" for="file">
      <span class="ic"></span>
      <b>Drag &amp; drop your file here</b>
      <small>or click to browse &mdash; maximum <?= max_mb() ?> MB per file</small>
      <input type="file" id="file" name="file" hidden>
    </label>
    <div id="picked" class="picked" hidden><span id="pname"></span><span id="psize"></span></div>
    <div class="bar" id="bar" hidden><i id="fill"></i></div>
    <button class="btn" id="send" type="submit" disabled>Upload file</button>
    <p class="err" id="err" hidden></p>
  </form>

  <div id="done" class="done" hidden>
    <h2>Upload complete</h2>
    <div class="linkrow"><input id="link" readonly><button type="button" class="btn small" id="copy">Copy</button></div>
    <p class="muted" id="expires"></p>
    <p><a href="/" class="again">Upload another file</a></p>
  </div>
</section>

<section class="grid">
  <div><h3>No registration</h3><p>No sign-up form, no verification e-mail. Pick a file, get a link, move on.</p></div>
  <div><h3>Automatic clean-up</h3><p>Storage is temporary by design. Files and their links are purged <?= retention() ?> days after upload.</p></div>
  <div><h3>Direct links</h3><p>Every file gets a short, stable URL you can paste into chat, e-mail or a ticket.</p></div>
  <div><h3>Sensible limits</h3><p>Up to <?= max_mb() ?> MB per file. Executable and script formats are rejected to keep the service clean.</p></div>
</section>
<script src="/assets/app.js" defer></script>
<?php layout_foot();

<?php require_once __DIR__.'/lib/common.php';
http_response_code(404);
layout_head('Page not found', 'The page or file you requested does not exist or has expired.');
?>
<section class="card center">
  <h1>404 &mdash; not found</h1>
  <p class="lead">The page you are looking for does not exist, or the file has already been removed by our automatic clean-up.</p>
  <p><a class="btn" href="/">Back to the upload page</a></p>
</section>
<?php layout_foot();

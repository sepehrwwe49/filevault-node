(function () {
  var form = document.getElementById('up'), drop = document.getElementById('drop'),
      input = document.getElementById('file'), send = document.getElementById('send'),
      bar = document.getElementById('bar'), fill = document.getElementById('fill'),
      err = document.getElementById('err'), done = document.getElementById('done'),
      link = document.getElementById('link'), copy = document.getElementById('copy'),
      picked = document.getElementById('picked'), pname = document.getElementById('pname'),
      psize = document.getElementById('psize'), expires = document.getElementById('expires');
  if (!form) return;

  function human(b) {
    var u = ['B', 'KB', 'MB', 'GB'], i = 0;
    while (b >= 1024 && i < 3) { b /= 1024; i++; }
    return (i ? b.toFixed(1) : b) + ' ' + u[i];
  }
  function show(f) {
    pname.textContent = f.name; psize.textContent = human(f.size);
    picked.hidden = false; send.disabled = false; err.hidden = true;
  }
  input.addEventListener('change', function () { if (input.files[0]) show(input.files[0]); });

  ['dragenter', 'dragover'].forEach(function (e) {
    drop.addEventListener(e, function (ev) { ev.preventDefault(); drop.classList.add('over'); });
  });
  ['dragleave', 'drop'].forEach(function (e) {
    drop.addEventListener(e, function (ev) { ev.preventDefault(); drop.classList.remove('over'); });
  });
  drop.addEventListener('drop', function (ev) {
    var f = ev.dataTransfer && ev.dataTransfer.files[0];
    if (f) { input.files = ev.dataTransfer.files; show(f); }
  });

  form.addEventListener('submit', function (ev) {
    ev.preventDefault();
    if (!input.files[0]) return;
    var fd = new FormData(); fd.append('file', input.files[0]);
    var x = new XMLHttpRequest();
    x.open('POST', '/upload.php', true);
    send.disabled = true; send.textContent = 'Uploading…'; bar.hidden = false; err.hidden = true;
    x.upload.onprogress = function (e) {
      if (e.lengthComputable) fill.style.width = (e.loaded / e.total * 100) + '%';
    };
    x.onload = function () {
      var r = {};
      try { r = JSON.parse(x.responseText); } catch (e) {}
      send.textContent = 'Upload file';
      if (x.status === 200 && r.ok) {
        form.hidden = true; done.hidden = false;
        link.value = r.url; expires.textContent = 'This link expires on ' + r.expires + '.';
      } else {
        bar.hidden = true; fill.style.width = '0'; send.disabled = false;
        err.textContent = (r && r.error) || 'Upload failed. Please try again.';
        err.hidden = false;
      }
    };
    x.onerror = function () {
      bar.hidden = true; send.disabled = false; send.textContent = 'Upload file';
      err.textContent = 'Network error. Please try again.'; err.hidden = false;
    };
    x.send(fd);
  });

  copy.addEventListener('click', function () {
    link.select();
    try { document.execCommand('copy'); } catch (e) {}
    if (navigator.clipboard) navigator.clipboard.writeText(link.value);
    copy.textContent = 'Copied'; setTimeout(function () { copy.textContent = 'Copy'; }, 1600);
  });
})();

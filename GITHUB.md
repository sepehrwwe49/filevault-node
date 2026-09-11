# آپلود این پروژه روی گیت‌هاب

## ۱) مخزن بساز
github.com → New repository → نام مثلاً `filevault-node` → **Private** یا Public → بدون README/gitignore (همه‌چیز اینجا هست).

## ۲) از ویندوز (همین پوشه)
Git for Windows نصب باشد. داخل پوشه `vpn-nginx` راست‌کلیک → *Open Git Bash here*:

```bash
git init -b main
git add .
git status            # مطمئن شو .env در لیست نیست
git commit -m "FileVault node: nginx camouflage + upload site"
git remote add origin https://github.com/sepehrwwe49/filevault-node.git
git push -u origin main
```

> اگر `.env` واقعی ساختی، هرگز کامیتش نکن — `.gitignore` جلویش را می‌گیرد.

## ۳) لینک نصب را در فایل‌ها جایگزین کن
در `setup.sh` و `README.md` عبارت `sepehrwwe49/filevault-node` را با `sepehrwwe49/filevault-node` عوض کن، بعد:

```bash
git commit -am "fix repo url" && git push
```

## ۴) نصب روی هر نود

مخزن Public:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sepehrwwe49/filevault-node/main/setup.sh)
```

مخزن Private (با Personal Access Token):
```bash
export FV_REPO="https://TOKEN@github.com/sepehrwwe49/filevault-node.git"
bash <(curl -fsSL -H "Authorization: token TOKEN" \
  https://raw.githubusercontent.com/sepehrwwe49/filevault-node/main/setup.sh)
```

## ۵) اگر گیت‌هاب از ایران باز نشد
سرور ثابت `91.107.149.37` را آینه کن:

```bash
# روی 91.107.149.37 (یک‌بار)
git clone https://github.com/sepehrwwe49/filevault-node.git /opt/dist/filevault
cd /opt/dist && python3 -m http.server 8088 --bind 0.0.0.0 &
ufw allow 8088/tcp

# روی هر نود جدید
export FV_REPO="http://91.107.149.37:8088/filevault/.git"
bash <(curl -fsSL http://91.107.149.37:8088/filevault/setup.sh)
```
(برای اینکه `.git` روی http سرو شود: `cd /opt/dist/filevault && git update-server-info`)

## ۶) به‌روزرسانی نودها بعد از تغییر کد
```bash
sudo fv        # → گزینه ۱۷ (به‌روزرسانی از گیت‌هاب)
```

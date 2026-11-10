# AnyTLS-Go Server Installer and Control Panel

[English](#english) · [فارسی](#persian)

<a id="english"></a>

## English

Install the latest stable AnyTLS-Go release on Linux with systemd, manage its service from an interactive terminal panel, or configure a direct TCP forward on an Iran-side server with GOST.

## Quick install

Run this single line in an interactive Linux terminal:

~~~bash
installer=$(curl -fsSL https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh) && sudo bash -c "$installer"
~~~

The installer offers three choices:

1. **Install or reconfigure the AnyTLS server** — installs the official AnyTLS-Go server with a single password, or opens the control panel without replacing an existing multi-user sing-box backend.
2. **Set up direct forwarding with GOST** — configure an Iran-side entry point that forwards TCP to an AnyTLS server abroad. This does not install AnyTLS on the Iran server.
3. **Open the control panel** — manage the services already configured on this machine.

After installing the AnyTLS server, the panel opens automatically. Start it later with:

~~~bash
sudo anytls-panel
~~~

The TUI prompts and menus are in English.

## Iran-to-abroad direct forwarding

The data path is:

~~~text
AnyTLS client → Iran server IP:port → GOST TCP forward → foreign AnyTLS server IP:port
~~~

Choose **Set up direct Iran-to-abroad TCP forwarding with GOST**. The wizard asks for:

- The foreign AnyTLS server address (IP or DNS name).
- The AnyTLS TCP port.
- The listen IP on the Iran server.

The Iran entry port is set to the same number as the foreign AnyTLS port. In the client profile, replace only the server address with the **public IP of the Iran server**. Keep the existing port and AnyTLS password.

GOST relays the TCP stream to the configured foreign address and port; it does not need the AnyTLS password. The AnyTLS server must already be running abroad and reachable from the Iran server. Open the selected inbound TCP port in the Iran server firewall and provider firewall, and allow the Iran server to reach the foreign AnyTLS destination.

The wizard downloads the latest stable GOST release for Linux amd64 or arm64 from the official project and checks its SHA-256 digest before installing it. Forwarding runs as a systemd service, starts at boot, and restarts automatically after a failure. The service unit keeps the name anytls-tunnel for compatibility with the existing panel commands.

## Multiple accounts and sing-box client profiles

The upstream AnyTLS-Go server accepts one shared password. To manage multiple passwords on the same AnyTLS port, open **AnyTLS server → Manage accounts and client configs** in the TUI. The panel asks to migrate the server to the official sing-box AnyTLS backend and keeps the existing password as the first account. sing-box supports multiple named AnyTLS users on one inbound listener.

The account menu can add and revoke accounts, set an expiry in days, and export Android, iOS, and Windows sing-box JSON files. After export, choose a platform in the TUI to print its complete JSON in the terminal for copying; the files are also saved under /root/anytls-clients. Expired accounts are removed automatically about once per minute. New passwords are shown once when created. Treat the JSON and QR image as credentials and copy them securely to each device.

The QR image contains a de-facto AnyTLS share URI for apps that support URI import. Other sing-box apps can import the generated JSON file. The JSON pins the self-signed server certificate's public key, so it verifies that the client reaches this server. Re-export client files if the server certificate is replaced. QR URI import support and certificate handling vary by client; use the JSON profile when URI import does not connect.

The stock AnyTLS-Go and sing-box servers do not enforce per-account device counts or data-volume quotas. The TUI identifies this limitation instead of presenting non-enforced settings as real limits. Expiration is enforced.

## Panel features

- Show status and start, stop, restart, enable at boot, or disable at boot for the AnyTLS server and forwarding service.
- Review or follow service logs.
- Change the AnyTLS server listen IP and port; manage passwords from the account menu after migration.
- Manage multiple sing-box accounts, account expiry, and client exports after switching server backend.
- Set up or update the direct GOST TCP forward.
- View the non-secret forwarding address and port.
- Display the equivalent systemd commands.

## Service commands

These commands are also available from the TUI:

~~~bash
sudo systemctl status anytls
sudo systemctl start anytls
sudo systemctl stop anytls
sudo systemctl restart anytls
sudo systemctl enable anytls
sudo systemctl disable anytls
sudo journalctl -u anytls -f

sudo systemctl status anytls-tunnel
sudo systemctl start anytls-tunnel
sudo systemctl stop anytls-tunnel
sudo systemctl restart anytls-tunnel
sudo systemctl enable anytls-tunnel
sudo systemctl disable anytls-tunnel
sudo journalctl -u anytls-tunnel -f
~~~

Disabling a service prevents it from starting at boot but does not stop a service that is already running.

### Troubleshooting startup

If `journalctl -u anytls` shows `create netlink socket: address family not supported by protocol`, the systemd address-family allow-list is blocking a socket AnyTLS needs. The quick installer adds a persistent drop-in for existing AnyTLS and GOST services. Restart the affected service after the installer finishes. You can apply the AnyTLS fix manually with:

~~~bash
sudo install -d -m 0755 /etc/systemd/system/anytls.service.d
sudo tee /etc/systemd/system/anytls.service.d/zz-netlink.conf >/dev/null <<'UNIT'
[Service]
RestrictAddressFamilies=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
UNIT
sudo systemctl daemon-reload
sudo systemctl reset-failed anytls
sudo systemctl restart anytls
~~~

## Requirements and notes

- Linux with systemd and root or sudo access.
- curl, Python 3, and standard account utilities.
- The installer installs qrencode automatically when installing or opening the AnyTLS panel, so QR export is ready to use. Supported package managers are apt, dnf, yum, zypper, and apk. OpenSSL is required to migrate the server to multi-user mode and export pinned client profiles.
- GOST forwarding supports Linux amd64 and arm64.
- The account and migration tools support Linux amd64 and arm64.
- The forwarder listens on the IP selected in the wizard. Use **0.0.0.0** to accept connections on all IPv4 interfaces; restrict access through firewalls as needed.
- The listen port must be available on the Iran server.
- AnyTLS-Go describes itself as a reference implementation and warns that its sample configuration assumes there is no man-in-the-middle attack. Read the [upstream project documentation](https://github.com/anytls/anytls-go) before using it for sensitive traffic.

---

<a id="persian"></a>

## فارسی

آخرین نسخهٔ پایدار AnyTLS-Go را روی لینوکس دارای systemd نصب کنید، سرویس را از پنل تعاملی مدیریت کنید یا روی سرور ایران با GOST فوروارد مستقیم TCP به سرور AnyTLS خارج بسازید.

## نصب سریع

این یک خط را در ترمینال تعاملی لینوکس اجرا کنید:

~~~bash
installer=$(curl -fsSL https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh) && sudo bash -c "$installer"
~~~

نصب‌کننده سه گزینه دارد:

1. **نصب یا تنظیم دوبارهٔ سرور AnyTLS** — سرور رسمی AnyTLS-Go تک‌رمزی را نصب می‌کند؛ اگر سرور چندکاربرهٔ sing-box از قبل فعال باشد، پنل را بدون جایگزین‌کردن آن باز می‌کند.
2. **راه‌اندازی فوروارد مستقیم با GOST** — سرور ایران را به ورودی اتصال تبدیل می‌کند و TCP را به AnyTLS روی سرور خارج می‌فرستد. در این حالت AnyTLS روی سرور ایران نصب نمی‌شود.
3. **بازکردن پنل مدیریت** — سرویس‌های تنظیم‌شده را مدیریت می‌کند.

پس از نصب سرور AnyTLS، پنل خودکار باز می‌شود. برای اجرای دوباره:

~~~bash
sudo anytls-panel
~~~

منو و پرسش‌های TUI انگلیسی هستند.

## فوروارد مستقیم از ایران به خارج

مسیر داده به این شکل است:

~~~text
کلاینت AnyTLS → IP و پورت سرور ایران → فوروارد TCP با GOST → IP و پورت سرور AnyTLS خارج
~~~

گزینهٔ **Set up direct Iran-to-abroad TCP forwarding with GOST** را انتخاب کنید. راهنما این موارد را می‌پرسد:

- آدرس سرور AnyTLS خارج (IP یا نام دامنه).
- پورت TCP سرور AnyTLS.
- IP شنود روی سرور ایران.

پورت ورودی ایران با همان شمارهٔ پورت AnyTLS خارج تنظیم می‌شود. در پروفایل کلاینت فقط آدرس سرور را با **IP عمومی سرور ایران** جایگزین کنید؛ پورت و رمز AnyTLS را همان قبلی نگه دارید.

GOST جریان TCP را به آدرس و پورت سرور خارج منتقل می‌کند و به رمز AnyTLS نیاز ندارد. سرور AnyTLS باید از قبل روی سرور خارج فعال باشد و سرور ایران بتواند به آن دسترسی داشته باشد. پورت ورودی TCP را در فایروال سرور ایران و فایروال ارائه‌دهنده باز کنید و دسترسی خروجی سرور ایران به مقصد AnyTLS خارج را نیز مجاز کنید.

## چندکاربره‌کردن و ساخت پروفایل sing-box

سرور AnyTLS-Go اصلی فقط یک رمز مشترک می‌پذیرد. برای چند رمز روی یک پورت، در TUI مسیر **AnyTLS server → Manage accounts and client configs** را باز کنید. پنل با تأیید شما سرور را به پیاده‌سازی رسمی AnyTLS در sing-box منتقل می‌کند و رمز فعلی را به‌عنوان حساب اول نگه می‌دارد. sing-box چند کاربر نام‌دار را روی یک ورودی و پورت پشتیبانی می‌کند.

از منوی حساب‌ها می‌توانید کاربر اضافه یا حذف کنید، مدت اعتبار را برحسب روز تعیین کنید و فایل JSON sing-box برای Android، iOS و Windows بسازید. پس از خروجی گرفتن، در TUI سیستم‌عامل را انتخاب کنید تا متن کامل JSON در ترمینال نمایش داده شود و بتوانید آن را کپی کنید؛ فایل‌ها در مسیر /root/anytls-clients هم ذخیره می‌شوند. حساب منقضی‌شده تقریباً هر یک دقیقه به‌طور خودکار حذف می‌شود. رمز جدید فقط یک‌بار پس از ساخت نمایش داده می‌شود. JSON و تصویر QR را مثل اطلاعات ورود محرمانه نگه دارید و امن به دستگاه‌ها منتقل کنید.

QR شامل URI متداول AnyTLS برای برنامه‌هایی است که واردکردن URI را پشتیبانی می‌کنند. در بقیهٔ برنامه‌های sing-box فایل JSON را وارد کنید. JSON اثرانگشت کلید عمومی گواهی خودامضای سرور را pin می‌کند تا کلاینت همان سرور را اعتبارسنجی کند. اگر گواهی سرور عوض شد، فایل‌های کلاینت را دوباره بسازید. پشتیبانی QR و اعتبارسنجی گواهی بین برنامه‌ها فرق دارد؛ اگر URI وصل نشد، پروفایل JSON را وارد کنید.

سرورهای رسمی AnyTLS-Go و sing-box محدودیت تعداد دستگاه یا سقف حجم را برای هر حساب اعمال نمی‌کنند. پنل این محدودیت را شفاف نشان می‌دهد و گزینهٔ ظاهریِ بدون اثر ارائه نمی‌کند. انقضای حساب اعمال می‌شود.

راهنما آخرین نسخهٔ پایدار رسمی GOST برای Linux amd64 یا arm64 را دانلود و پیش از نصب SHA-256 آن را بررسی می‌کند. فوروارد به‌صورت سرویس systemd اجرا می‌شود، پس از راه‌اندازی مجدد سرور خودکار بالا می‌آید و در صورت خطا دوباره اجرا می‌شود. برای سازگاری با فرمان‌های پنل، نام سرویس anytls-tunnel باقی مانده است.

## امکانات پنل

- نمایش وضعیت و اجرای start، stop، restart، enable هنگام بوت یا disable برای سرور AnyTLS و سرویس فوروارد.
- مشاهده یا دنبال‌کردن گزارش سرویس‌ها.
- تغییر IP شنود و پورت سرور AnyTLS؛ پس از مهاجرت، رمزها از منوی حساب‌ها مدیریت می‌شوند.
- مدیریت حساب‌های چندگانهٔ sing-box، تاریخ انقضا و خروجی کلاینت پس از تغییر backend سرور.
- راه‌اندازی یا تنظیم دوبارهٔ فوروارد مستقیم TCP با GOST.
- نمایش آدرس و پورت فوروارد؛ رمز AnyTLS در این تنظیمات ذخیره نمی‌شود.
- نمایش دستورهای معادل systemd.

## دستورهای سرویس

این عملیات از داخل TUI هم در دسترس هستند:

~~~bash
sudo systemctl status anytls
sudo systemctl start anytls
sudo systemctl stop anytls
sudo systemctl restart anytls
sudo systemctl enable anytls
sudo systemctl disable anytls
sudo journalctl -u anytls -f

sudo systemctl status anytls-tunnel
sudo systemctl start anytls-tunnel
sudo systemctl stop anytls-tunnel
sudo systemctl restart anytls-tunnel
sudo systemctl enable anytls-tunnel
sudo systemctl disable anytls-tunnel
sudo journalctl -u anytls-tunnel -f
~~~

disable اجرای خودکار هنگام بوت را متوقف می‌کند، اما سرویسی را که اکنون فعال است متوقف نمی‌کند.

### عیب‌یابی اجرا

اگر در `journalctl -u anytls` پیام `create netlink socket: address family not supported by protocol` دیدید، فهرست خانواده‌های آدرس systemd جلوی سوکتی را گرفته که AnyTLS به آن نیاز دارد. اجرای دوبارهٔ نصب‌کننده برای سرویس‌های موجود AnyTLS و GOST تنظیم پایدار اضافه می‌کند. پس از پایان، سرویس مربوط را restart کنید. اصلاح دستی AnyTLS:

~~~bash
sudo install -d -m 0755 /etc/systemd/system/anytls.service.d
sudo tee /etc/systemd/system/anytls.service.d/zz-netlink.conf >/dev/null <<'UNIT'
[Service]
RestrictAddressFamilies=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
UNIT
sudo systemctl daemon-reload
sudo systemctl reset-failed anytls
sudo systemctl restart anytls
~~~

## پیش‌نیازها و نکته‌ها

- لینوکس دارای systemd و دسترسی root یا sudo.
- curl، Python 3 و ابزارهای استاندارد مدیریت حساب.
- نصب‌کننده هنگام نصب AnyTLS یا بازکردن پنل، qrencode را خودکار نصب می‌کند تا خروجی QR آماده باشد. package managerهای پشتیبانی‌شده apt، dnf، yum، zypper و apk هستند. برای مهاجرت به حالت چندکاربره و ساخت پروفایل pin‌شده OpenSSL لازم است.
- فوروارد GOST از Linux amd64 و arm64 پشتیبانی می‌کند.
- فوروارد روی IP انتخاب‌شده در راهنما شنود می‌کند. برای پذیرش اتصال روی همهٔ رابط‌های IPv4 مقدار **0.0.0.0** را انتخاب کنید و دسترسی را با فایروال محدود کنید.
- پورت ورودی باید روی سرور ایران آزاد باشد.
- AnyTLS-Go خود را پیاده‌سازی مرجع معرفی می‌کند و هشدار می‌دهد تنظیم نمونه با فرض نبود حملهٔ MITM است. پیش از استفاده برای ترافیک حساس، [مستندات پروژهٔ اصلی](https://github.com/anytls/anytls-go) را بخوانید.

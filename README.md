# AnyTLS-Go Server Installer and Control Panel

[English](#english) · [فارسی](#persian)

<a id="english"></a>

## English

Install the interactive control panel on Linux with systemd. From the panel, install or manage AnyTLS, configure direct or reverse GOST forwarding between Iran and a foreign server, or view the command reference.

## Quick install

Run this single line in an interactive Linux terminal:

~~~bash
installer=$(curl -fsSL https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh) && sudo bash -c "$installer"
~~~

The control panel opens directly after quick installation. Choose **AnyTLS server management** to install or configure the server, or **GOST forwarding management** to configure direct forwarding or a reverse tunnel. Start it later with:

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

## Reverse GOST tunnel

Use this mode when AnyTLS-Go runs on one server and clients should connect through a different public-facing server. Only the backend host needs AnyTLS-Go. GOST runs on both hosts: the Relay listens on the client-facing host, and the Agent makes an outbound connection from the AnyTLS-Go host and forwards the Relay's client entry port to the local AnyTLS-Go service. GOST's Relay BIND function provides the remote entry port. The panel uses Relay over TLS with a generated username and password. See the [GOST Relay documentation](https://gost.run/en/tutorials/protocols/relay/) for remote port forwarding.

For this setup, AnyTLS-Go runs on the abroad server and clients connect to Iran:

~~~text
AnyTLS client → Iran public IP:entry port → GOST Relay on Iran → outbound GOST Agent abroad → 127.0.0.1:AnyTLS-Go port
~~~

Configure the two roles separately:

1. On Iran, choose **GOST forwarding management → Set up or update reverse GOST tunnel → Configure Relay server (client entry point)**. Save the generated Relay username and password. Allow the Relay control TCP port (default `8444`) from the abroad server's public IP in the Iran and provider firewalls.
2. On the abroad server, choose **GOST forwarding management → Set up or update reverse GOST tunnel → Configure reverse Agent (AnyTLS backend)**. Enter the Iran Relay address, control port and credentials, client entry port on Iran, and the local AnyTLS-Go backend address and port. Entry and backend ports default to `8443`; the backend address defaults to `127.0.0.1`.
3. Allow the client entry TCP port from client networks on Iran and its provider firewall. In the AnyTLS client profile, use Iran's public IP and entry port; keep the abroad AnyTLS-Go password unchanged.

The Agent initiates the connection to the Relay, so the Iran firewall must allow its control port from the abroad server. Restrict that port to the abroad server's public IP when possible. The Relay credentials and GOST configuration are stored in a restricted file. TLS encrypts the Relay data, but the Agent does not verify GOST's automatically generated certificate; source-IP firewall restrictions are recommended. Setting up either GOST mode replaces the `anytls-tunnel` configuration on that host, so configure the Relay on Iran and Agent abroad.

## Single-user server and client profiles

The server runs the upstream AnyTLS-Go implementation with one shared password. A fresh installation generates a random 32-character password and prints it once so you can save it; the password is stored in the root-only server settings. Reconfiguring the listen IP or port also generates and saves a new random password, then shows it once. This invalidates existing client profiles, so export fresh QR/JSON profiles from option 3 on the abroad server. The exporter creates both connection variants using the password saved by AnyTLS-Go: an Iran GOST tunnel profile and an abroad direct profile. On the first export, enter the abroad public IP, Iran public IP, and Iran GOST entry port. The panel securely saves the latest addresses, ports, and SNI in `/root/anytls-clients/export-settings.json`; later exports show the saved values and let you reuse them or enter new ones. The current AnyTLS-Go password is read from the server settings each time. Separate NekoBox QR and Android, iOS, and Windows sing-box JSON files are stored under `/root/anytls-clients/iran-gost-tunnel/` and `/root/anytls-clients/abroad-direct/`. Each profile name and JSON filename remains `AnyTLS-Go`.

The tunnel profile uses Iran's public IP and must use the same port configured as the GOST client entry on Iran. It works with either direct or reverse GOST forwarding when that mode is active on Iran; the panel configures one GOST mode per server at a time. The direct profile uses the abroad server's public IP and the local AnyTLS-Go port. For NekoBox, import the corresponding AnyTLS QR/link. The JSON profiles are full sing-box configurations: they enable `tls.insecure`, set ALPN to `h2` and `http/1.1`, use a device-specific uTLS fingerprint (`android`, `ios`, or `chrome` for Windows), and send DNS through the AnyTLS outbound. NekoBox imports sing-box outbound nodes without their routing rules, and its URL test uses direct DNS; therefore, its `cp.cloudflare.com` / “missing default interface” test error may remain. A failed URL test alone does not prove the AnyTLS connection failed; confirm by opening a website through the connected proxy. The default SNI is `www.cloudflare.com`; replace it with your own server domain when available. SNI does not route traffic through Cloudflare or guarantee that a connection will pass filtering. `tls.insecure` disables certificate verification and can expose the connection to interception. uTLS fingerprint imitation does not guarantee that traffic will avoid detection.

If a server still uses the legacy sing-box multi-user backend, choose **AnyTLS server management → Restore AnyTLS-Go single-user mode**. The first active account password becomes the shared AnyTLS-Go password. Existing sing-box settings and client exports are saved in a backup directory.

## Panel features

- Show status and start, stop, restart, enable at boot, or disable at boot for the AnyTLS server and forwarding service.
- Review or follow service logs.
- Change the AnyTLS server listen IP and port while generating a new shared password; restore the previous settings if the service fails to start.
- Restore legacy sing-box installations to the AnyTLS-Go single-user backend.
- Export Iran-tunnel and abroad-direct AnyTLS-Go QR codes and Android, iOS, and Windows sing-box JSON profiles, reusing saved addresses and ports or entering new values.
- Set up or update direct GOST TCP forwarding or the two roles of a reverse GOST tunnel.
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
- curl, Python 3, and standard system utilities.
- The installer installs qrencode automatically when installing or opening the AnyTLS panel, so QR export is ready to use. Supported package managers are apt, dnf, yum, zypper, and apk.
- Direct and reverse GOST forwarding support Linux amd64 and arm64. Reverse mode requires the Agent host to reach the Relay control port.
- The server installer supports Linux amd64 and arm64.
- Direct forwarding listens on the IP selected in its wizard. Use **0.0.0.0** to accept connections on all IPv4 interfaces; restrict access through firewalls as needed.
- The listen port must be available on the Iran server.
- AnyTLS-Go describes itself as a reference implementation and warns that its sample configuration assumes there is no man-in-the-middle attack. Read the [upstream project documentation](https://github.com/anytls/anytls-go) before using it for sensitive traffic.

---

<a id="persian"></a>

## فارسی

پنل تعاملی را روی لینوکس دارای systemd نصب کنید. از داخل پنل می‌توانید AnyTLS را نصب یا مدیریت کنید، فوروارد مستقیم یا معکوس GOST بین ایران و سرور خارج بسازید یا راهنمای فرمان‌ها را ببینید.

## نصب سریع

این یک خط را در ترمینال تعاملی لینوکس اجرا کنید:

~~~bash
installer=$(curl -fsSL https://raw.githubusercontent.com/alirezahdr/anytls-go-installer/main/install-anytls.sh) && sudo bash -c "$installer"
~~~

پس از نصب سریع، پنل اصلی مستقیم باز می‌شود. برای نصب یا تنظیم سرور، **AnyTLS server management** و برای تنظیم فوروارد مستقیم یا معکوس، **GOST forwarding management** را انتخاب کنید. برای اجرای دوبارهٔ پنل:

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

## تونل معکوس GOST

در این حالت AnyTLS-Go روی یک سرور اجرا می‌شود و کلاینت‌ها از سرور عمومی دیگری وارد می‌شوند. فقط روی سرور مقصد AnyTLS-Go نصب می‌شود. روی هر دو سرور GOST اجرا می‌شود: Relay روی سرور ورودی کلاینت قرار می‌گیرد و Agent از سرور AnyTLS-Go به Relay اتصال خروجی می‌زند و پورت ورودی را به AnyTLS-Go محلی فوروارد می‌کند. قابلیت Relay BIND در GOST پورت ورودی را از راه دور ایجاد می‌کند. پنل Relay را با TLS و نام‌کاربری و رمز تصادفی اجرا می‌کند. جزئیات این روش در [مستند رسمی Relay در GOST](https://gost.run/en/tutorials/protocols/relay/) آمده است.

در این چیدمان AnyTLS-Go روی سرور خارج است و کلاینت‌ها به ایران وصل می‌شوند:

~~~text
کلاینت AnyTLS → IP عمومی ایران:پورت ورودی → GOST Relay روی ایران → اتصال خروجی GOST Agent روی سرور خارج → 127.0.0.1:پورت AnyTLS-Go
~~~

دو نقش را جداگانه تنظیم کنید:

1. در ایران مسیر **GOST forwarding management → Set up or update reverse GOST tunnel → Configure Relay server (client entry point)** را انتخاب کنید. نام‌کاربری و رمز ساخته‌شده را نگه دارید. پورت کنترل TCP (پیش‌فرض `8444`) را در فایروال ایران و ارائه‌دهنده فقط برای IP عمومی سرور خارج باز کنید.
2. روی سرور خارج مسیر **GOST forwarding management → Set up or update reverse GOST tunnel → Configure reverse Agent (AnyTLS backend)** را انتخاب کنید. آدرس Relay ایران، پورت کنترل و مشخصات ورود، پورت ورودی کلاینت روی ایران، و آدرس و پورت محلی AnyTLS-Go را وارد کنید. پورت ورودی و مقصد پیش‌فرض `8443` و آدرس مقصد پیش‌فرض `127.0.0.1` است.
3. پورت ورودی کلاینت را در فایروال ایران و ارائه‌دهنده برای کاربران باز کنید. در پروفایل AnyTLS، IP عمومی ایران و پورت ورودی را قرار دهید؛ رمز AnyTLS-Go روی سرور خارج بدون تغییر می‌ماند.

Agent اتصال را به Relay آغاز می‌کند؛ بنابراین فایروال ایران باید پورت کنترل را از سرور خارج بپذیرد. اگر امکان دارد این پورت را به IP عمومی سرور خارج محدود کنید. اطلاعات Relay و تنظیمات GOST در فایلی با دسترسی محدود ذخیره می‌شوند. TLS دادهٔ Relay را رمز می‌کند، اما Agent گواهی خودکار GOST را بررسی نمی‌کند؛ محدودکردن دسترسی پورت کنترل به IP مبدأ توصیه می‌شود. انتخاب هرکدام از حالت‌های GOST، تنظیم سرویس `anytls-tunnel` همان سرور را جایگزین می‌کند؛ Relay روی ایران و Agent روی سرور خارج تنظیم می‌شوند.

## ساخت پروفایل کلاینت

سرور با پیاده‌سازی اصلی AnyTLS-Go و یک رمز مشترک اجرا می‌شود. نصب تازه یک رمز تصادفی ۳۲ کاراکتری می‌سازد و آن را یک‌بار برای ذخیره‌کردن نشان می‌دهد؛ رمز در تنظیمات فقط‌خواندنی برای root ذخیره می‌شود. با تغییر IP شنود یا پورت، رمز تصادفی تازه‌ای هم ساخته و ذخیره می‌شود و یک‌بار نمایش داده می‌شود. پروفایل‌های قبلی پس از این تغییر کار نمی‌کنند؛ از گزینهٔ ۳ در پنل سرور خارج QR/JSON تازه بسازید. خروجی‌ساز با رمز ذخیره‌شدهٔ AnyTLS-Go دو مدل پروفایل می‌سازد: تونل GOST ایران و اتصال مستقیم سرور خارج. در نخستین خروجی، IP عمومی سرور خارج، IP عمومی ایران و پورت ورودی GOST ایران را وارد کنید. پنل آخرین IPها، پورت‌ها و SNI را با دسترسی root-only در `/root/anytls-clients/export-settings.json` ذخیره می‌کند؛ دفعات بعد مقادیر قبلی را نمایش می‌دهد تا دوباره استفاده کنید یا مقادیر جدید وارد کنید. رمز جاری AnyTLS-Go هر بار از تنظیمات سرور خوانده می‌شود. فایل‌های QR و JSON اندروید، iOS و Windows در پوشه‌های `/root/anytls-clients/iran-gost-tunnel/` و `/root/anytls-clients/abroad-direct/` ذخیره می‌شوند. نام هر دو پروفایل و فایل JSON برابر `AnyTLS-Go` است.

پروفایل تونل از IP ایران و پورتی استفاده می‌کند که باید با پورت ورودی GOST روی ایران یکی باشد. این پروفایل با فوروارد مستقیم یا تونل معکوس GOST کار می‌کند، به شرط آنکه همان روش روی ایران فعال باشد؛ پنل در هر سرور هم‌زمان یک روش GOST را پیکربندی می‌کند. پروفایل مستقیم از IP سرور خارج و پورت شنود AnyTLS-Go استفاده می‌کند. برای NekoBox، QR یا لینک AnyTLS مربوط به روش موردنظر را وارد کنید. فایل‌های JSON پیکربندی کامل sing-box هستند: `tls.insecure`، ALPN برابر `h2` و `http/1.1`، fingerprint متناسب با دستگاه (`android`، `ios` یا `chrome` برای Windows) و DNS از مسیر AnyTLS را تنظیم می‌کنند. NekoBox از JSONهای sing-box فقط outbound را وارد می‌کند و قوانین مسیریابی را نادیده می‌گیرد؛ تست URL آن نیز DNS مستقیم دارد. به همین دلیل ممکن است خطای `cp.cloudflare.com` یا `missing default interface` در تست باقی بماند. خطای تست به‌تنهایی ثابت نمی‌کند اتصال AnyTLS برقرار نشده؛ پس از اتصال، یک سایت را در مرورگر باز کنید. SNI پیش‌فرض `www.cloudflare.com` است؛ در صورت داشتن دامنهٔ خودتان آن را جایگزین کنید. SNI اتصال را از مسیر Cloudflare عبور نمی‌دهد و عبور از فیلترینگ را تضمین نمی‌کند. گزینهٔ `tls.insecure` بررسی گواهی را غیرفعال می‌کند و می‌تواند اتصال را در برابر رهگیری آسیب‌پذیر کند. تقلید uTLS نیز تضمینی برای شناسایی‌نشدن ترافیک نیست.

اگر سروری هنوز از بک‌اند قدیمی sing-box چندکاربره استفاده می‌کند، از مسیر **AnyTLS server management → Restore AnyTLS-Go single-user mode** برگردید. رمز اولین حساب فعال به رمز مشترک AnyTLS-Go تبدیل می‌شود و تنظیمات و خروجی‌های sing-box در پوشهٔ پشتیبان نگه داشته می‌شوند.

راهنما آخرین نسخهٔ پایدار رسمی GOST برای Linux amd64 یا arm64 را دانلود و پیش از نصب SHA-256 آن را بررسی می‌کند. فوروارد به‌صورت سرویس systemd اجرا می‌شود، پس از راه‌اندازی مجدد سرور خودکار بالا می‌آید و در صورت خطا دوباره اجرا می‌شود. برای سازگاری با فرمان‌های پنل، نام سرویس anytls-tunnel باقی مانده است.

## امکانات پنل

- نمایش وضعیت و اجرای start، stop، restart، enable هنگام بوت یا disable برای سرور AnyTLS و سرویس فوروارد.
- مشاهده یا دنبال‌کردن گزارش سرویس‌ها.
- تغییر IP شنود و پورت همراه با ساخت رمز مشترک تازه؛ اگر سرویس اجرا نشود تنظیم قبلی بازگردانده می‌شود.
- بازگرداندن نصب‌های قدیمی sing-box به حالت تک‌کاربرهٔ AnyTLS-Go.
- ساخت QR تونل ایران و اتصال مستقیم سرور خارج، همراه فایل JSON sing-box برای Android، iOS و Windows و امکان استفادهٔ دوباره از مشخصات ذخیره‌شده.
- راه‌اندازی فوروارد مستقیم GOST یا هر دو نقش تونل معکوس GOST.
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
- curl، Python 3 و ابزارهای استاندارد سیستم.
- نصب‌کننده هنگام نصب AnyTLS یا بازکردن پنل، qrencode را خودکار نصب می‌کند تا خروجی QR آماده باشد. package managerهای پشتیبانی‌شده apt، dnf، yum، zypper و apk هستند.
- فوروارد GOST از Linux amd64 و arm64 پشتیبانی می‌کند.
- فوروارد روی IP انتخاب‌شده در راهنما شنود می‌کند. برای پذیرش اتصال روی همهٔ رابط‌های IPv4 مقدار **0.0.0.0** را انتخاب کنید و دسترسی را با فایروال محدود کنید.
- پورت ورودی باید روی سرور ایران آزاد باشد.
- AnyTLS-Go خود را پیاده‌سازی مرجع معرفی می‌کند و هشدار می‌دهد تنظیم نمونه با فرض نبود حملهٔ MITM است. پیش از استفاده برای ترافیک حساس، [مستندات پروژهٔ اصلی](https://github.com/anytls/anytls-go) را بخوانید.

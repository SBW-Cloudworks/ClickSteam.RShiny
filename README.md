![R](https://img.shields.io/badge/R-4.1+-blue.svg) ![Shiny](https://img.shields.io/badge/Shiny-1.7+-brightgreen.svg) ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-blue.svg) ![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04-orange.svg)

# SBW Clickstream Dashboard – Hướng dẫn cài Shiny + R trên EC2 (Private)

Tài liệu này hướng dẫn cài **Shiny**, **R** và các thư viện cần thiết trên EC2 Ubuntu (private) để chạy app:

* Shiny dashboard: `SBW Clickstream Dashboard`
* Database: PostgreSQL `clickstream_dw` trên cùng EC2 (`127.0.0.1`)
* Bảng DWH: `clickstream_events` với các cột `event_timestamp`, `event_name`, `user_login_state`, `context_product_*`…

> 🔐 **Lưu ý**: EC2 ở private subnet → để chạy `apt-get` và `install.packages()` bắt buộc phải tạm thời cho EC2 ra Internet (NAT Gateway) hoặc gắn ra public **trong thời gian cài đặt**, sau đó tắt lại.

---

## 1. Thông tin môi trường

* OS: **Ubuntu 22.04** (Jammy) – AWS EC2
* PostgreSQL: **v18** (cài từ repo `apt.postgresql.org`)
* Shiny Server: cài theo hướng dẫn RStudio (binary `.deb`)
* User chạy Shiny: `shiny`
* App path: `/srv/shiny-server/sbw_dashboard/app.R`

---

## 2. Cài các package hệ thống (system libs)

Đăng nhập EC2 bằng SSM Session Manager hoặc SSH, sau đó chạy:

```bash
# 1) Update danh sách package
sudo apt-get update

# 2) Cài R (nếu chưa cài)
sudo apt-get install -y r-base

# 3) Cài Postgres client & dev headers (cho RPostgres)
#    Nếu DB của bạn là PG 18 thì dùng postgresql-server-dev-18
#    (nếu version khác thì đổi số 18 -> 14, 15, ...)
sudo apt-get install -y postgresql-client-18 postgresql-server-dev-18

# 4) Cài libpq + libssl (bắt buộc để build RPostgres)
sudo apt-get install -y libpq-dev libssl-dev

# 5) (Nếu chưa cài Shiny Server)
#    Tùy theo cách bạn đã cài, ở đây chỉ ghi nhớ:
#    - shiny-server service: /etc/systemd/system/shiny-server.service
#    - thư mục app: /srv/shiny-server/
#    - user chạy: shiny
```

Kiểm tra lại `libpq` và dev headers đã có:

```bash
dpkg -l | grep -E 'libpq-dev|postgresql-server-dev' || echo "MISSING_LIBS"
ls -l /usr/include/postgresql/libpq-fe.h || echo "NO_LIBPQ_HEADER"
```

Nếu không thấy lỗi → OK.

---

## 3. Cấu hình thư mục R libraries cho user `shiny`

Để Shiny Server load được các package R, ta cài package **dưới user `shiny`** và dùng thư mục:

* `/home/shiny/R/x86_64-pc-linux-gnu-library/4.1`

Chạy:

```bash
sudo -u shiny R --vanilla <<'EOF'
# Tạo thư mục library cho user shiny nếu chưa có
dir.create(Sys.getenv("R_LIBS_USER"), recursive = TRUE, showWarnings = FALSE)

# Đưa R_LIBS_USER lên đầu .libPaths()
.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
cat("LIBPATHS:\n"); print(.libPaths())

q("no")
EOF
```

Bạn sẽ thấy `LIBPATHS` có dòng 1 là `/home/shiny/R/x86_64-pc-linux-gnu-library/4.1`.

---

## 4. Cài các R package cần thiết

Các package cần cho dashboard:

* `shiny`
* `DBI`
* `RPostgres`
* `dplyr`
* `ggplot2`
* `lubridate`
* `pool`

Cài tất cả **dưới user `shiny`**:

```bash
sudo -u shiny R --vanilla <<'EOF'
dir.create(Sys.getenv("R_LIBS_USER"), recursive = TRUE, showWarnings = FALSE)
.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
cat("LIBPATHS:\n"); print(.libPaths())

install.packages(
  c("shiny", "DBI", "RPostgres", "dplyr", "ggplot2", "lubridate", "pool"),
  repos = "https://cloud.r-project.org"
)

q("no")
EOF
```

> 💡 Nếu gặp lỗi liên quan tới `libpq-fe.h` hoặc `libpq`:
>
> * Kiểm tra lại đã cài `libpq-dev`, `postgresql-server-dev-XX`, `libssl-dev` chưa.
> * Chạy lại đoạn `install.packages("RPostgres", ...)` sau khi cài đủ libs.

Kiểm tra lại việc load package:

```bash
sudo -u shiny R --vanilla <<'EOF'
.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
cat("LIBPATHS:\n"); print(.libPaths())

library(shiny)
library(DBI)
library(RPostgres)
library(dplyr)
library(ggplot2)
library(lubridate)
library(pool)

cat("All packages loaded OK\n")
q("no")
EOF
```

Nếu không có error → môi trường R đã OK.

---

## 5. Triển khai Shiny app

### 5.1. Tạo thư mục app và copy code

```bash
sudo mkdir -p /srv/shiny-server/sbw_dashboard
sudo chown -R shiny:shiny /srv/shiny-server/sbw_dashboard
```

Tạo (hoặc thay) file app:

```bash
sudo nano /srv/shiny-server/sbw_dashboard/app.R
# DÁN TOÀN BỘ CODE app.R (bản full mà bạn đang dùng)
# Ctrl+O, Enter, Ctrl+X để lưu
```

Đảm bảo quyền:

```bash
sudo chown shiny:shiny /srv/shiny-server/sbw_dashboard/app.R
sudo chmod 644 /srv/shiny-server/sbw_dashboard/app.R
```

### 5.2. Restart Shiny server

```bash
sudo systemctl restart shiny-server
sudo systemctl status shiny-server
```

---

## 6. Kiểm tra app từ EC2 (local)

Từ session SSM trên EC2:

```bash
# Check trang welcome Shiny
curl -m 5  -sS -o /dev/null -w "WELCOME HTTP %{http_code}\n" \
  http://127.0.0.1:3838/

# Check app SBW dashboard
curl -m 10 -sS -o /dev/null -w "DASHBOARD HTTP %{http_code}\n" \
  http://127.0.0.1:3838/sbw_dashboard/
```

Nếu trả về `DASHBOARD HTTP 200` → app chạy OK.

Nếu `500`:

```bash
LATEST=$(ls -1t /var/log/shiny-server/sbw_dashboard-shiny-*.log | head -n 1)
echo "LATEST=$LATEST"
sudo tail -n 100 "$LATEST"
```

Xem error log để debug.

---

## 7. Truy cập dashboard từ máy local

Vì EC2 ở private subnet, bạn dùng **SSM port-forwarding**:

```bash
# Ví dụ dùng AWS CLI v2 trên máy local:
aws ssm start-session \
  --target <INSTANCE_ID_PRIVATE> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["127.0.0.1"],"portNumber":["3838"],"localPortNumber":["3838"]}'
```

Sau đó, trên máy local mở:

* `http://127.0.0.1:3838/sbw_dashboard/`

Dashboard sẽ hiển thị với:

* KPI cards
* Biểu đồ events over time, event mix, events by login state
* Tab Products & Raw sample (phân trang, newest trước, auto refresh mỗi 10s)

---

## 8. Tóm tắt nhanh các lệnh quan trọng

```bash
# Cài system libs
sudo apt-get update
sudo apt-get install -y r-base postgresql-client-18 postgresql-server-dev-18 libpq-dev libssl-dev

# Cài R packages cho user shiny
sudo -u shiny R --vanilla <<'EOF'
dir.create(Sys.getenv("R_LIBS_USER"), recursive = TRUE, showWarnings = FALSE)
.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
install.packages(
  c("shiny", "DBI", "RPostgres", "dplyr", "ggplot2", "lubridate", "pool"),
  repos = "https://cloud.r-project.org"
)
q("no")
EOF

# Deploy app
sudo mkdir -p /srv/shiny-server/sbw_dashboard
sudo nano /srv/shiny-server/sbw_dashboard/app.R   # dán code
sudo chown -R shiny:shiny /srv/shiny-server/sbw_dashboard
sudo systemctl restart shiny-server

# Kiểm tra
curl -m 10 -sS -o /dev/null -w "DASHBOARD HTTP %{http_code}\n" \
  http://127.0.0.1:3838/sbw_dashboard/
```


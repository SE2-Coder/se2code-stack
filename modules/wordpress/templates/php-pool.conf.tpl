; ============================================================================
; POOL FPM: {{SITE_SLUG}} (Puerto {{PHP_PORT}})
; Generado por se2Code Stack Server
; ============================================================================

[{{SITE_SLUG}}]
user = www-data
group = www-data

listen = 0.0.0.0:{{PHP_PORT}}

pm = dynamic
pm.max_children = 50
pm.start_servers = 10
pm.min_spare_servers = 5
pm.max_spare_servers = 20
pm.max_requests = 1000
pm.process_idle_timeout = 10s

pm.status_path = /status
ping.path = /ping
ping.response = pong

access.log = /var/log/php/{{SITE_SLUG}}.access.log
access.format = "%{REMOTE_ADDR}e - %u %t \"%m %r%Q%q\" %s %f %{milliseconds}d %M %C%%"

slowlog = /var/log/php/{{SITE_SLUG}}-slow.log
request_slowlog_timeout = 10s
request_terminate_timeout = 300s

env[HOSTNAME] = $HOSTNAME
env[PATH] = /usr/local/bin:/usr/bin:/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp

php_admin_value[error_log] = /var/log/php/{{SITE_SLUG}}-error.log
php_admin_flag[log_errors] = on
php_admin_value[sendmail_path] = /bin/true

php_value[session.save_path] = /tmp
php_value[soap.wsdl_cache_dir] = /tmp
php_value[upload_tmp_dir] = /tmp

php_value[memory_limit] = 1024M
php_value[max_execution_time] = 300
php_value[max_input_time] = 300
php_value[max_input_vars] = 10000
php_value[default_socket_timeout] = 300
php_value[upload_max_filesize] = 256M
php_value[post_max_size] = 256M

clear_env = no
catch_workers_output = yes

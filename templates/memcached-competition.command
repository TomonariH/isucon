# memcached competition command template
# Apply to Docker Compose command: or systemd ExecStart after checking the
# service is used only for cache/session data.

memcached -m 256 -c 4096 -t 2

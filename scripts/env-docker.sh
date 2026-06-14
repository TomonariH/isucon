# Docker Compose 環境の analyze.sh 用ログパス設定
# setup-docker.sh が自動生成。analyze.sh が自動 source する。
export NGINX_ACCESS_LOG="/home/tomo/private-isu/webapp/logs/nginx/access.log"
export MYSQL_SLOW_LOG="/home/tomo/private-isu/webapp/logs/mysql/slow.log"

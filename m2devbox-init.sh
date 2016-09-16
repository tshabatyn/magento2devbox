#!/bin/bash

get_free_port () {
    local port=$1

    while [[ ! $port ]] || [[ $(lsof -i tcp:$port | grep "(LISTEN)") ]]; do
        port=$(jot -r 1 1 65000)
    done

    echo $port
}

request () {
    local varName=$1
    local question=$2
    local isBoolean=$3
    local defaultValue=$4
    local value
    local output

    if [[ $isBoolean = 1 ]]; then
        if [[ $defaultValue = 1 ]]; then
            question="$question [Y/n]"
        else
            question="$question [y/N]"
        fi
    else
        if [[ $defaultValue != '' ]]; then
            question="$question [default: $defaultValue]"
        fi
    fi

    read -p "$question: " value #prompt value
    value=$(echo $value | xargs) #trim input

    if [[ ${#value} > 0 ]]; then
        if [[ $isBoolean = 1 ]]; then
            if $(echo $value | grep -Eiq '^(?:[1y]|yes|true)$'); then
                value=1
                output='yes'
            else
                value=0
                output='no'
            fi
        else
            output=$value
        fi
    else
        if [[ $isBoolean = 1 ]]; then
            if [[ $defaultValue = 1 ]]; then
                value=1
                output='yes'
            else
                value=0
                output='no'
            fi
        else
            value=$defaultValue
            output=$value
        fi
    fi

    export $varName=$value
    echo $output
}

while test $# -gt 0; do
    case $1 in
        -it)
            interactive=1
            shift
            ;;
        --*)
            export $( \
                echo $1 | sed -e 's/^--\([^=]*\)=[^=]*$/\1/g' | sed -e 's/-/_/g' \
            )=$( \
                echo $1 | sed -e 's/^[^=]*=//g' \
            )
            shift
            ;;
        *)
            break
            ;;
    esac
done

echo 'Creating docker-compose config'

#Database
db_host='db'
db_password='root'
db_user='root'
db_name='magento2'
db_port=3306
db_home_port=$(get_free_port 1345)
db_path='/var/lib/mysql'
db_logs_path='/var/log/mysql'
db_home_logs_path='./shared/logs/mysql'

if [[ ! $db_home_path ]]; then
    db_home_path='./shared/db'
fi

#RabbitMQ
rabbitmq_host='rabbit'
rabbitmq_port=5672
rabbitmq_admin_port=15672
rabbitmq_home_port=$(get_free_port $rabbitmq_port)
rabbitmq_home_admin_port=$(get_free_port 8282)

#Redis
redis_host='redis'

#Varnish
varnish_container=magento2-devbox-varnish
varnish_port=6081
varnish_home_port=$(get_free_port 1748)
varnish_config_path='/home/magento2/scripts/default.vcl'

#Elastic Search
elastic_host='elasticsearch'
elastic_port=9200
elastic_home_port=$(get_free_port 9200)

#Web Server
webserver_container=magento2-devbox-web
webserver_host=web
webserver_port=80
webserver_ssh_port=22
webserver_home_port=$(get_free_port 1749)
webserver_home_ssh_port=$(get_free_port 2222)
webserver_apache_logs_path='/var/log/apache2'
webserver_phpfpm_logs_path='/var/log/php-fpm'
webserver_home_apache_logs_path='./shared/logs/apache2'
webserver_home_phpfpm_logs_path='./shared/logs/php-fpm'

#Paths
magento_path='/var/www/magento2'
magento_cloud_path='./shared/.magento-cloud'
magento_cloud_home_path='/root/.magento-cloud'
composer_home_path='/home/magento2/.composer'
ssh_home_path='/home/magento2/.ssh'

if [[ $magento_home_path ]]; then
    magento_sources_reuse=1
else
    magento_home_path='./shared/webroot'

    if [[ ! $magento_sources_reuse ]]; then
        request 'magento_sources_reuse' 'Do you have existing copy of Magento 2?' 1
    fi

    if [[ $magento_sources_reuse = 1 ]]; then
        request 'magento_home_path' 'Please provide full path to the Magento folder on local machine'
    fi
fi

if [[ ! $composer_path ]]; then
    composer_path='./shared/.composer'
fi

if [[ ! $ssh_path ]]; then
    ssh_path='./shared/.ssh'
fi

cat > docker-compose.yml <<- EOM
##
# Services needed to run Magento2 application on Docker
#
# Docker Compose defines required services and attach them together through aliases
##
version: '2'
services:
  $db_host:
    container_name: magento2-devbox-db
    restart: always
    image: mysql:5.6
    ports:
      - $db_home_port:$db_port
    environment:
      - MYSQL_ROOT_PASSWORD=$db_password
      - MYSQL_DATABASE=$db_name
    volumes:
      - $db_home_path:$db_path
      - $db_home_logs_path:$db_logs_path
  $rabbitmq_host:
    container_name: magento2-devbox-rabbit
    image: rabbitmq:3-management
    ports:
      - $rabbitmq_home_admin_port:$rabbitmq_admin_port
      - $rabbitmq_home_port:$rabbitmq_port
  $redis_host:
    container_name: magento2-devbox-redis
    image: redis:3.0.7
  varnish:
    image: magento/magento2devbox_varnish:latest
    container_name: $varnish_container
    ports:
      - $varnish_home_port:$varnish_port
  $elastic_host:
    image: elasticsearch:latest
    container_name: magento2-devbox-elasticsearch
    ports:
      - $elastic_home_port:$elastic_port
  $webserver_host:
#    image: magento/magento2devbox_web:latest
    build: web
    container_name: $webserver_container
    volumes:
      - $magento_home_path:$magento_path
      - $composer_path:$composer_home_path
      - $ssh_path:$ssh_home_path
      - $webserver_home_apache_logs_path:$webserver_apache_logs_path
      - $webserver_home_phpfpm_logs_path:$webserver_phpfpm_logs_path
#      - $magento_cloud_path:$magento_cloud_home_path
    ports:
      - $webserver_home_port:$webserver_port
      - $webserver_home_ssh_port:$webserver_ssh_port
EOM

echo 'Creating shared and temporary folders'
mkdir -p shared/.composer
mkdir -p shared/.ssh
mkdir -p shared/webroot
mkdir -p shared/db
mkdir -p shared/logs/apache2
mkdir -p shared/logs/php-fpm
mkdir -p shared/logs/mysql
mkdir -p tmp

echo 'Build docker images'
docker-compose up --build -d

docker exec -it --privileged magento2-devbox-web \
    /bin/sh -c "chown -R magento2:magento2 /home/magento2 && chown -R magento2:magento2 $magento_path"

docker exec -it --privileged -u magento2 magento2-devbox-web \
    php -f /home/magento2/scripts/m2init magento:install \
        --magento-sources-reuse=$magento_sources_reuse \
        --magento-path=$magento_path \
        --webserver-host=$webserver_host \
        --webserver-port=$webserver_port \
        --db-host=$db_host \
        --db-port=$db_port \
        --db-user=$db_user \
        --db-name=$db_name \
        --db-password=$db_password \
        --rabbitmq-host=$rabbitmq_host \
        --rabbitmq-port=$rabbitmq_port \
        --redis-host=$redis_host \
        --varnish-config-path=$varnish_config_path \
        --elastic-host=$elastic_host \
        --elastic-port=$elastic_port

docker cp $webserver_container:/home/magento2/scripts/default.vcl tmp/default.vcl.bak
docker cp tmp/default.vcl.bak $varnish_container:/etc/varnish/default.vcl
docker-compose restart varnish

rm -rf tmp

#!/bin/bash


get_free_port () {
    local port=$1
    while [[ $(lsof -i tcp:$port | grep "(LISTEN)") ]]
    do
        port=$RANDOM
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
            if echo $value | grep -Eiq '^(?:[1y]|yes|true)$'; then
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

if [[ $webroot_path ]]; then
    use_existing_sources=1
else
    webroot_path='./shared/webroot'

    if [[ ! $use_existing_sources ]]; then
        request 'use_existing_sources' 'Do you have existing copy of Magento 2?' 1
    fi

    if [[ $use_existing_sources = 1 ]]; then
        request 'webroot_path' 'Please provide full path to the magento2 folder'
    fi
fi

if [[ ! $composer_path ]]; then
    composer_path='./shared/.composer'
fi

if [[ ! $ssh_path ]]; then
    ssh_path='./shared/.ssh'
fi

if [[ ! $db_path ]]; then
    db_path='./shared/db'
fi

db_host=db
db_port=3306
db_password=root
db_user=root
db_name=magento2
db_host_port=$(get_free_port 1345)

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
      - "$db_host_port:$db_port"
    environment:
      - MYSQL_ROOT_PASSWORD=$db_password
      - MYSQL_DATABASE=$db_name
    volumes:
      - $db_path:/var/lib/mysql
EOM

rabbit_host='rabbit'
rabbit_port=5672
rabbit_admin_host_port=$(get_free_port 8282)
rabbit_host_port=$(get_free_port $rabbit_port)
  cat << EOM >> docker-compose.yml
  $rabbit_host:
    container_name: magento2-devbox-rabbit
    image: rabbitmq:3-management
    ports:
      - "$rabbit_admin_host_port:15672"
      - "$rabbit_host_port:$rabbit_port"
EOM

redis_host='redis'

cat << EOM >> docker-compose.yml
  $redis_host:
    container_name: magento2-devbox-redis
    image: redis:3.0.7
EOM

varnish_host_port=$(get_free_port 1748)
varnish_host_container=magento2-devbox-varnish

cat << EOM >> docker-compose.yml
  varnish:
    image: magento/magento2devbox_varnish:latest
    container_name: $varnish_host_container
    ports:
      - "$varnish_host_port:6081"
EOM

elastic_host='elasticsearch'
elastic_port=9200
elastic_local_port=$(get_free_port 9200)
cat << EOM >> docker-compose.yml
  $elastic_host:
    image: elasticsearch:latest
    container_name: magento2-devbox-elasticsearch
    ports:
      - "$elastic_local_port:$elastic_port"
EOM

magento_path='/var/www/magento2'
main_host=web
main_host_port=80
main_host_container=magento2-devbox-web

web_port=$(get_free_port 1749)
cat << EOM >> docker-compose.yml
  $main_host:
    # image: magento/magento2devbox_web:latest
    build: web
    container_name: $main_host_container
    volumes:
      - $webroot_path:$magento_path
      - $composer_path:/home/magento2/.composer
      - $ssh_path:/home/magento2/.ssh
      #    - ./shared/.magento-cloud:/root/.magento-cloud
    ports:
      - "$web_port:$main_host_port"
      - "2222:22"
EOM

echo 'Creating shared folders'
mkdir -p shared/.composer
mkdir -p shared/.ssh
mkdir -p shared/webroot
mkdir -p shared/db

echo 'Build docker images'
docker-compose up --build -d

docker exec -it --privileged magento2-devbox-web \
    /bin/sh -c 'chown -R magento2:magento2 /home/magento2 && chown -R magento2:magento2 /var/www/magento2'


magento_sample_data=1
backend_path=admin
admin_user=admin
admin_password=admin123
install_rabbitmq=1
redis_cache=1
redis_fpc=0
redis_session=1
static_deploy=0
static_grunt_compile=0
di_compile=0

docker exec -it --privileged -u magento2 magento2-devbox-web \
    php -f /home/magento2/scripts/m2init magento:install \
        --use-existing-sources=$use_existing_sources \
        --magento-sample-data=$magento_sample_data \
        --backend-path=$backend_path \
        --admin-user=$admin_user \
        --admin-password=$admin_password \
        --rabbitmq-install=$install_rabbitmq \
        --rabbitmq-host=$rabbit_host \
        --rabbitmq-port=$rabbit_port \
        --redis-cache=$redis_cache \
        --redis-fpc=$redis_fpc \
        --redis-session=$redis_session \
        --redis-host=$redis_host \
        --magento-path=$magento_path \
        --db-host=$db_host \
        --db-port=$db_port \
        --db-user=$db_user \
        --db-name=$db_name \
        --db-password=$db_password \
        --backend-host=$main_host \
        --backend-port=$main_host_port \
        --out-file-path=/home/magento2/scripts/default.vcl \
        --static-deploy=$static_deploy \
        --static-grunt-compile=$static_grunt_compile \
        --di-compile=$di_compile \
        --elastic-host=$elastic_host --elastic-port=$elastic_port

docker cp "$main_host_container:/home/magento2/scripts/default.vcl" ./default.vcl.bak
docker cp ./default.vcl.bak $varnish_host_container:/etc/varnish/default.vcl
rm ./default.vcl.bak

docker-compose restart varnish

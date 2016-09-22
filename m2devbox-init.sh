#!/bin/bash

generate_container_name () {
    local service=$1
    local number=1
    local name="magento2devbox_${service}_${number}"

    while [[ `docker ps -a -q --filter="name=$name"` ]]; do
        ((number++))
        name="magento2devbox_${service}_${number}"
    done

    echo $name
}

get_data () {
    local file_name=$1
    local folder_path='tmp'
    local file_path="$folder_path/$file_name"
    local contents

    if [ -f $file_path ]; then
        contents=$(cat $file_path)
    fi

    echo $contents
}

store_data () {
    local file_name=$1
    local value=$2
    local delimiter=$3
    local key=$4
    local key_value_delimiter=$5
    local prefix=$6
    local suffix=$7
    local folder_path='tmp'
    local file_path="$folder_path/$file_name"
    local contents=$(get_data $file_name)

    if [[ $contents ]]; then
        contents="$contents$delimiter"
    fi

    contents="$contents$prefix"

    if [[ $key ]]; then
        contents="$contents$key$key_value_delimiter"
    fi

    contents="$contents$value$suffix"
    mkdir -p $folder_path && echo $contents > $file_path
    echo $value
}

store_option () {
    local key=$1
    local value=$2

    store_data 'options' $value ' ' $key '=' '--' &> /dev/null
    echo $value
}

get_free_port () {
    local port=$1
    local used_ports=$(get_data 'ports')

    while [[ ! $port ]] || [[ $(lsof -i tcp:$port | grep "(LISTEN)") ]] || [[ $used_ports == *"|$port|"* ]]; do
        port=$(jot -r 1 1 65000)
    done

    store_data 'ports' $port '' '' '' '|' '|' &> /dev/null

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

echo 'Creating docker-compose config'

#Database
db_container=$(generate_container_name 'db')
db_host=$(store_option 'db-host' 'db')
db_user=$(store_option 'db-user' 'root')
db_password=$(store_option 'db-password' 'root')
db_name=$(store_option 'db-name' 'magento2')
db_port=$(store_option 'db-port' 3306)
db_home_port=$(get_free_port 1345)
db_path='/var/lib/mysql'
db_logs_path='/var/log/mysql'
db_home_logs_path='./shared/logs/mysql'

if [[ ! $db_home_path ]]; then
    db_home_path='./shared/db'
fi

#RabbitMQ
rabbitmq_container=$(generate_container_name 'rabbit')
rabbitmq_host=$(store_option 'rabbitmq-host' 'rabbit')
rabbitmq_port=$(store_option 'rabbitmq-port' 5672)
rabbitmq_admin_port=15672
rabbitmq_home_port=$(get_free_port $rabbitmq_port)
rabbitmq_home_admin_port=$(get_free_port 8282)

#Redis
redis_container=$(generate_container_name 'redis')
redis_host=$(store_option 'redis-host' 'redis')

#Varnish
varnish_container=$(generate_container_name 'varnish')
varnish_host='varnish'
varnish_port=6081
varnish_home_port=$(get_free_port 1749) && $(store_option 'varnish-home-port' $varnish_home_port) &> /dev/null
varnish_config_dir='/home/magento2/configs/varnish'
varnish_config_path=$(store_option 'varnish-config-path' "$varnish_config_dir/default.vcl")
varnish_shared_dir="./shared/configs/varnish"
varnish_container_config_path='/etc/varnish/default'

#Elastic Search
elastic_container=$(generate_container_name 'elastic')
elastic_host=$(store_option 'elastic-host' 'elasticsearch')
elastic_port=$(store_option 'elastic-port' 9200)
elastic_home_port=$(get_free_port 9200)

#Web Server
webserver_container=$(generate_container_name 'web')
webserver_host=$(store_option 'webserver-host' 'web')
webserver_port=$(store_option 'webserver-port' 80)
webserver_ssh_port=22
webserver_home_port=$(get_free_port 1748) && $(store_option 'webserver-home-port' $webserver_home_port) &> /dev/null
webserver_home_ssh_port=$(get_free_port 2222)
webserver_apache_logs_path='/var/log/apache2'
webserver_phpfpm_logs_path='/var/log/php-fpm'
webserver_home_apache_logs_path='./shared/logs/apache2'
webserver_home_phpfpm_logs_path='./shared/logs/php-fpm'

#Magento
magento_host=$(store_option 'magento-host' 'localhost')
magento_path=$(store_option 'magento-path' '/home/magento2/magento2')
magento_cloud_path='/root/.magento-cloud'
composer_path='/home/magento2/.composer'
ssh_path='/home/magento2/.ssh'

while [ $# -gt 0 ]; do
    case $1 in
        -it)
            interactive=1
            shift
            ;;
        --*)
            key=$(echo $1 | sed -e 's/^--\([^=]*\)=[^=]*$/\1/g')
            var_name=$(echo $key | sed -e 's/-/_/g')
            value=$(echo $1 | sed -e 's/^[^=]*=//g')
            export $var_name=$value
            store_option $key $value &> /dev/null
            shift
            ;;
        *)
            echo "Error: Unexpected argument \"$1\"!"
            exit
            ;;
    esac
done

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

if [[ ! $magento_cloud_home_path ]]; then
    magento_cloud_home_path='./shared/.magento-cloud'
fi

if [[ ! $composer_home_path ]]; then
    composer_home_path='./shared/.composer'
fi

if [[ ! $ssh_home_path ]]; then
    ssh_home_path='./shared/.ssh'
fi

store_option 'magento-sources-reuse' $magento_sources_reuse &> /dev/null

cat > docker-compose.yml <<- EOM
##
# Services needed to run Magento2 application on Docker
#
# Docker Compose defines required services and attach them together through aliases
##
version: '2'
services:
  $webserver_host:
    container_name: $webserver_container
    restart: always
#    image: magento/magento2devbox_web:latest
    build: web
    volumes:
      - "$magento_home_path:$magento_path"
      - "$composer_home_path:$composer_path"
      - "$ssh_home_path:$ssh_path"
      - "$webserver_home_apache_logs_path:$webserver_apache_logs_path"
      - "$webserver_home_phpfpm_logs_path:$webserver_phpfpm_logs_path"
      - "$varnish_shared_dir:$varnish_config_dir"
#      - "$magento_cloud_home_path:$magento_cloud_path"
    ports:
      - "$webserver_home_port:$webserver_port"
      - "$webserver_home_ssh_port:$webserver_ssh_port"
  $db_host:
    container_name: $db_container
    restart: always
    image: mysql:5.6
    ports:
      - "$db_home_port:$db_port"
    environment:
      - MYSQL_ROOT_PASSWORD=$db_password
      - MYSQL_DATABASE=$db_name
    volumes:
      - "$db_home_path:$db_path"
      - "$db_home_logs_path:$db_logs_path"
  $varnish_host:
    container_name: $varnish_container
    restart: always
    depends_on:
      - "$webserver_host"
#    image: magento/magento2devbox_varnish:latest
    build: varnish
    volumes:
      - "$varnish_shared_dir:$varnish_container_config_path"
    ports:
      - "$varnish_home_port:$varnish_port"
  $redis_host:
    container_name: $redis_container
    restart: always
    image: redis:3.0.7
  $rabbitmq_host:
    container_name: $rabbitmq_container
    restart: always
    image: rabbitmq:3-management
    ports:
      - "$rabbitmq_home_admin_port:$rabbitmq_admin_port"
      - "$rabbitmq_home_port:$rabbitmq_port"
  $elastic_host:
    container_name: $elastic_container
    restart: always
    image: elasticsearch:latest
    ports:
      - "$elastic_home_port:$elastic_port"
EOM

echo 'Creating shared folders'
mkdir -p $composer_home_path
mkdir -p $ssh_home_path
mkdir -p $magento_home_path
mkdir -p $db_home_path
mkdir -p $webserver_home_apache_logs_path
mkdir -p $webserver_home_phpfpm_logs_path
mkdir -p $db_home_logs_path
mkdir -p $varnish_shared_dir

echo 'Build docker images'
docker-compose up --build -d

cat > m2devbox.sh <<- EOM
#!/bin/bash

case \$1 in
    exec|show-name)
        command=\$1
        shift
        ;;
    *)
        echo 'Wrong command: only "exec" and "show-name" are supported'
        exit
        ;;
esac

while [ \$# -gt 0 ]; do
    options="\$options \$1"
    shift
done

if [[ \$command = 'exec' ]]; then
    docker exec -it --privileged -u magento2 $webserver_container\$options
fi

if [[ \$command = 'show-name' ]]; then
    echo $webserver_container
fi

EOM

chmod +x m2devbox.sh
options=$(get_data 'options')

if [[ $interactive != 1 ]]; then
    options="$options --no-interaction"
fi

./m2devbox.sh exec php -f /home/magento2/scripts/m2init magento:install $options
rm -rf tmp

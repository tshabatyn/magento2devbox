if (Test-Path tmp) {
    Remove-Item tmp -Recurse -Force
}

function get_data ($file_name, $folder_path='tmp', $file_path="$folder_path/$file_name", $contents) {
    if (Test-Path $file_path) {
        $contents=$(type $file_path)
    }

    return $contents
}

function store_data
    ($file_name, $value, $delimiter, $key, $key_value_delimiter, $prefix,
    $suffix, $folder_path = 'tmp', $file_path = "$folder_path/$file_name", $contents = (get_data $file_name))
    {
    if ($contents) {
        $contents = "$contents$delimiter"
    }

    $contents = "$contents$prefix"

    if ($key) {
        $contents = "$contents$key$key_value_delimiter"
    }

    $contents="$contents$value$suffix"

    New-Item -ItemType directory -Path $folder_path
    $contents | Out-File $file_path

    return $value | Out-Null
}

function store_option ($key, $value) {
    store_data 'options' $value ' ' $key '=' '--' 2>$null

    return $value
}

function get_free_port ($port, $used_ports=(get_data 'ports')) {
    while ((!$port) -or (netstat -ano | findstr $port | Select-String -Pattern ".*?TCP.*:$port\s.*LISTENING") -or ($used_ports -contains "|$port|")) {
        $port = Get-Random -Maximum 65000 -Minimum 1
    }

    store_data 'ports' $port '' '' '' '|' '|' 2>$null

    return $port
}

function request ($varName, $question, $isBoolean, $defaultValue, $value, $output) {
    if ($isBoolean -eq $true) {
        if ($defaultValue -eq $true) {
            $question = "$question [Y/n]"
        } else {
            $question="$question [y/N]"
        }
    } else {
        if ($defaultValue -ne $null) {
            $question="$question [default: $defaultValue]"
        }
    }

    $value = Read-Host "$question"
    $value = $value.Trim()

    if ($value) {
        if ($isBoolean -eq $true) {
            if (Select-String -Pattern "^(?:[1y]|yes|true)$" -InputObject $value) {
                $value = 1
                $output = 'yes'
            } else {
                $value = 0
                $output = 'no'
            }
        }
    } else {
        if ($isBoolean -eq $true) {
            if ($defaultValue -eq $true) {
                $value = 1
                $output = 'yes'
            } else {
                $value = 0
                $output = 'no'
            }
        } else {
            $value = $defaultValue
            $output = $value
        }
    }

    Set-Variable -Name $varName -Value $value -Scope Global
    return $output | Out-Null
}

Write-Host "Creating docker-compose config"

#Database
$db_user = store_option 'db-user' 'root'
$db_host = store_option 'db-host' 'db'
$db_password = store_option 'db-password' 'root'
$db_name = store_option 'db-name' 'magento2'
$db_port = store_option 'db-port' 3306
$db_home_port = get_free_port 1345
$db_path = '/var/lib/mysql'
$db_logs_path = '/var/log/mysql'
$db_home_logs_path = './shared/logs/mysql'

if (!$db_home_path) {
    $db_home_path = './shared/db'
}

#RabbitMQ
$rabbitmq_host = store_option 'rabbitmq-host' 'rabbit'
$rabbitmq_port = store_option 'rabbitmq-port' 5672
$rabbitmq_admin_port = 15672
$rabbitmq_home_port = get_free_port 5672
$rabbitmq_home_admin_port = get_free_port 8282

#Redis
$redis_host = store_option 'redis-host' 'redis'

#Varnish
$varnish_port = 6081
$varnish_home_port = get_free_port 1748
$varnish_config_dir = '/home/magento2/configs/varnish'
$varnish_config_path = store_option 'varnish-config-path' "$varnish_config_dir/default.vcl"
$varnish_shared_dir = "./shared/configs/varnish"
$varnish_container_config_path = '/etc/varnish/default'

#Elastic Search
$elastic_host = store_option 'elastic-host' 'elasticsearch'
$elastic_port = store_option 'elastic-port' 9200
$elastic_home_port = get_free_port 9200

#Web Server
$webserver_host = store_option 'webserver-host' 'web'
$webserver_port = store_option 'webserver-port' 80
$webserver_ssh_port = 22
$webserver_home_port = get_free_port 1749
$webserver_home_ssh_port = get_free_port 2222
$webserver_apache_logs_path = '/var/log/apache2'
$webserver_phpfpm_logs_path = '/var/log/php-fpm'
$webserver_home_apache_logs_path = './shared/logs/apache2'
$webserver_home_phpfpm_logs_path = './shared/logs/php-fpm'

#Paths
$magento_path = store_option 'magento-path' '/var/www/magento2'
$magento_cloud_path = '/root/.magento-cloud'
$composer_path = '/home/magento2/.composer'
$ssh_path = '/home/magento2/.ssh'

if ($Args.Length -gt 0) {
    foreach ($argument in $Args) {
        switch -regex ($argument)
        {
            ^-it$ { $interactive = 1 }
            --.+ {
                    $argumentKey = $argument -match '^--(.*)='
                    if ($argumentKey) {
                        $key = $matches[1]
                    }

                    $var_name = $key -replace "-","_"

                    $argumentValue = $argument -match '^--(.*)=(.*)'
                    if ($argumentValue) {
                        $value = $matches[2]
                    }

                    Set-Variable -Name $var_name -Value $value -Scope Global
                    store_option $key $value | Out-Null
                }
            default { echo "Error: Unexpected argument $argument!" }
        }
    }
}

if ($magento_home_path) {
    $magento_sources_reuse = $true
} else {
    $magento_home_path='./shared/webroot'

    if (!$magento_sources_reuse) {
        request 'magento_sources_reuse' 'Do you have existing copy of Magento 2?' $true
    }
    if ($magento_sources_reuse -eq $true) {
        request 'magento_home_path' 'Please provide full path to the Magento folder on local machine'
    }
}

if (!$magento_cloud_home_path) {
    $magento_cloud_home_path = './shared/.magento-cloud'
}

if (!$composer_home_path) {
    $composer_home_path = './shared/.composer'
}

if (!$ssh_home_path) {
    $ssh_home_path = './shared/.ssh'
}

store_option 'magento-sources-reuse' $magento_sources_reuse | Out-Null

$yml = @"
##
# Services needed to run Magento2 application on Docker
#
# Docker Compose defines required services and attach them together through aliases
##
version: '2'
services:
  %%%DB_HOST%%%:
      restart: always
      image: mysql:5.6
      ports:
          - "%%%DB_HOME_PORT%%%:%%%DB_PORT%%%"
      environment:
          - MYSQL_ROOT_PASSWORD=%%%DB_PASSWORD%%%
          - MYSQL_DATABASE=%%%DB_NAME%%%
      volumes:
          - "%%%DB_HOME_PATH%%%:%%%DB_PATH%%%"
          - "%%%DB_HOME_LOGS_PATH%%%:%%%DB_LOGS_PATH%%%"
  %%%RABBITMQ_HOST%%%:
      image: rabbitmq:3-management
      ports:
          - "%%%RABBITMQ_HOME_ADMIN_PORT%%%:%%%RABBITMQ_ADMIN_PORT%%%"
          - "%%%RABBITMQ_HOME_PORT%%%:%%%RABBITMQ_PORT%%%"
  %%%REDIS_HOST%%%:
      image: redis:3.0.7
  varnish:
#      image: magento/magento2devbox_varnish:latest
      build: varnish
      volumes:
          - "%%%VARNISH_SHARED_DIR%%%:%%%VARNISH_CONTAINER_CONFIG_PATH%%%"
      ports:
          - "%%%VARNISH_HOME_PORT%%%:%%%VARNISH_PORT%%%"
  %%%ELASTIC_HOST%%%:
      image: elasticsearch:latest
      ports:
          - "%%%ELASTIC_HOME_PORT%%%:%%%ELASTIC_PORT%%%"
  %%%WEBSERVER_HOST%%%:
#     image: magento/magento2devbox_web:latest
      build: web
      volumes:
          - "%%%MAGENTO_HOME_PATH%%%:%%%MAGENTO_PATH%%%"
          - "%%%COMPOSER_HOME_PATH%%%:%%%COMPOSER_PATH%%%"
          - "%%%SSH_HOME_PATH%%%:%%%SSH_PATH%%%"
          - "%%%WEBSERVER_HOME_APACHE_LOGS_PATH%%%:%%%WEBSERVER_APACHE_LOGS_PATH%%%"
          - "%%%WEBSERVER_HOME_PHPFPM_LOGS_PATH%%%:%%%WEBSERVER_PHPFPM_LOGS_PATH%%%"
          - "%%%VARNISH_SHARED_DIR%%%:%%%VARNISH_CONFIG_DIR%%%"
#         - "%%%MAGENTO_CLOUD_HOME_PATH%%%:%%%MAGENTO_CLOUD_PATH%%%"
      ports:
          - "%%%WEBSERVER_HOME_PORT%%%:%%%WEBSERVER_PORT%%%"
          - "%%%WEBSERVER_HOME_SSH_PORT%%%:%%%WEBSERVER_SSH_PORT%%%"
"@

$yml = $yml -Replace "%%%DB_HOST%%%", $db_host
$yml = $yml -Replace "%%%DB_HOME_PORT%%%", $db_home_port
$yml = $yml -Replace "%%%DB_PORT%%%", $db_port
$yml = $yml -Replace "%%%DB_PASSWORD%%%", $db_password
$yml = $yml -Replace "%%%DB_NAME%%%", $db_name
$yml = $yml -Replace "%%%DB_HOME_PATH%%%", $db_home_path
$yml = $yml -Replace "%%%DB_PATH%%%", $db_path
$yml = $yml -Replace "%%%DB_HOME_LOGS_PATH%%%", $db_home_logs_path
$yml = $yml -Replace "%%%DB_LOGS_PATH%%%", $db_logs_path
$yml = $yml -Replace "%%%RABBITMQ_HOST%%%", $rabbitmq_host
$yml = $yml -Replace "%%%RABBITMQ_HOME_ADMIN_PORT%%%", $rabbitmq_home_admin_port
$yml = $yml -Replace "%%%RABBITMQ_ADMIN_PORT%%%", $rabbitmq_admin_port
$yml = $yml -Replace "%%%RABBITMQ_HOME_PORT%%%", $rabbitmq_home_port
$yml = $yml -Replace "%%%RABBITMQ_PORT%%%", $rabbitmq_port
$yml = $yml -Replace "%%%REDIS_HOST%%%", $redis_host
$yml = $yml -Replace "%%%VARNISH_SHARED_DIR%%%", $varnish_shared_dir
$yml = $yml -Replace "%%%VARNISH_CONTAINER_CONFIG_PATH%%%", $varnish_container_config_path
$yml = $yml -Replace "%%%VARNISH_HOME_PORT%%%", $varnish_home_port
$yml = $yml -Replace "%%%VARNISH_PORT%%%", $varnish_port
$yml = $yml -Replace "%%%ELASTIC_HOST%%%", $elastic_host
$yml = $yml -Replace "%%%ELASTIC_HOME_PORT%%%", $elastic_home_port
$yml = $yml -Replace "%%%ELASTIC_PORT%%%", $elastic_port
$yml = $yml -Replace "%%%WEBSERVER_HOST%%%", $webserver_host
$yml = $yml -Replace "%%%MAGENTO_HOME_PATH%%%", $magento_home_path
$yml = $yml -Replace "%%%MAGENTO_PATH%%%", $magento_path
$yml = $yml -Replace "%%%COMPOSER_HOME_PATH%%%", $composer_home_path
$yml = $yml -Replace "%%%COMPOSER_PATH%%%", $composer_path
$yml = $yml -Replace "%%%SSH_HOME_PATH%%%", $ssh_home_path
$yml = $yml -Replace "%%%SSH_PATH%%%", $ssh_path
$yml = $yml -Replace "%%%WEBSERVER_HOME_APACHE_LOGS_PATH%%%", $webserver_home_apache_logs_path
$yml = $yml -Replace "%%%WEBSERVER_APACHE_LOGS_PATH%%%", $webserver_apache_logs_path
$yml = $yml -Replace "%%%WEBSERVER_HOME_PHPFPM_LOGS_PATH%%%", $webserver_home_phpfpm_logs_path
$yml = $yml -Replace "%%%WEBSERVER_PHPFPM_LOGS_PATH%%%", $webserver_phpfpm_logs_path
$yml = $yml -Replace "%%%VARNISH_CONFIG_DIR%%%", $varnish_config_dir
$yml = $yml -Replace "%%%MAGENTO_CLOUD_HOME_PATH%%%", $magento_cloud_home_path
$yml = $yml -Replace "%%%MAGENTO_CLOUD_PATH%%%", $magento_cloud_path
$yml = $yml -Replace "%%%WEBSERVER_HOME_PORT%%%", $webserver_home_port
$yml = $yml -Replace "%%%WEBSERVER_PORT%%%", $webserver_port
$yml = $yml -Replace "%%%WEBSERVER_HOME_SSH_PORT%%%", $webserver_home_ssh_port
$yml = $yml -Replace "%%%WEBSERVER_SSH_PORT%%%", $webserver_ssh_port
Set-Content docker-compose.yml $yml

Write-Host "Creating shared folders"
if ((Test-Path $composer_home_path) -eq 0) {
    mkdir $composer_home_path
}
if ((Test-Path $ssh_home_path) -eq 0) {
    mkdir $ssh_home_path
}
if ((Test-Path $magento_home_path) -eq 0) {
    mkdir $magento_home_path
}
if ((Test-Path $db_home_path) -eq 0) {
    mkdir $db_home_path
}
if ((Test-Path $webserver_home_apache_logs_path) -eq 0) {
    mkdir $webserver_home_apache_logs_path
}
if ((Test-Path $webserver_home_phpfpm_logs_path) -eq 0) {
    mkdir $webserver_home_phpfpm_logs_path
}
if ((Test-Path $db_home_logs_path) -eq 0) {
    mkdir $db_home_logs_path
}
if ((Test-Path $varnish_shared_dir) -eq 0) {
    mkdir $varnish_shared_dir
}

Write-Host "Build docker images"

docker-compose up --build -d

$webserver_container = `docker-compose ps -q $webserver_host`
docker exec -it --privileged $webserver_container /bin/sh -c "chown -R magento2:magento2 /home/magento2 && chown -R magento2:magento2 $magento_path"

$options = get_data 'options'

if ($interactive -ne 1) {
    $options = "$options --no-interaction"
}

docker exec -it --privileged -u magento2 $webserver_container php -f /home/magento2/scripts/m2init magento:install $options

Remove-Item tmp -Recurse -Force

clear-variable -name magento_home_path
clear-variable -name magento_sources_reuse

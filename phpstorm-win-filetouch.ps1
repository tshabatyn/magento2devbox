Param($arguments)
docker exec -it --privileged -u magento2 magento2-devbox-web touch /var/www/magento2/$Args[0]

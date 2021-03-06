FROM centos:latest
MAINTAINER Yuriy Sklyarenko <iskliarenko@magento.com>

# Additional repos
RUN yum install -y --nogpgcheck http://www.percona.com/downloads/percona-release/redhat/0.1-4/percona-release-0.1-4.noarch.rpm \
       http://rpms.remirepo.net/enterprise/remi-release-7.rpm \
        && echo -e "\nip_resolve=4\nerrorlevel=0\nrpmverbosity=critical" >> /etc/yum.conf \
        && yum update --enablerepo=remi-php70 -y --nogpgcheck && yum install -d 0 --nogpgcheck --enablerepo=remi-php70 -y vim rsync less which openssh-server cronie sudo \
            bash-completion bash-completion-extras mod_ssl mc nano dos2unix unzip lsof pv telnet zsh patch python2-pip net-tools git tmux htop wget \
            httpd httpd-tools \
            php php-cli php-mcrypt php-mbstring php-soap php-pecl-xdebug php-xml php-bcmath phpmyadmin \
            php-pecl-memcached php-pecl-redis php-pdo php-gd php-mysqlnd php-intl php-pecl-zip \
            ruby ruby-devel sqlite-devel make gcc gcc-c++ \
            php-mongodb mongodb mongodb-server \
            Percona-Server-server-56 Percona-Server-client-56 \

# Install tidyways
        && echo -e "[tideways]\nname = Tideways\nbaseurl = https://s3-eu-west-1.amazonaws.com/qafoo-profiler/rpm" > /etc/yum.repos.d/tideways.repo \
        && rpm --import https://s3-eu-west-1.amazonaws.com/qafoo-profiler/packages/EEB5E8F4.gpg \
        && yum makecache --disablerepo=* --enablerepo=tideways \
        && yum install -y --nogpgcheck tideways-php tideways-cli && yum clean all \

# Mailcatcher
        && gem install mailcatcher --no-ri --no-rdoc

# PHP 
ADD ./scripts/php-ext-switch.sh /usr/local/bin/
RUN ln -s /usr/local/bin/php-ext-switch.sh /usr/local/bin/xdebug-sw.sh && /usr/local/bin/xdebug-sw.sh 0 \
        && echo -e "xdebug.remote_enable = 1 \nxdebug.remote_autostart = 1\nxdebug.remote_host=10.254.254.254\nxdebug.max_nesting_level = 100000" >> /etc/php.d/15-xdebug.ini \
        && sed -i -e "s/;date.timezone\s*=/date.timezone = 'UTC'/g" /etc/php.ini \
        && sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 64M/g" /etc/php.ini \
        && sed -i -e "s/post_max_size\s*=\s*2M/post_max_size = 64M/g" /etc/php.ini \
        && sed -i -e "s/memory_limit\s*=\s*128M/memory_limit = 768M/g" /etc/php.ini \
        && sed -i -e "s/sendmail_path\s=\s\/usr\/sbin\/sendmail\s-t\s-i/sendmail_path=\/usr\/bin\/env catchmail -f sparta@docker.local/g" /etc/php.ini \

# Tideways PHP profiler
        && echo -e "tideways.auto_prepend_library=0\ntideways.framework=magento2\n" >> /etc/php.d/40-tideways.ini \
        && ln -s /usr/local/bin/php-ext-switch.sh /usr/local/bin/tideways-sw.sh && /usr/local/bin/tideways-sw.sh 0 \

# Apache
        && sed -i -e "s/AllowOverride\s*None/AllowOverride All/g" /etc/httpd/conf/httpd.conf \
        && sed -i -e "s/#OPTIONS=/OPTIONS=-DFOREGROUND/g" /etc/sysconfig/httpd \
        && sed -i -e "s/#ServerName\s*www.example.com:80/ServerName local.magento/g" /etc/httpd/conf/httpd.conf \
        && sed -i -e "s/FALSE/TRUE/g" /etc/phpMyAdmin/config.inc.php \
        && echo "Header always set Strict-Transport-Security 'max-age=0'" >> /etc/httpd/conf/httpd.conf \
        && echo "umask 002" >> /etc/profile \
# MongoDB
        && sed -i -e "s/fork\s*=\s*true/fork = false/g" /etc/mongod.conf \ 
        && sed -i -e "s/bind_ip\s*=\s*127.0.0.1/#bind_ip = 127.0.0.1/g" /etc/mongod.conf  

# MySQL
ADD ./conf/daemons/mysql-sparta.cnf /etc/mysql/my.cnf

# SSH
ADD ./conf/daemons/.terminal /home/apache/.terminal
ADD ./conf/magento/docker.pem.pub /etc/ssh/authorized_keys
ADD ./conf/magento/docker.pem /etc/ssh/docker.pem
RUN echo 'root:root' | chpasswd && /usr/bin/ssh-keygen -A \
        && echo 'apache:apache' | chpasswd && chsh apache -s /bin/bash && usermod -d /home/apache apache \
        && chown -R apache.apache /var/www \
        && sed -i -e "s/AuthorizedKeysFile\s*\.ssh\/authorized_keys/AuthorizedKeysFile \/etc\/ssh\/authorized_keys/g" /etc/ssh/sshd_config \
        && chmod 400 /etc/ssh/authorized_keys && chown apache.apache /etc/ssh/authorized_keys \
        && cp /root/.bashrc /home/apache && ln -s /home/apache/.bashrc /home/apache/.bash_profile \
        && echo -e "\nsource ~/.terminal\n" >> /home/apache/.bashrc \
        && echo 'apache ALL=(ALL:ALL) NOPASSWD:ALL' >> /etc/sudoers

# Magento tools
ADD ./conf/magento/auth.json /home/apache/.composer/auth.json
ADD ./conf/magento/.m2install.conf /home/apache/.m2install.conf
ADD ./scripts/m2modtgl.sh /usr/local/bin/m2modtgl.sh
RUN find /home/apache/ -exec chown apache.apache {} \; \
        && ln -s /usr/local/bin/m2modtgl.sh /usr/local/bin/m2modon \
        && ln -s /usr/local/bin/m2modtgl.sh /usr/local/bin/m2modoff \
        && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer && chmod +x /usr/bin/composer \
        && curl -o /usr/bin/m2install.sh https://raw.githubusercontent.com/yvoronoy/m2install/master/m2install.sh && chmod +x /usr/bin/m2install.sh \
        && curl -o /usr/bin/convert-for-composer.php https://raw.githubusercontent.com/isitnikov/m2-convert-patch-for-composer-install/master/convert-for-composer.php \
        && chmod +x /usr/bin/convert-for-composer.php \
        && curl -o /usr/bin/n98-magerun2 https://files.magerun.net/n98-magerun2.phar && chmod +x /usr/bin/n98-magerun2 \
# Tools from Performance team https://gist.github.com/kandy
        && mkdir -p /usr/share/magetools/sql \
        && curl -o /usr/share/magetools/inline_profiler_autoprepend.php https://gist.githubusercontent.com/kandy/7ae16d74e2bdc35ffd7b524f089259c2/raw/1f7392faade651a1e4b28f317f6b3706a61622ea/autoprepend.php \
        && curl -o /usr/share/magetools/sql/bootstrap.php https://gist.githubusercontent.com/kandy/4e07735185dfdfe30cb58eba5cc87ece/raw/68f052c5b1093bf3e59f02df9235b5c59d828267/bootstrap.php \
        && curl -o /usr/share/magetools/sql/env.php https://gist.githubusercontent.com/kandy/4e07735185dfdfe30cb58eba5cc87ece/raw/68f052c5b1093bf3e59f02df9235b5c59d828267/env.php \

# Supervisor config
        && mkdir /var/log/supervisor/ && /usr/bin/easy_install supervisor && /usr/bin/easy_install supervisor-stdout && rm /tmp/* -rf
ADD ./conf/daemons/supervisord.conf /etc/supervisord.conf

# XHGUI & PhpMyAdmin
ADD ./conf/daemons/aliases.conf /etc/httpd/conf.d/aliases.conf
RUN rm /etc/httpd/conf.d/phpMyAdmin.conf  && mkdir /usr/share/xhgui \
        && git clone https://github.com/kandy/xhgui.git /usr/share/xhgui \
        && /usr/bin/composer install -d /usr/share/xhgui \
        && find /usr/share/xhgui /var/log/httpd /root/.composer -exec chown apache.apache {} \; 

# Initialization startup script
ADD ./scripts/start.sh /start.sh
RUN chmod 755 /start.sh && /bin/bash /start.sh

EXPOSE 22 80 81 443 3306 27017

ENTRYPOINT [ "/start.sh" ]

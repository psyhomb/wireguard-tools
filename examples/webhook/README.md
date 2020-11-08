wgcg with webhook
=================

Here we're going to show how we can use [wgcg.sh](../../README.md) tool in combination with [webhook](https://github.com/adnanh/webhook) service to create endpoint from where client will be able to download WireGuard configuration.

We'll assume that [wgcg.sh](../../README.md) is already configured and ready to use.

The only difference from standard configuration is that you will have to create 2 configuration files if you plan to configure 2 WireGuard servers behind LB and to set valid SSH IP address (`WGCG_SERVER_SSH_IP`) in both configuration files, all other settings should be the same:

- `/root/wireguard/wgcg/wg-1.conf`
- `/root/wireguard/wgcg/wg-2.conf`

Preparation
-----------

Copy all the scripts from local [bin](./bin) to `/usr/local/bin` directory on the remote server where [wgcg.sh](../../README.md) script is already installed.

Download, install and configure `webhook` and `nginx` services.

### Webhook

Install `webhook` binary.

```bash
WEBHOOK_VERSION="2.7.0"
wget https://github.com/adnanh/webhook/releases/download/${WEBHOOK_VERSION}/webhook-linux-amd64.tar.gz
tar xzvf webhook-linux-amd64.tar.gz
mv webhook-linux-amd64/webhook /usr/local/bin/webhook_${WEBHOOK_VERSION}
cd /usr/local/bin
chown root:root webhook_${WEBHOOK_VERSION}
ln -snf webhook_${WEBHOOK_VERSION} webhook
cd
```

Specify command line options that will be used by `webhook` service.

```bash
cat > /etc/default/webhook <<'EOF'
### SSL termination on Webhook layer
#OPTIONS="-hooks=/etc/webhook/hooks.json -hotreload -ip 127.0.0.1 -port 9000 -secure -cert /etc/letsencrypt/live/wgcg.yourdomain.com/fullchain.pem -key /etc/letsencrypt/live/wgcg.yourdomain.com/privkey.pem -verbose"

### SSL termination on Nginx layer
OPTIONS="-hooks=/etc/webhook/hooks.json -hotreload -ip 127.0.0.1 -port 9000 -verbose"
EOF
```

Create systemd unit for `webhook` service.

```bash
systemctl edit --force --full webhook.service
```

```plain
[Unit]
Description=Webhook Service
Documentation=https://github.com/adnanh/webhook

[Service]
EnvironmentFile=/etc/default/webhook
ExecStart=/usr/local/bin/webhook $OPTIONS
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Create first part of `webhook` configuration file that will be used by our scripts to automatically generate the main configuration file => `/etc/webhook/hooks.json`

```bash
mkdir -p /etc/webhook && cat > /etc/webhook/main.json <<'EOF'
[
  {
    "id": "wgcg",
    "execute-command": "/usr/local/bin/wgcg-html-gpg.sh",
    "include-command-output-in-response": true,
    "response-headers": [
      {
        "name": "Cache-Control",
        "value": "no-store, no-cache, must-revalidate"
      }
    ],
    "pass-arguments-to-command": [
      {
        "source": "url",
        "name": "servername"
      },
      {
        "source": "url",
        "name": "username"
      }
    ],
    "trigger-rule": {}
  }
]
EOF
```

### Nginx

Install `nginx` service.

```bash
apt install nginx
```

Create vhost configuration.

**Note:** Don't forget to replace `wgcg.yourdomain.com` domain name with real domain name and to generate certificate for it (see `certbot` section down below).

```bash
cat > /etc/nginx/sites-available/wgcg.yourdomain.com.conf <<'EOF'
# Disable emitting nginx version
server_tokens off;

# Sets the maximum allowed size of the client request body
# Setting size to 0 disables checking of client request body size
#client_max_body_size 0;

server {
    listen 80 default_server;
    server_name wgcg.yourdomain.com;

    #access_log /var/log/nginx/wgcg.yourdomain.com-acme_access.log;
    #error_log  /var/log/nginx/wgcg.yourdomain.com-acme_error.log;

    ## https://certbot.eff.org/docs/using.html#webroot
    #location ^~ /.well-known/acme-challenge/ {
    #    root /usr/share/nginx/wgcg.yourdomain.com;
    #}

    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name wgcg.yourdomain.com;

    access_log /var/log/nginx/wgcg.yourdomain.com_access.log;
    error_log  /var/log/nginx/wgcg.yourdomain.com_error.log;

    ssl_certificate         /etc/letsencrypt/live/wgcg.yourdomain.com/fullchain.pem;
    ssl_certificate_key     /etc/letsencrypt/live/wgcg.yourdomain.com/privkey.pem;
    #ssl_trusted_certificate /etc/nginx/conf.d/ssl/ca-certs.pem;

    ssl_session_cache   shared:SSL:20m;
    ssl_session_timeout 10m;

    ssl_prefer_server_ciphers       on;
    ssl_protocols                   TLSv1.2 TLSv1.3;
    ssl_ciphers                     ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:ECDH+3DES:DH+3DES:RSA+AESGCM:RSA+AES:RSA+3DES:!aNULL:!MD5:!DSS;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";

    location /healthcheck {
        add_header Content-Type "text/plain";
        return 200 "OK";
    }

    location / {
        #satisfy all;

        #allow 10.0.0.0/8;
        #deny  all;

        auth_basic "wgcg";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
```

Disable `default` vhost and enable our newly added vhost configuration.

```bash
cd /etc/nginx/sites-enabled
rm -f default
ln -snf /etc/nginx/sites-available/wgcg.yourdomain.com.conf
cd
```

Create `test` user that will be used for Nginx Basic Auth.

Install required utils.

```bash
apt install apache2-utils
```

Create a user.

```bash
htpasswd -c /etc/nginx/.htpasswd test
```

Use Let's Encrypt with [certbot](https://certbot.eff.org/all-instructions) client to generate certificates if needed.

```bash
apt install certbot
```

**Note:** We're using DNS TXT RR for verification because our Nginx instance isn't internet-facing.

```bash
certbot certonly --manual --preferred-challenges dns
```

**Note:** Please be sure to name it exactly like it is specified in the Nginx configuration file.

```bash
certbot certificates
```

Fire up
-------

Now when all the components are in place we are ready to fire up the services.

Generate webhook's main configuration file => `/etc/webhook/hooks.json`

**Note:** This script has to be executed only once and before `webhook` service is started for the first time.

```bash
wh.py
```

Enable and start `webhook` and restart `nginx` service.

```bash
systemctl enable --now webhook
systemctl restart nginx
```

Check if everything is running without errors.

```bash
journalctl -fu webhook
journalctl -fu nginx
```

Usage
-----

Generate client configuration.

```bash
wgcg-gen.sh add test@yourdomain.com 10.0.0.2
```

Remove client configuration.

```bash
wgcg-gen.sh remove test@yourdomain.com
```

List existing clients.

```bash
wgcg-gen.sh list
```

When new client is added, URL where client can download configuration will be printed out.

Example:

https://wgcg.yourdomain.com/hooks/wgcg?servername=server1&username=test@yourdomain.com&token=QwhRKi2WNz9UFqqUE6nZsNckQ2jDQtGfqqvCl6kC

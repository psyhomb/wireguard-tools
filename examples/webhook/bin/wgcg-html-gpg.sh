#!/bin/bash
# Author: Milos Buncic
# Date: 2020/06/10
# Description: Generate HTML page with GPG encrypted WireGuard configuration file

SERVER_NAME=${1}
USERNAME=${2}

CONFIG_GPG_FILE="/root/wireguard/${SERVER_NAME}/client-${USERNAME}.conf.asc"
if [[ ! -f "${CONFIG_GPG_FILE}" ]]; then
  exit 1
fi

echo '<html>
<head>
  <title>wgcg</title>
  <link rel="shortcut icon" href="https://www.yourdomain.com/favicon.ico" type="image/x-icon">
  <style>
    body {
      background-color: #eeeeee;
      text-align: center;
      padding: 20px;
      font: 20px Helvetica, sans-serif;
      color: #5d5b5d;
    }

    img {
      height: auto;
      width: auto;
      display: block;
      margin-left: auto;
      margin-right: auto;
    }

    a {
      color: #884595;
      text-decoration: none;
    }

    a:hover {
      color: #271b3c;
      text-decoration: none;
    }

    h1.pink {
      color: #884595;
      text-decoration: none;
      text-align: center;
      font: 30px Helvetica, sans-serif;
    }

    span.darkpink {
      color: #271b3c;
      text-decoration: none;
      font: 45px Helvetica, sans-serif;
    }

    span.small {
      color: #884595;
      text-decoration: none;
      font: 20px Helvetica, sans-serif;
    }

    pre code {
      text-align: left;
      border: 1px solid #999999;
      padding: 20px;
      display: block;
    }
  </style>
</head>

<body>
  <h1 class="pink">'"${USERNAME}"'</h1>
  <br>

  <center>
  <table>
    <tr>
      <th><pre><code><p># Install required packages<br>brew install wireguard-tools gpg</p></pre></code></th>
    </tr>
    <tr>
      <th><pre><code><p># Create encrypted configuration file<br>cat > /tmp/'"${SERVER_NAME}"'.conf.asc <<"EOF"<br>'$(sed "s/$/<br>/" ${CONFIG_GPG_FILE} | tr -d "\n")'EOF</p></pre></code></th>
    </tr>
    <tr>
      <th><pre><code><p># Decrypt configuration file and set permissions<br>mkdir -p /usr/local/etc/wireguard && \<br>gpg -o /usr/local/etc/wireguard/'"${SERVER_NAME}"'.conf -d /tmp/'"${SERVER_NAME}"'.conf.asc && \<br>chmod 600 /usr/local/etc/wireguard/'"${SERVER_NAME}"'.conf && \<br>rm -f /tmp/'"${SERVER_NAME}"'.conf.asc</p></pre></code></th>
    </tr>
    <tr>
      <th><pre><code><p># Bring up the VPN tunnel<br>wg-quick up '"${SERVER_NAME}"'</p></pre></code></th>
    </tr>
    <tr>
      <th><pre><code><p># Bring down the VPN tunnel<br>wg-quick down '"${SERVER_NAME}"'</p></pre></code></th>
    </tr>
  </table>
  </center>

</body>
</html>
'

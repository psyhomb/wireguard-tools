#!/bin/bash
# Author: Milos Buncic
# Date: 2020/06/10
# Description: Generate HTML page with embedded base64 encoded QRCode

SERVER_NAME=${1}
USERNAME=${2}

QRCODE_FILE="/root/wireguard/${SERVER_NAME}/client-${USERNAME}.conf.png"
if [[ ! -f "${QRCODE_FILE}" ]]; then
  exit 1
fi

BASE64_QRCODE=$(echo -n `base64 "${QRCODE_FILE}"` | sed 's/ \+//g')

echo '<html>
<head>
  <title>wgcg</title>
  <link rel="shortcut icon" href="https://www.yourdomain.com/favicon.ico" type="image/x-icon">
  <style>
    body {
      background-color: #eeeeee;
      text-align: center;
      padding: 150px;
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
    }
  </style>
</head>

<body>
  <h1 class="pink">'"${USERNAME}"'</h1>
  <img alt="QRCode" src="data:image/png;base64,'"${BASE64_QRCODE}"'" />
  <br>

  <label for="showConfig">Show config:</label>
  <input type="checkbox" id="showConfig" onclick="showOnCheck()">

  <center>
  <table>
    <tr>
      <th><pre><code><p id="text" style="display:none">'$(sed "s/$/<br>/" ${QRCODE_FILE%.*} | tr -d "\n")'</p></pre></code></th>
    </tr>
  </table>
  </center>

  <script>
  function showOnCheck() {
    var checkBox = document.getElementById("showConfig");
    var text = document.getElementById("text");
    if (checkBox.checked == true){
      text.style.border = "1px solid #999999";
      text.style.padding = "20px";
      text.style.display = "block";
    } else {
      text.style.border = "0px";
      text.style.display = "none";
    }
  }
  </script>

</body>
</html>
'

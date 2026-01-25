Tesla's recent rollout of fleet-telemetry empowers authorized users to seamlessly stream real-time data directly from Tesla vehicles. Let's delve into the process of initiating live data streaming from a Tesla vehicle.

To make this as smooth as possible, a few important notes:

I created a Postman collection to help with the API requests sent during this tutorial.
The latest documentation for Tesla's Fleet API is available here.
Create a Developer Account
To begin your quest for data, first create a developer account on Tesla's official developer portal: developer.tesla.com.

I recommend selecting all scopes as there is no downside. Here is my configuration for Client Details:

Client Details of Tesla developer application

Finishing Application Registration
Once your developer application is created, you must register it with Fleet API.

This includes submitting a certificate signing request (CSR) to Tesla. To create one, first generate a private key.



openssl ecparam -name prime256v1 -genkey -noout -out private-key.pem


Now, derive its public key.



openssl ec -in private-key.pem -pubout -out public-key.pem


Make this public key accessible at: https://your-domain.com/.well-known/appspecific/com.tesla.3p.public-key.pem

Note: there are two domains you may use throughout this tutorial. The first one is your public domain users are familiar with (such as your-domain.com). This is the domain you host your public key on. The second domain is the domain your fleet-telemetry server is exposed on (such as tesla-telemetry.your-domain.com).

Now, using the private key, create a CSR.



openssl req -out your-domain.com.csr -key private_key.pem -subj /CN=your-domain.com/ -new


With all this created, let's send it to Tesla.

In Postman, fill in your environment variables (client id, client secret, scopes, audience, redirect uri).
Send the "Generate Partner Token" request.
Send the "Register Partner Account" request.
Input the appropriate domain and csr in the body.
Sample body:



{
  "domain": "your-domain.com",
  "csr": "-----BEGIN CERTIFICATE REQUEST-----\ncert_data\n-----END CERTIFICATE REQUEST-----\n
}


Once this is submitted, Tesla will process the CSR and update your account on the backend accordingly. It may take a few weeks to process. In the meanwhile, check out all the capabilities of Fleet API.

After CSR Confirmation
Once you receive a confirmation email from Tesla, you can begin configuring your fleet-telemetry server. Since the server will need to be accessible to the world, I am using a Linode nano server to run everything.

1. Create another CSR (optional)
If the domain your fleet-telemetry server will be on is different from the domain used in the CSR above, create a new CSR for this domain.

2. Obtain a Certificate and CA Bundle
Next, we need to obtain a certificate for fleet-telemetry to use for TLS connections. There are many ways to do this, but I opted for a free and simple soution: LetsEncrypt and Certbot.

Note: Ensure your server's DNS is configured for this to work.



# install certbot
sudo snap install --classic certbot

# ensure certbot command can be run
sudo ln -s /snap/bin/certbot /usr/bin/certbot

# create the certificate
# when offered http server or validation files, I opted for http server (option 1)
certbot certonly -d tesla-telemetry.your-domain.com --csr tesla-telemetry.your-domain.com.csr



The output of this last command should tell you where the certificate and full certificate chain are located. Copy these files into an easy to access directory.



Successfully received certificate.
Certificate is saved at:            /root/fleet-telemetry/0000_cert.pem
Intermediate CA chain is saved at:  /root/fleet-telemetry/0000_chain.pem
Full certificate chain is saved at: /root/fleet-telemetry/0001_chain.pem


Create fleet-telemetry config
The fleet-telemetry server takes a JSON configuration file. You can take this template and customize accordingly:



{
  "host": "0.0.0.0",
  "hostname": "tesla-telemetry.your-domain.com",
  "port": 443,
  "log_level": "debug",
  "json_log_enable": true,
  "namespace": "telemetry",
  "reliable_ack": false,
  "rate_limit": {
    "enabled": false,
    "message_limit": 100
  },
  "records": {
    "alerts": [
        "logger"
    ],
    "errors": [
        "logger"
    ],
    "V": [
          "logger"
      ]
  },
  "tls": {
    "server_cert": "path to certificate from previous step",
    "server_key": "path to private key"
  },
  "ca": "content of full certificate chain file from previous step"
}


The hostname and ca fields are not required. They must be included to use the check_server_cert.sh script later in tutorial.

Start your server
There are many ways to start your fleet-telemetry server. I opted to use Docker with the following docker-compose.yml:



version: '3.8'

services:
  app:
    build:
      context: ./repo
    ports:
      - 0.0.0.0:443:443
    volumes:
      - /path/on/host/to/certs:/config
      - /path/on/host/to/config.json:/etc/fleet-telemetry/config.json
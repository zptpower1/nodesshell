#!/bin/bash

curl -L https://raw.githubusercontent.com/nezhahq/scripts/main/agent/install.sh -o agent.sh && chmod +x agent.sh && env NZ_SERVER=cc01-ts.v9.gg:8008 NZ_TLS=false NZ_CLIENT_SECRET=nkug7L2XTGgdgOKNzZU8dWYF7aAr3wWS ./agent.sh
rm agent.sh